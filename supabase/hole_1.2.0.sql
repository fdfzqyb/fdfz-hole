-- FDFZ 樹洞 v1.2.0：回覆評分、再找上次那位、站內未讀提示
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次（要先跑過 hole_1.1.2_help.sql）。
--
-- 1. 回覆評分：發出者可以給每位回覆過的傾聽者打「有幫助／普通／沒幫助」，隨時可以改。
--    評分只影響之後的派單權重，並在管理後台的傾聽者名單顯示統計；傾聽者看不到。
-- 2. 再找上次那位：發新訊息時可以指定之前回覆過自己的傾聽者。對方先收到這張單（照樣匿名、可以拒絕）；
--    對方暫停接單、名額已滿或不在了，就照常隨機派。
-- 3. 站內未讀提示：記錄雙方各自讀到哪一則，底部導覽列和列表顯示未讀數。

begin;

-------------------------------------------------------------------------------
-- 資料表
-------------------------------------------------------------------------------

alter table hole_assignments
  add column rating smallint check (rating between 1 and 3), -- 發出者的評分：3 有幫助、2 普通、1 沒幫助
  add column rated_at timestamptz,
  add column requested boolean not null default false,       -- 發出者指定找這位（再找上次那位）
  add column poster_read_id bigint not null default 0,       -- 發出者讀到哪一則 hole_messages.id
  add column listener_read_id bigint not null default 0;     -- 傾聽者讀到哪一則

-- 已有的對話一律當作讀過，上線時不會突然跳出一堆未讀
update hole_assignments a
set poster_read_id = m.last, listener_read_id = m.last
from (select assignment_id, max(id) as last from hole_messages group by assignment_id) m
where m.assignment_id = a.id;

-------------------------------------------------------------------------------
-- 派送：多了 prefer（指定的傾聽者）與評分權重
-------------------------------------------------------------------------------

drop function hole_dispatch(bigint, bigint);

-- 幫一則訊息補足傾聽者到 target_listeners 位，回傳這次新派了幾位。
-- carry：第一位新傾聽者要帶過去的舊對話（換人時用）。
-- prefer：發出者指定的傾聽者，先試著派給他（條件和一般派單相同），不符合就照常抽。
-- 加權隨機：手上對話少、比較久沒被派到、回覆率高、評分高的人權重高；
-- 用 -ln(u)/w 排序取第一名，等同按權重抽籤，任何人都無法預測自己會接到誰。
create function hole_dispatch(tid bigint, carry bigint default null, prefer uuid default null) returns int
language plpgsql security definer set search_path = public as $$
declare
  c hole_config;
  t hole_threads;
  poster_sid text;
  need int;
  pick uuid;
  added int := 0;
begin
  select * into c from hole_config;
  select * into t from hole_threads where id = tid for update;
  if not found or t.closed_at is not null then
    return 0;
  end if;
  select student_id into poster_sid from profiles where id = t.poster_id;

  select c.target_listeners + t.extra_listeners - count(*) into need
  from hole_assignments where thread_id = tid and status in ('pending', 'accepted');

  while need > 0 loop
    select l.user_id into pick
    from hole_listeners l
    join profiles p on p.id = l.user_id
    cross join lateral (
      select count(*) as n from hole_assignments x
      where x.listener_id = l.user_id and x.status in ('pending', 'accepted')) act
    cross join lateral (
      select avg(case when x.first_reply_at is not null then 1.0 else 0.0 end) as r
      from (select first_reply_at from hole_assignments x
            where x.listener_id = l.user_id and x.status <> 'pending'
            order by x.offered_at desc limit 20) x) rr
    cross join lateral (
      -- 最近 20 次評分的平均（1～3）；少於 3 次不計，避免一兩次評分影響太大
      select case when count(*) >= 3 then avg(x.rating) end as s
      from (select rating from hole_assignments x
            where x.listener_id = l.user_id and x.rating is not null
            order by x.rated_at desc limit 20) x) rt
    where p.verify_status = 'approved'
      and l.quiz_passed_at is not null and l.pledge_version = c.pledge_version
      and l.suspended_at is null and l.available
      and act.n < c.max_active
      and l.user_id <> t.poster_id
      and not (t.topic = any (l.avoid_topics))
      and not exists (select 1 from hole_blocks b
                      where b.poster_id = t.poster_id and b.listener_id = l.user_id)
      and not exists (select 1 from hole_assignments x
                      where x.thread_id = tid and x.listener_id = l.user_id)
      and not (t.avoid_classmates and left(p.student_id, 6) = left(poster_sid, 6))
      and (prefer is null or l.user_id = prefer)
    order by -ln(1 - random()) / (
        (1.0 / (1 + act.n))
      * (1 + least(extract(epoch from now() - coalesce(l.last_assigned_at, now() - interval '3 days')) / 86400, 3))
      * (0.5 + coalesce(rr.r, 1))
      * (0.6 + 0.4 * (coalesce(rt.s, 2) - 1)))  -- 評分平均 1 → 0.6、2 → 1.0、3 → 1.4
    limit 1
    for update of l skip locked;

    if pick is null and prefer is not null then
      prefer := null;  -- 指定的人現在接不了，改成照常抽
      continue;
    end if;
    exit when pick is null;

    insert into hole_assignments (thread_id, listener_id, carried_from, requested)
    values (tid, pick, carry, prefer is not null);
    update hole_listeners set last_assigned_at = now() where user_id = pick;
    insert into hole_email_outbox (user_id, kind) values (pick, 'new_offer');
    added := added + 1;
    need := need - 1;
    carry := null;
    prefer := null;
  end loop;

  return added;
end $$;
revoke execute on function hole_dispatch(bigint, bigint, uuid) from public, anon, authenticated;

-------------------------------------------------------------------------------
-- 發出者
-------------------------------------------------------------------------------

drop function hole_post(hole_topic, text, boolean);

-- 發訊息。回傳 { thread_id, show_help, preferred }：
-- show_help 為 true 時前端顯示求助資源；有指定傾聽者時 preferred 表示這次有沒有派給他。
-- p_prefer：之前某段對話的 assignment id（hole_my_threads 裡 can_request_again 的那幾段）。
create function hole_post(p_topic hole_topic, p_body text, p_avoid_classmates boolean default false,
                          p_prefer bigint default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c hole_config;
  tid bigint;
  want uuid;
begin
  if not is_approved() then
    raise exception '帳號還沒通過校園卡驗證';
  end if;
  select * into c from hole_config;
  if (select count(*) from hole_threads where poster_id = auth.uid() and closed_at is null)
     >= c.max_open_threads then
    raise exception '你已經有 % 則還沒結束的訊息，先結束一則再發', c.max_open_threads;
  end if;
  if p_prefer is not null then
    select a.listener_id into want
    from hole_assignments a join hole_threads t on t.id = a.thread_id
    where a.id = p_prefer and t.poster_id = auth.uid() and a.first_reply_at is not null;
    if want is null then
      raise exception '找不到之前那段對話';
    end if;
  end if;

  insert into hole_threads (poster_id, topic, body, avoid_classmates)
  values (auth.uid(), p_topic, btrim(p_body), coalesce(p_avoid_classmates, false))
  returning id into tid;

  perform hole_dispatch(tid, null, want);
  return jsonb_build_object(
    'thread_id', tid,
    'show_help', hole_mentions_crisis(p_body),
    'preferred', case when want is not null then
      exists (select 1 from hole_assignments where thread_id = tid and requested) end);
end $$;

-- 發出者：我的訊息和每段對話。傾聽者以「傾聽者 1、2…」稱呼，不含任何 user id。
-- waiting = 已派出、還沒人接下的數量；unread = 對方傳來、我還沒讀的訊息數；
-- can_rate = 對方回覆過，可以評分；can_request_again = 發新訊息時可以指定再找這位
create or replace function hole_my_threads() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id, 'topic', t.topic, 'body', t.body, 'avoid_classmates', t.avoid_classmates,
    'swap_count', t.swap_count, 'created_at', t.created_at, 'closed_at', t.closed_at,
    'waiting', (select count(*) from hole_assignments a
                where a.thread_id = t.id and a.status = 'pending'),
    'conversations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'assignment_id', a.id, 'label', '傾聽者 ' || a.n,
        'active', a.status = 'accepted',
        'accepted_at', a.accepted_at, 'ended_at', a.ended_at,
        'waiting_since', case when a.status = 'accepted' then a.poster_waiting_since end,
        'can_request_extra', a.status = 'accepted' and t.closed_at is null
          and a.poster_waiting_since < now() - (select extra_after from hole_config)
          and a.extra_requested_at is null
          and t.extra_listeners < (select max_extra_listeners from hole_config),
        'rating', a.rating,
        'can_rate', a.first_reply_at is not null,
        'can_request_again', a.first_reply_at is not null
          and not exists (select 1 from hole_blocks b
                          where b.poster_id = t.poster_id and b.listener_id = a.listener_id),
        'unread', (select count(*) from hole_messages m
                   where m.assignment_id = a.id and not m.from_poster and m.id > a.poster_read_id)
        ) order by a.accepted_at)
      from (select a.*, row_number() over (order by a.accepted_at) as n
            from hole_assignments a
            where a.thread_id = t.id and a.accepted_at is not null) a), '[]'::jsonb)
  ) order by t.created_at desc), '[]'::jsonb)
  from hole_threads t
  where t.poster_id = auth.uid();
$$;

-- 給回覆過的傾聽者評分：3 有幫助、2 普通、1 沒幫助。可以改；傾聽者看不到。
create function hole_rate(aid bigint, p_rating int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_rating not between 1 and 3 then
    raise exception '評分錯誤';
  end if;
  update hole_assignments a set rating = p_rating, rated_at = now()
  from hole_threads t
  where a.id = aid and t.id = a.thread_id and t.poster_id = auth.uid()
    and a.first_reply_at is not null;
  if not found then
    raise exception '對方回覆之後才能評分';
  end if;
end $$;

-------------------------------------------------------------------------------
-- 傾聽者
-------------------------------------------------------------------------------

-- 傾聽者：派給我的單。接下之前只有話題標籤，沒有原文。
-- status：pending 待接、active 進行中、ended 對方已結束（被換或發出者結束，不區分）、
--         expired 逾時、left 我已退出
-- requested：發出者之前和你聊過，這次指定找你；unread：對方傳來、我還沒讀的訊息數
create or replace function hole_my_assignments() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'assignment_id', a.id, 'topic', t.topic,
    'status', case a.status
                when 'pending' then 'pending'
                when 'accepted' then 'active'
                when 'swapped' then 'ended'
                when 'closed' then 'ended'
                else a.status::text end,
    'offered_at', a.offered_at, 'accepted_at', a.accepted_at, 'ended_at', a.ended_at,
    'body', case when a.accepted_at is not null then t.body end,
    'has_history', a.carried_from is not null and a.accepted_at is not null,
    'requested', a.requested,
    'unread', (select count(*) from hole_messages m
               where m.assignment_id = a.id and m.from_poster and m.id > a.listener_read_id)
  ) order by a.offered_at desc), '[]'::jsonb)
  from hole_assignments a join hole_threads t on t.id = a.thread_id
  where a.listener_id = auth.uid()
    and (a.status = 'pending' or a.accepted_at is not null);
$$;

-------------------------------------------------------------------------------
-- 雙方：已讀
-------------------------------------------------------------------------------

-- 打開一段對話時呼叫，把自己這一方標成讀到最新一則
create function hole_mark_read(aid bigint) returns void
language plpgsql security definer set search_path = public as $$
declare
  newest bigint;
begin
  select coalesce(max(id), 0) into newest from hole_messages where assignment_id = aid;
  update hole_assignments a
  set poster_read_id = case when t.poster_id = auth.uid() then greatest(a.poster_read_id, newest) else a.poster_read_id end,
      listener_read_id = case when a.listener_id = auth.uid() then greatest(a.listener_read_id, newest) else a.listener_read_id end
  from hole_threads t
  where a.id = aid and t.id = a.thread_id and a.accepted_at is not null
    and (t.poster_id = auth.uid() or a.listener_id = auth.uid());
end $$;

-------------------------------------------------------------------------------
-- 管理員：傾聽者名單多了評分統計
-------------------------------------------------------------------------------

create or replace function hole_admin_listeners() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_hole_admin() then
    raise exception '只有樹洞管理員可以查看';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'user_id', l.user_id, 'full_name', p.full_name, 'student_id', p.student_id,
      'qualified', hole_is_qualified(l.user_id), 'available', l.available,
      'quiz_passed_at', l.quiz_passed_at, 'pledged_at', l.pledged_at,
      'timeout_count', l.timeout_count,
      'suspended_at', l.suspended_at, 'suspend_reason', l.suspend_reason,
      'rated_helpful', (select count(*) from hole_assignments x where x.listener_id = l.user_id and x.rating = 3),
      'rated_okay', (select count(*) from hole_assignments x where x.listener_id = l.user_id and x.rating = 2),
      'rated_unhelpful', (select count(*) from hole_assignments x where x.listener_id = l.user_id and x.rating = 1)
      ) order by l.created_at)
    from hole_listeners l join profiles p on p.id = l.user_id), '[]'::jsonb);
end $$;

-------------------------------------------------------------------------------
-- 執行權限
-------------------------------------------------------------------------------

revoke execute on function hole_post(hole_topic, text, boolean, bigint) from public, anon;
revoke execute on function hole_rate(bigint, int) from public, anon;
revoke execute on function hole_mark_read(bigint) from public, anon;
grant execute on function
  hole_post(hole_topic, text, boolean, bigint), hole_rate(bigint, int), hole_mark_read(bigint)
to authenticated;

commit;

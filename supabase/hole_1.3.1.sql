-- FDFZ 樹洞 v1.3.1：修正「多找一位」沒人補上、換人時帶過去的對話被丟掉
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次（重跑也不會出錯）。
--
-- 1. 發出者按「多找一位」時剛好沒有可接單的傾聽者：之前定時任務補派只看 target_listeners，
--    多找的那位永遠不會派出。現在補派會把 extra_listeners 算進去。
-- 2. 換人時勾選「把這段對話也給新的人看」，當下沒人可派的話，之後補派的人看不到舊對話。
--    現在要帶的對話先記在 hole_threads.carry_from，之後派出第一位新傾聽者時帶給他。

begin;

alter table hole_threads add column if not exists carry_from bigint;

create or replace function hole_dispatch(tid bigint, carry bigint default null, prefer uuid default null) returns int
language plpgsql security definer set search_path = public as $$
declare
  c hole_config;
  t hole_threads;
  poster_sid text;
  need int;
  pick uuid;
  saved bigint;
  added int := 0;
begin
  select * into c from hole_config;
  select * into t from hole_threads where id = tid for update;
  if not found or t.closed_at is not null then
    return 0;
  end if;
  select student_id into poster_sid from profiles where id = t.poster_id;
  saved := t.carry_from;

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
    values (tid, pick, coalesce(carry, saved), prefer is not null);
    if carry is null and saved is not null then
      saved := null;
      update hole_threads set carry_from = null where id = tid;
    end if;
    update hole_listeners set last_assigned_at = now() where user_id = pick;
    insert into hole_email_outbox (user_id, kind) values (pick, 'new_offer');
    added := added + 1;
    need := need - 1;
    carry := null;
    prefer := null;
  end loop;

  return added;
end $$;

create or replace function hole_tick() returns void
language plpgsql security definer set search_path = public as $$
declare
  c hole_config;
  r record;
begin
  select * into c from hole_config;

  -- 久沒新訊息的對話自動結束
  update hole_assignments a set status = 'closed', ended_at = now()
  from hole_threads t
  where t.id = a.thread_id and t.closed_at is null
    and t.last_activity_at < now() - c.auto_close_after
    and a.status in ('pending', 'accepted');
  update hole_threads set closed_at = now()
  where closed_at is null and last_activity_at < now() - c.auto_close_after;

  -- 派出後沒人接
  for r in
    update hole_assignments set status = 'expired', ended_at = now()
    where status = 'pending' and offered_at < now() - c.pending_timeout
    returning thread_id, carried_from
  loop
    perform hole_dispatch(r.thread_id, r.carried_from);
  end loop;

  -- 已接下的對話不自動轉派。發出者等了 remind_after 還沒有回覆，就寄一次提醒給傾聽者；
  -- 等滿 extra_after 後由發出者決定要不要多找一位（hole_request_extra）。
  with due as (
    update hole_assignments a set reminded_at = now()
    from hole_threads t
    where t.id = a.thread_id and t.closed_at is null and a.status = 'accepted'
      and a.poster_waiting_since < now() - c.remind_after
      and a.reminded_at is null
    returning a.listener_id)
  insert into hole_email_outbox (user_id, kind)
  select listener_id, 'reply_reminder' from due;

  update hole_listeners
  set suspended_at = now(), suspend_reason = '多次逾時', available = false
  where suspended_at is null and timeout_count >= c.timeout_suspend;

  -- 還沒補滿的訊息再試一次（例如剛好有人切回可接單）；發出者多找的人也要算進去
  for r in
    select t.id from hole_threads t
    where t.closed_at is null
      and (select count(*) from hole_assignments a
           where a.thread_id = t.id and a.status in ('pending', 'accepted')) < c.target_listeners + t.extra_listeners
  loop
    perform hole_dispatch(r.id);
  end loop;
end $$;

create or replace function hole_swap(aid bigint, carry_history boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c hole_config;
  a hole_assignments;
  t hole_threads;
begin
  select * into c from hole_config;
  select * into a from hole_assignments where id = aid for update;
  select * into t from hole_threads where id = a.thread_id for update;
  if not found or t.poster_id is distinct from auth.uid() then
    raise exception '找不到這段對話';
  end if;
  if a.status <> 'accepted' or t.closed_at is not null then
    raise exception '這段對話已經結束';
  end if;

  if t.swap_count >= c.max_swaps then
    perform hole_open_report(t.id, aid, 'swap_limit', null, null);
    return jsonb_build_object('ok', false, 'limit', true);
  end if;

  update hole_assignments set status = 'swapped', ended_at = now() where id = aid;
  insert into hole_blocks (poster_id, listener_id) values (t.poster_id, a.listener_id)
  on conflict do nothing;
  -- 要帶過去的對話先記在訊息上，當下沒人可派時，之後補派的人一樣看得到
  update hole_threads set swap_count = swap_count + 1, last_activity_at = now(),
    carry_from = case when carry_history then aid else carry_from end
  where id = t.id;
  perform hole_dispatch(t.id);
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function hole_dispatch(bigint, bigint, uuid) from public, anon, authenticated;
revoke execute on function hole_tick() from public, anon, authenticated;
revoke execute on function hole_swap(bigint, boolean) from public, anon;
grant execute on function hole_swap(bigint, boolean) to authenticated;

commit;

-- FDFZ 樹洞 v1.5.0：分段加派
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次（要先跑過 hole_1.4.0.sql）。
--
-- 先派 target_listeners 位（2 位）。派出超過 escalate_after（10 分鐘）還沒湊滿兩位接下，
-- 定時任務就再多派 escalate_listeners 位（2 位），誰先接下算誰。湊滿兩位時，其他還沒接的單自動收回，
-- 狀態記為 withdrawn：不算傾聽者沒接、不影響回覆率，傾聽者的列表裡直接消失。
-- 定時任務每 5 分鐘跑一次，所以實際是派出後 10～15 分鐘加派。escalate_listeners 改成 0 就關掉。

-- 新的狀態要在交易外先加好
alter type hole_assign_status add value if not exists 'withdrawn';

begin;

alter table hole_config
  add column escalate_after interval not null default '10 minutes',  -- 派出多久還沒湊滿就加派
  add column escalate_listeners int not null default 2;              -- 加派幾位（0 = 不加派）
alter table hole_threads
  add column surge int not null default 0;                           -- 目前加派中的人數，湊滿後歸零

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

  -- surge：分段加派時暫時多派的人數，湊滿後歸零
  select c.target_listeners + t.extra_listeners + t.surge - count(*) into need
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
            where x.listener_id = l.user_id and x.status not in ('pending', 'withdrawn')
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

  -- 分段加派：派出超過 escalate_after 還沒湊滿，就多派 escalate_listeners 位，誰先接下算誰；
  -- 湊滿時 hole_accept 會收回其他還沒接的單（狀態 withdrawn，不算傾聽者沒接）
  update hole_threads t set surge = c.escalate_listeners
  where t.closed_at is null and t.surge = 0 and c.escalate_listeners > 0
    and exists (select 1 from hole_assignments a
                where a.thread_id = t.id and a.status = 'pending'
                  and a.offered_at < now() - c.escalate_after)
    and (select count(*) from hole_assignments a
         where a.thread_id = t.id and a.status = 'accepted') < c.target_listeners + t.extra_listeners;

  -- 還沒補滿的訊息再試一次（例如剛好有人切回可接單）；發出者多找的人、分段加派的人也要算進去
  for r in
    select t.id from hole_threads t
    where t.closed_at is null
      and (select count(*) from hole_assignments a
           where a.thread_id = t.id and a.status in ('pending', 'accepted')) < c.target_listeners + t.extra_listeners + t.surge
  loop
    perform hole_dispatch(r.id);
  end loop;
end $$;

-- 傾聽者接下。這一則湊滿傾聽者後，收回其他還沒接的單。
create or replace function hole_accept(aid bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  tid bigint;
  sib bigint;
  sib_carry bigint;
begin
  if not hole_is_qualified(auth.uid()) then
    raise exception '你目前沒有傾聽者資格';
  end if;
  update hole_assignments a set status = 'accepted', accepted_at = now(), poster_waiting_since = now()
  from hole_threads t
  where a.id = aid and t.id = a.thread_id
    and a.listener_id = auth.uid() and a.status = 'pending' and t.closed_at is null
  returning a.thread_id into tid;
  if not found then
    raise exception '這張單已經失效，可能已經有其他傾聽者先接下了';
  end if;

  perform 1 from hole_threads where id = tid for update;

  -- 換人時要帶給新傾聽者的舊對話，掛在最早派出的那張單上。分段加派時可能是別人先接下，
  -- 就把舊對話移給先接下的人（只移不複製，仍然只有一位新傾聽者看得到）
  select id, carried_from into sib, sib_carry from hole_assignments
  where thread_id = tid and status = 'pending' and carried_from is not null
  order by offered_at limit 1;
  if sib is not null and (select carried_from from hole_assignments where id = aid) is null then
    update hole_assignments set carried_from = sib_carry where id = aid;
    update hole_assignments set carried_from = null where id = sib;
  end if;
  if (select count(*) from hole_assignments where thread_id = tid and status = 'accepted')
     >= (select c.target_listeners + t.extra_listeners from hole_config c, hole_threads t where t.id = tid) then
    update hole_assignments set status = 'withdrawn', ended_at = now()
    where thread_id = tid and status = 'pending';
    update hole_threads set surge = 0 where id = tid;
  end if;
  return hole_get_conversation(aid);
end $$;

commit;

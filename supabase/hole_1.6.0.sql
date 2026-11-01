-- FDFZ 樹洞 v1.6.0：傾聽者找管理員聊
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次（要先跑過 hole_1.5.0.sql）。
--
-- 傾聽者遇到「不到危機、但不知道怎麼回」或「聽完自己不太舒服」時，可以開一段和管理員的一對一對話。
-- 派送邏輯和派傾聽者類似：從「可接諮詢」的樹洞管理員裡，選手上諮詢最少的一位（同樣多就隨機）；
-- 管理員接下或婉拒，pending_timeout（30 分鐘）沒接就改派別人。傾聽者自己是管理員時不會派給自己。
-- 預設匿名：管理員只看到「一位傾聽者」；傾聽者勾選具名才會顯示姓名。
-- 這段對話和傾聽者手上的對話完全分開，管理員看不到傾聽者和發出者聊了什麼。
-- 派單通知沿用 admin_alert 這種信（「有求助或舉報需要處理」），不用重新部署寄信程式。

begin;

alter table hole_admins add column consult_available boolean not null default true;  -- 可接傾聽者諮詢

create table hole_consults (
  id bigint generated always as identity primary key,
  listener_id uuid not null references profiles(id) on delete cascade,
  admin_id uuid references profiles(id) on delete set null,   -- 目前派給誰；沒人可派時是 null
  status text not null default 'pending' check (status in ('pending', 'active', 'closed')),
  named boolean not null default false,                       -- 傾聽者同意讓管理員看到姓名
  offered_at timestamptz,
  accepted_at timestamptz,
  closed_at timestamptz,
  listener_read_id bigint not null default 0,
  admin_read_id bigint not null default 0,
  created_at timestamptz not null default now()
);
create index on hole_consults (listener_id);
create index on hole_consults (admin_id) where status <> 'closed';

-- 婉拒過的管理員，這段諮詢不再派給他
create table hole_consult_skips (
  consult_id bigint not null references hole_consults on delete cascade,
  admin_id uuid not null references profiles(id) on delete cascade,
  primary key (consult_id, admin_id)
);

-- 訊息只記 consult_id 和誰說的，沒有 user id，所以可以開 Realtime
create table hole_consult_messages (
  id bigint generated always as identity primary key,
  consult_id bigint not null references hole_consults on delete cascade,
  from_listener boolean not null,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index on hole_consult_messages (consult_id, id);

alter table hole_consults enable row level security;
alter table hole_consult_skips enable row level security;
alter table hole_consult_messages enable row level security;
revoke insert, update, delete, truncate on hole_consults, hole_consult_skips, hole_consult_messages from anon, authenticated;
revoke select on hole_consults, hole_consult_skips from anon, authenticated;
revoke select on hole_consult_messages from anon;

-- 自己是不是這段諮詢的一方（管理員要已接下）
create function hole_can_read_consult(cid bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from hole_consults c
    where c.id = cid and (c.listener_id = auth.uid() or (c.admin_id = auth.uid() and c.status <> 'pending')));
$$;
create policy "諮詢雙方可看" on hole_consult_messages for select to authenticated using (hole_can_read_consult(consult_id));

-- 派給一位管理員：可接諮詢、不是傾聽者本人、沒婉拒過；手上諮詢少的優先，剛逾時的那位排最後
create function hole_consult_dispatch(cid bigint, prev uuid default null) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  k hole_consults;
  pick uuid;
begin
  select * into k from hole_consults where id = cid for update;
  if not found or k.status <> 'pending' then
    return false;
  end if;
  select a.user_id into pick
  from hole_admins a join profiles p on p.id = a.user_id
  where a.consult_available and p.verify_status = 'approved'
    and a.user_id <> k.listener_id
    and not exists (select 1 from hole_consult_skips s where s.consult_id = cid and s.admin_id = a.user_id)
  order by (a.user_id = prev),
    (select count(*) from hole_consults x where x.admin_id = a.user_id and x.status <> 'closed'),
    random()
  limit 1;
  update hole_consults set admin_id = pick, offered_at = case when pick is null then null else now() end
  where id = cid;
  if pick is not null then
    insert into hole_email_outbox (user_id, kind) values (pick, 'admin_alert');
  end if;
  return pick is not null;
end $$;

-- 傾聽者開一段諮詢。同時只能有一段沒結束的，再開就回傳原本那段
create function hole_consult_open(p_body text, p_named boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cid bigint;
  body text := btrim(p_body);
begin
  if not is_approved() or not exists (select 1 from hole_listeners where user_id = auth.uid() and quiz_passed_at is not null) then
    raise exception '只有傾聽者可以找管理員聊';
  end if;
  select id into cid from hole_consults where listener_id = auth.uid() and status <> 'closed';
  if cid is not null then
    return jsonb_build_object('id', cid, 'existing', true);
  end if;
  if body is null or char_length(body) not between 1 and 2000 then
    raise exception '先寫下想聊的事';
  end if;
  insert into hole_consults (listener_id, named) values (auth.uid(), coalesce(p_named, false))
  returning id into cid;
  insert into hole_consult_messages (consult_id, from_listener, body) values (cid, true, body);
  update hole_consults set listener_read_id = (select max(id) from hole_consult_messages where consult_id = cid) where id = cid;
  return jsonb_build_object('id', cid, 'existing', false, 'dispatched', hole_consult_dispatch(cid));
end $$;

-- 管理員接下；接下前只看得到「有一位傾聽者想聊」和是否具名
create function hole_consult_accept(cid bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_hole_admin() then
    raise exception '只有樹洞管理員可以處理';
  end if;
  update hole_consults set status = 'active', accepted_at = now()
  where id = cid and admin_id = auth.uid() and status = 'pending';
  if not found then
    raise exception '這則諮詢已經失效';
  end if;
end $$;

-- 管理員這次不行：改派給別人
create function hole_consult_decline(cid bigint) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not is_hole_admin() then
    raise exception '只有樹洞管理員可以處理';
  end if;
  perform 1 from hole_consults where id = cid and admin_id = auth.uid() and status = 'pending' for update;
  if not found then
    raise exception '這則諮詢已經失效';
  end if;
  insert into hole_consult_skips (consult_id, admin_id) values (cid, auth.uid()) on conflict do nothing;
  return hole_consult_dispatch(cid, auth.uid());
end $$;

create function hole_consult_send(cid bigint, p_body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  k hole_consults;
  mine boolean;
  mid bigint;
begin
  select * into k from hole_consults where id = cid for update;
  if not found then
    raise exception '找不到這段對話';
  end if;
  if k.listener_id = auth.uid() then
    mine := true;
  elsif k.admin_id = auth.uid() and k.status = 'active' then
    mine := false;
  else
    raise exception '找不到這段對話';
  end if;
  if k.status = 'closed' then
    raise exception '這段對話已經結束';
  end if;
  if p_body is null or char_length(btrim(p_body)) not between 1 and 2000 then
    raise exception '訊息要 1～2000 個字';
  end if;
  insert into hole_consult_messages (consult_id, from_listener, body) values (cid, mine, btrim(p_body))
  returning id into mid;
  if mine then
    update hole_consults set listener_read_id = mid where id = cid;
  else
    update hole_consults set admin_read_id = mid where id = cid;
  end if;
  return jsonb_build_object('id', mid);
end $$;

create function hole_consult_close(cid bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  update hole_consults set status = 'closed', closed_at = now()
  where id = cid and status <> 'closed'
    and (listener_id = auth.uid() or (admin_id = auth.uid() and status = 'active'));
  if not found then
    raise exception '找不到這段對話';
  end if;
end $$;

-- 打開一段諮詢：回傳訊息並標成已讀。管理員只看得到具名傾聽者的姓名
create function hole_consult_get(cid bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  k hole_consults;
  role text;
  newest bigint;
begin
  select * into k from hole_consults where id = cid;
  if found and k.listener_id = auth.uid() then
    role := 'listener';
  elsif found and k.admin_id = auth.uid() and k.status <> 'pending' then
    role := 'admin';
  else
    raise exception '找不到這段對話';
  end if;
  select coalesce(max(id), 0) into newest from hole_consult_messages where consult_id = cid;
  if role = 'listener' then
    update hole_consults set listener_read_id = newest where id = cid;
  else
    update hole_consults set admin_read_id = newest where id = cid;
  end if;
  return jsonb_build_object(
    'id', k.id, 'role', role, 'status', k.status, 'named', k.named,
    'has_admin', k.admin_id is not null,
    'created_at', k.created_at, 'accepted_at', k.accepted_at, 'closed_at', k.closed_at,
    'listener_name', case when role = 'admin' and k.named then (select full_name from profiles where id = k.listener_id) end,
    'messages', coalesce((select jsonb_agg(jsonb_build_object(
        'id', m.id, 'from', case when m.from_listener = (role = 'listener') then 'me' else 'other' end,
        'body', m.body, 'created_at', m.created_at) order by m.id)
      from hole_consult_messages m where m.consult_id = cid), '[]'::jsonb));
end $$;

-- 傾聽者自己的諮詢
create function hole_my_consults() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', k.id, 'status', k.status, 'has_admin', k.admin_id is not null,
    'created_at', k.created_at, 'accepted_at', k.accepted_at, 'closed_at', k.closed_at,
    'unread', (select count(*) from hole_consult_messages m
               where m.consult_id = k.id and not m.from_listener and m.id > k.listener_read_id)
  ) order by k.created_at desc), '[]'::jsonb)
  from hole_consults k where k.listener_id = auth.uid();
$$;

-- 管理員：派給我的、我接下的，以及最近結束的
create function hole_admin_consults() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_hole_admin() then
    raise exception '只有樹洞管理員可以查看';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', k.id, 'status', k.status, 'named', k.named,
    'listener_name', case when k.named and k.status <> 'pending' then p.full_name end,
    'offered_at', k.offered_at, 'accepted_at', k.accepted_at, 'closed_at', k.closed_at,
    'unread', (select count(*) from hole_consult_messages m
               where m.consult_id = k.id and m.from_listener and m.id > k.admin_read_id)
  ) order by k.status = 'closed', coalesce(k.closed_at, k.offered_at) desc)
  from hole_consults k join profiles p on p.id = k.listener_id
  where k.admin_id = auth.uid()
    and (k.status <> 'closed' or k.closed_at > now() - interval '30 days')), '[]'::jsonb);
end $$;

create function hole_set_consult_available(p_on boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_hole_admin() then
    raise exception '只有樹洞管理員可以處理';
  end if;
  update hole_admins set consult_available = coalesce(p_on, false) where user_id = auth.uid();
end $$;

-- 定時任務的一部分：派出 pending_timeout 沒接的改派別人；還沒派出去的再試一次
create function hole_consult_tick() returns void
language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  for r in
    select id, admin_id from hole_consults
    where status = 'pending'
      and (admin_id is null or offered_at < now() - (select pending_timeout from hole_config))
  loop
    perform hole_consult_dispatch(r.id, r.admin_id);
  end loop;
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

  -- 傾聽者找管理員聊：沒人接的改派
  perform hole_consult_tick();
end $$;

revoke execute on function hole_consult_dispatch(bigint, uuid) from public, anon, authenticated;
revoke execute on function hole_consult_tick() from public, anon, authenticated;
revoke execute on function hole_can_read_consult(bigint), hole_consult_open(text, boolean), hole_consult_accept(bigint),
  hole_consult_decline(bigint), hole_consult_send(bigint, text), hole_consult_close(bigint), hole_consult_get(bigint),
  hole_my_consults(), hole_admin_consults(), hole_set_consult_available(boolean) from public, anon;
grant execute on function hole_can_read_consult(bigint), hole_consult_open(text, boolean), hole_consult_accept(bigint),
  hole_consult_decline(bigint), hole_consult_send(bigint, text), hole_consult_close(bigint), hole_consult_get(bigint),
  hole_my_consults(), hole_admin_consults(), hole_set_consult_available(boolean) to authenticated;

alter publication supabase_realtime add table hole_consult_messages;

commit;

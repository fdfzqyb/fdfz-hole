-- FDFZ 樹洞 v1.1.2：求助通知修正
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次（已經跑過 hole_schema.sql 的資料庫）。
--
-- 1. 發出者還沒有傾聽者接下時，按「我現在需要馬上有人幫忙」也能通知管理員：
--    hole_reports 多記 thread_id，assignment_id 可以是空的（整則訊息層級的求助）。
-- 2. 同一段對話已經有未處理的標記時，另一方再標記會另開一筆；同一方再標記會把新留言接在原紀錄後面，
--    並再通知一次管理員。以前這兩種情況的留言都會被丟掉。

begin;

-------------------------------------------------------------------------------
-- 資料表
-------------------------------------------------------------------------------

alter table hole_reports add column thread_id bigint references hole_threads on delete cascade;
update hole_reports r set thread_id = a.thread_id from hole_assignments a where a.id = r.assignment_id;
alter table hole_reports alter column thread_id set not null;
alter table hole_reports alter column assignment_id drop not null;

-- 留言會累加，上限放寬
alter table hole_reports drop constraint if exists hole_reports_note_check;
alter table hole_reports add constraint hole_reports_note_check check (char_length(note) <= 2000);

-- 未處理的紀錄：同一則訊息、同一段對話、同一種、同一方各只有一筆（雙方各自一筆，不再互相吞掉）
drop index if exists hole_one_open_report;
create unique index hole_one_open_report on hole_reports (thread_id, assignment_id, kind, by_poster)
  nulls not distinct where status = 'open';

-------------------------------------------------------------------------------
-- 建立或累加一筆紀錄
-------------------------------------------------------------------------------

-- 沒有未處理的同類紀錄就新增；有的話把留言接在後面。
-- 新增時一定通知管理員；累加時只有人按的才再通知（by_poster 為 null 的系統紀錄不重複寄信）。
create function hole_open_report(tid bigint, aid bigint, p_kind text, p_by_poster boolean, p_note text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  rid bigint;
  n text := nullif(btrim(left(p_note, 500)), '');
begin
  select id into rid from hole_reports
  where thread_id = tid and assignment_id is not distinct from aid and kind = p_kind
    and by_poster is not distinct from p_by_poster and status = 'open'
  for update;

  if rid is null then
    insert into hole_reports (thread_id, assignment_id, kind, by_poster, note)
    values (tid, aid, p_kind, p_by_poster, n);
    perform hole_alert_admins();
  elsif p_by_poster is not null then
    update hole_reports
    set note = right(concat_ws(E'\n',
          note,
          '（' || to_char(now() at time zone 'Asia/Taipei', 'MM-DD HH24:MI') || ' 再次標記）' || coalesce(n, '')),
        2000)
    where id = rid;
    perform hole_alert_admins();
  end if;
end $$;
revoke execute on function hole_open_report(bigint, bigint, text, boolean, text) from public, anon, authenticated;

-------------------------------------------------------------------------------
-- 發出者與傾聽者
-------------------------------------------------------------------------------

-- 檢舉或標記「需要協助」（雙方都可以，對話不會因此結束）
create or replace function hole_flag(aid bigint, p_kind text, note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  a hole_assignments;
  t hole_threads;
begin
  if p_kind not in ('report', 'need_help') then
    raise exception '類型錯誤';
  end if;
  select * into a from hole_assignments where id = aid;
  select * into t from hole_threads where id = a.thread_id;
  if a.accepted_at is null
     or not (t.poster_id = auth.uid() or a.listener_id = auth.uid()) then
    raise exception '找不到這段對話';
  end if;
  perform hole_open_report(t.id, aid, p_kind, t.poster_id = auth.uid(), note);
end $$;

-- 發出者還沒有進行中的對話時求助：掛在整則訊息上，管理員看得到原訊息，必要時可查發出者身份
create function hole_ask_help(tid bigint, note text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from hole_threads where id = tid and poster_id = auth.uid()) then
    raise exception '找不到這則訊息';
  end if;
  perform hole_open_report(tid, null, 'need_help', true, note);
end $$;
revoke execute on function hole_ask_help(bigint, text) from public, anon;
grant execute on function hole_ask_help(bigint, text) to authenticated;

-- 傾聽者退出。reason = crisis 時建立「需要協助」並通知管理員。
-- 不論原因都會補派一位，避免發出者在危機時身邊的人變少。
create or replace function hole_leave(aid bigint, reason hole_leave_reason, note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  tid bigint;
begin
  update hole_assignments set status = 'left', leave_reason = reason, ended_at = now()
  where id = aid and listener_id = auth.uid() and status = 'accepted'
  returning thread_id into tid;
  if not found then
    raise exception '這段對話已經結束';
  end if;
  if reason = 'crisis' then
    perform hole_open_report(tid, aid, 'need_help', false, note);
  end if;
  perform hole_dispatch(tid);
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
  update hole_threads set swap_count = swap_count + 1, last_activity_at = now() where id = t.id;
  perform hole_dispatch(t.id, case when carry_history then aid end);
  return jsonb_build_object('ok', true);
end $$;

-------------------------------------------------------------------------------
-- 管理員
-------------------------------------------------------------------------------

-- 檢舉列表（不含任何身份）。has_listener = false 是發出者在還沒有傾聽者時的求助。
create or replace function hole_admin_reports(p_status text default 'open') returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_hole_admin() then
    raise exception '只有樹洞管理員可以查看';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'kind', r.kind, 'by_poster', r.by_poster, 'note', r.note,
      'status', r.status, 'resolved_note', r.resolved_note,
      'created_at', r.created_at, 'resolved_at', r.resolved_at,
      'topic', t.topic, 'swap_count', t.swap_count,
      'has_listener', r.assignment_id is not null,
      'conversation_active', t.closed_at is null and (a.id is null or a.status = 'accepted'),
      'leave_reason', a.leave_reason) order by r.created_at desc)
    from hole_reports r
    join hole_threads t on t.id = r.thread_id
    left join hole_assignments a on a.id = r.assignment_id
    where p_status is null or r.status = p_status), '[]'::jsonb);
end $$;

-- 查看被檢舉／標記的那段對話（每次都寫入操作紀錄）。整則訊息層級的求助只有原訊息。
create or replace function hole_admin_view_conversation(report_id bigint, reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  aid bigint;
  tid bigint;
begin
  if not is_hole_admin() then
    raise exception '只有樹洞管理員可以查看';
  end if;
  select assignment_id, thread_id into aid, tid from hole_reports where id = report_id;
  if not found then
    raise exception '找不到這份檢舉';
  end if;
  insert into hole_audit_log (admin_id, action, report_id, reason)
  values (auth.uid(), 'view_conversation', report_id, reason);

  return (
    select jsonb_build_object(
      'topic', t.topic, 'body', t.body, 'thread_created_at', t.created_at,
      'messages', coalesce((
        select jsonb_agg(jsonb_build_object(
          'from', case when m.from_poster then 'poster' else 'listener' end,
          'body', m.body, 'created_at', m.created_at) order by m.id)
        from hole_messages m where m.assignment_id = aid), '[]'::jsonb))
    from hole_threads t
    where t.id = tid);
end $$;

-- 查身份：who = 'poster'（發出者）或 'listener'（傾聽者）。必須填理由，寫入操作紀錄。
create or replace function hole_admin_reveal_identity(report_id bigint, who text, reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid;
  result jsonb;
begin
  if not is_hole_admin() then
    raise exception '只有樹洞管理員可以查詢';
  end if;
  if who not in ('poster', 'listener') then
    raise exception '請選擇要查發出者還是傾聽者';
  end if;
  if char_length(btrim(coalesce(reason, ''))) < 4 then
    raise exception '請填寫查詢理由';
  end if;

  select case who when 'poster' then t.poster_id else a.listener_id end into uid
  from hole_reports r
  join hole_threads t on t.id = r.thread_id
  left join hole_assignments a on a.id = r.assignment_id
  where r.id = report_id;
  if uid is null then
    raise exception '找不到這個人';
  end if;

  insert into hole_audit_log (admin_id, action, report_id, target, reason)
  values (auth.uid(), 'reveal_identity', report_id, who, btrim(reason));

  select jsonb_build_object('full_name', p.full_name, 'student_id', p.student_id, 'email', u.email)
  into result
  from profiles p join auth.users u on u.id = p.id
  where p.id = uid;
  return result;
end $$;

commit;

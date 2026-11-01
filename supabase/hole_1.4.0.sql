-- FDFZ 樹洞 v1.4.0：發出者回覆通知、對話頁常駐「正在找新的傾聽者」
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次（要先跑過 hole_1.3.2.sql）。
-- 另外要重新部署 hole-mailer（多了一種信）。
--
-- 1. hole_user_prefs：發出者可以打開「傾聽者回覆我時寄信」，預設關閉。信件不提樹洞、不含內容，
--    同一位發出者一小時最多一封。
-- 2. hole_my_threads 多回傳 seeking：還缺幾位傾聽者但目前沒人可派。

begin;

create table hole_user_prefs (
  user_id uuid primary key references profiles(id) on delete cascade,
  notify_reply boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table hole_user_prefs enable row level security;
create policy "看自己的設定" on hole_user_prefs for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete, truncate on hole_user_prefs from anon, authenticated;
revoke select on hole_user_prefs from anon;

create function hole_set_notify_reply(p_on boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_approved() then
    raise exception '帳號還沒通過校園卡驗證';
  end if;
  insert into hole_user_prefs (user_id, notify_reply) values (auth.uid(), coalesce(p_on, false))
  on conflict (user_id) do update set notify_reply = excluded.notify_reply, updated_at = now();
end $$;
revoke execute on function hole_set_notify_reply(boolean) from public, anon;
grant execute on function hole_set_notify_reply(boolean) to authenticated;

alter table hole_email_outbox drop constraint hole_email_outbox_kind_check;
alter table hole_email_outbox add constraint hole_email_outbox_kind_check
  check (kind in ('new_offer', 'reply_reminder', 'admin_alert', 'poster_reply'));

create or replace function hole_send_message(aid bigint, p_body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  a hole_assignments;
  t hole_threads;
  i_am_poster boolean;
  mid bigint;
begin
  select * into a from hole_assignments where id = aid for update;
  if not found then
    raise exception '找不到這段對話';
  end if;
  select * into t from hole_threads where id = a.thread_id;
  if t.poster_id = auth.uid() then
    i_am_poster := true;
  elsif a.listener_id = auth.uid() then
    i_am_poster := false;
  else
    raise exception '找不到這段對話';
  end if;
  if a.status <> 'accepted' or t.closed_at is not null then
    raise exception '這段對話已經結束';
  end if;

  insert into hole_messages (assignment_id, from_poster, body)
  values (aid, i_am_poster, btrim(p_body))
  returning id into mid;

  if i_am_poster then
    update hole_assignments set poster_waiting_since = coalesce(poster_waiting_since, now())
    where id = aid;
  else
    update hole_assignments
    set first_reply_at = coalesce(first_reply_at, now()),
        poster_waiting_since = null, reminded_at = null, extra_requested_at = null
    where id = aid;
    -- 發出者打開了「有人回我時寄信」：同一位發出者一小時最多一封
    if exists (select 1 from hole_user_prefs p where p.user_id = t.poster_id and p.notify_reply)
       and not exists (select 1 from hole_email_outbox o
                       where o.user_id = t.poster_id and o.kind = 'poster_reply'
                         and o.created_at > now() - interval '1 hour') then
      insert into hole_email_outbox (user_id, kind) values (t.poster_id, 'poster_reply');
    end if;
  end if;
  update hole_threads set last_activity_at = now() where id = t.id;

  return jsonb_build_object('id', mid, 'show_help', i_am_poster and hole_mentions_crisis(p_body));
end $$;

create or replace function hole_my_threads() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id, 'topic', t.topic, 'body', t.body, 'avoid_classmates', t.avoid_classmates,
    'swap_count', t.swap_count, 'created_at', t.created_at, 'closed_at', t.closed_at,
    'waiting', (select count(*) from hole_assignments a
                where a.thread_id = t.id and a.status = 'pending'),
    -- 還缺幾位傾聽者、但目前沒人可派（換人或傾聽者退出後，對話頁常駐顯示「正在找新的傾聽者」）
    'seeking', case when t.closed_at is null then greatest(0,
      (select target_listeners from hole_config) + t.extra_listeners
      - (select count(*) from hole_assignments a
         where a.thread_id = t.id and a.status in ('pending', 'accepted'))) else 0 end,
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

commit;

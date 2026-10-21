-- FDFZ 樹洞 寄信：給 hole-mailer Edge Function 用的函數，以及每 5 分鐘叫它一次的定時任務。
-- 前提：已執行 hole_schema.sql、hole_cron.sql；已部署 hole-mailer（見 README「寄信功能」）。
-- 用法：Supabase 後台 → Database → Extensions 開啟 pg_net，再到 SQL Editor 整份貼上按 Run。

-- 取出一批待寄的信，同時先標記為已寄，避免兩次執行重複寄出；寄失敗的再用 hole_outbox_release 放回去。
-- 同一個人同一類通知合併成一封。超過一天還沒寄的（例如寄信功能上線前累積的）直接略過，不再寄。
create or replace function hole_outbox_claim(max_rows int default 100)
returns table (ids bigint[], kind text, email text)
language plpgsql security definer set search_path = public as $$
begin
  update hole_email_outbox set sent_at = now()
  where sent_at is null and created_at < now() - interval '1 day';

  return query
  with claimed as (
    update hole_email_outbox o set sent_at = now()
    where o.id in (
      select x.id from hole_email_outbox x
      where x.sent_at is null
      order by x.created_at
      limit max_rows
      for update skip locked)
    returning o.id, o.user_id, o.kind)
  select array_agg(c.id order by c.id), c.kind, u.email::text
  from claimed c join auth.users u on u.id = c.user_id
  where u.email is not null
  group by c.user_id, c.kind, u.email;
end $$;

create or replace function hole_outbox_release(p_ids bigint[]) returns void
language sql security definer set search_path = public as $$
  update hole_email_outbox set sent_at = null where id = any (p_ids);
$$;

-- 只有 Edge Function（service role）能呼叫
revoke execute on function hole_outbox_claim(int) from public, anon, authenticated;
revoke execute on function hole_outbox_release(bigint[]) from public, anon, authenticated;
grant execute on function hole_outbox_claim(int), hole_outbox_release(bigint[]) to service_role;

-- 每 5 分鐘叫一次 hole-mailer。網址是你的 Supabase 專案網址 + /functions/v1/hole-mailer
select cron.schedule('hole-mailer', '*/5 * * * *', $$
  select net.http_post(
    url := 'https://lqprjmgvruuugvnmzhaz.supabase.co/functions/v1/hole-mailer',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{}'::jsonb)
$$);

-- 要停用：select cron.unschedule('hole-mailer');

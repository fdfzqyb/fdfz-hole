-- FDFZ 樹洞 v1.3.0：後台管理危機關鍵詞、匿名統計
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次（要先跑過 hole_1.2.0.sql）。
--
-- 1. 危機關鍵詞：樹洞管理員在後台直接新增／移除，不用再進 Table Editor；每次增刪都寫進操作紀錄。
-- 2. 匿名統計：每週新訊息數、多久有人接、多久第一次回覆、逾時與求助次數。只有數字，不含任何內容或身份。

begin;

-------------------------------------------------------------------------------
-- 操作紀錄多兩種動作
-------------------------------------------------------------------------------

alter table hole_audit_log drop constraint hole_audit_log_action_check;
alter table hole_audit_log add constraint hole_audit_log_action_check check (action in
  ('view_conversation', 'reveal_identity', 'resolve_report',
   'suspend_listener', 'restore_listener', 'add_admin', 'remove_admin',
   'add_crisis_word', 'remove_crisis_word'));

-------------------------------------------------------------------------------
-- 危機關鍵詞
-------------------------------------------------------------------------------

-- 關鍵詞只要出現在訊息裡就會顯示求助資源，所以不收空白、太長的詞；簡繁要分別加
create function hole_admin_add_crisis_word(p_word text) returns void
language plpgsql security definer set search_path = public as $$
declare
  w text := btrim(p_word);
begin
  if not is_hole_admin() then
    raise exception '只有樹洞管理員可以處理';
  end if;
  if w is null or char_length(w) not between 1 and 20 then
    raise exception '關鍵詞要 1～20 個字';
  end if;
  insert into hole_crisis_words (word) values (w) on conflict do nothing;
  if not found then
    raise exception '這個關鍵詞已經在名單裡了';
  end if;
  insert into hole_audit_log (admin_id, action, reason) values (auth.uid(), 'add_crisis_word', w);
end $$;

create function hole_admin_remove_crisis_word(p_word text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_hole_admin() then
    raise exception '只有樹洞管理員可以處理';
  end if;
  delete from hole_crisis_words where word = p_word;
  if not found then
    raise exception '名單裡沒有這個關鍵詞';
  end if;
  insert into hole_audit_log (admin_id, action, reason) values (auth.uid(), 'remove_crisis_word', p_word);
end $$;

-------------------------------------------------------------------------------
-- 匿名統計
-------------------------------------------------------------------------------

-- 最近 p_weeks 週（週一開始，台北時間 UTC+8），新的一週在前。只回傳次數和時間長度（分鐘）。
-- 「沒接」是派出後超過 pending_timeout 沒人接下（不算傾聽者逾時）；
-- 「逾時」是發出者等滿 extra_after 後多找一位，會記在傾聽者的逾時次數上。
create function hole_admin_stats(p_weeks int default 8) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  n int := least(greatest(coalesce(p_weeks, 8), 1), 52);
  first_week timestamp := date_trunc('week', now() at time zone 'Asia/Taipei') - (n - 1) * interval '1 week';
begin
  if not is_hole_admin() then
    raise exception '只有樹洞管理員可以查看';
  end if;
  return jsonb_build_object(
    'listeners_qualified', (select count(*) from hole_listeners l where hole_is_qualified(l.user_id)),
    'listeners_available', (select count(*) from hole_listeners l where l.available and hole_is_qualified(l.user_id)),
    'threads_open', (select count(*) from hole_threads where closed_at is null),
    'threads_waiting', (select count(*) from hole_threads t where t.closed_at is null
      and not exists (select 1 from hole_assignments a where a.thread_id = t.id and a.status = 'accepted')),
    'weeks', (select jsonb_agg(jsonb_build_object(
        'week_start', to_char(first_week + i * interval '1 week', 'YYYY-MM-DD'),
        'posted', th.posted,
        'got_listener', th.got_listener,
        'wait_median_min', th.wait_median,
        'wait_avg_min', th.wait_avg,
        'first_reply_avg_min', (select round(avg(extract(epoch from a.first_reply_at - a.accepted_at)) / 60)
          from hole_assignments a where a.first_reply_at >= w.lo and a.first_reply_at < w.hi),
        'messages_poster', (select count(*) from hole_messages m where m.from_poster and m.created_at >= w.lo and m.created_at < w.hi),
        'messages_listener', (select count(*) from hole_messages m where not m.from_poster and m.created_at >= w.lo and m.created_at < w.hi),
        'declined', (select count(*) from hole_assignments a where a.status = 'declined' and a.ended_at >= w.lo and a.ended_at < w.hi),
        'not_accepted', (select count(*) from hole_assignments a
          where a.status = 'expired' and a.accepted_at is null and a.ended_at >= w.lo and a.ended_at < w.hi),
        'reminded', (select count(*) from hole_assignments a where a.reminded_at >= w.lo and a.reminded_at < w.hi),
        'late', (select count(*) from hole_assignments a where a.extra_requested_at >= w.lo and a.extra_requested_at < w.hi),
        'need_help', (select count(*) from hole_reports r where r.kind = 'need_help' and r.created_at >= w.lo and r.created_at < w.hi),
        'reports', (select count(*) from hole_reports r where r.kind = 'report' and r.created_at >= w.lo and r.created_at < w.hi)
      ) order by i desc)
      from generate_series(0, n - 1) i
      cross join lateral (select (first_week + i * interval '1 week') at time zone 'Asia/Taipei' as lo,
                                 (first_week + (i + 1) * interval '1 week') at time zone 'Asia/Taipei' as hi) w
      cross join lateral (
        select count(*) as posted,
               count(f.at) as got_listener,
               round((percentile_cont(0.5) within group (order by extract(epoch from f.at - t.created_at)))::numeric / 60) as wait_median,
               round(avg(extract(epoch from f.at - t.created_at)) / 60) as wait_avg
        from hole_threads t
        left join lateral (select min(a.accepted_at) as at from hole_assignments a where a.thread_id = t.id) f on true
        where t.created_at >= w.lo and t.created_at < w.hi) th));
end $$;

-------------------------------------------------------------------------------
-- 執行權限
-------------------------------------------------------------------------------

revoke execute on function hole_admin_add_crisis_word(text) from public, anon;
revoke execute on function hole_admin_remove_crisis_word(text) from public, anon;
revoke execute on function hole_admin_stats(int) from public, anon;
grant execute on function
  hole_admin_add_crisis_word(text), hole_admin_remove_crisis_word(text), hole_admin_stats(int)
to authenticated;

commit;

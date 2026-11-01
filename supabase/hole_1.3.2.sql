-- FDFZ 樹洞 v1.3.2：危機關鍵詞例外詞、多找一位的錯誤訊息、保留最後一位管理員
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次（要先跑過 hole_1.3.1.sql）。
--
-- 1. 例外詞：「想死」會命中「不想死記硬背」、「跳樓」會命中「跳樓價」。比對前先把例外詞從訊息裡拿掉，
--    剩下的部分再比對關鍵詞。例外詞必須包含某個關鍵詞（否則沒有作用），管理員在後台增刪，寫進操作紀錄。
-- 2. 「還沒等滿 50 小時」改成照 hole_config.extra_after 顯示。
-- 3. 不能移除最後一位樹洞管理員（危機通知要有人收）。

begin;

-------------------------------------------------------------------------------
-- 操作紀錄多兩種動作
-------------------------------------------------------------------------------

alter table hole_audit_log drop constraint hole_audit_log_action_check;
alter table hole_audit_log add constraint hole_audit_log_action_check check (action in
  ('view_conversation', 'reveal_identity', 'resolve_report',
   'suspend_listener', 'restore_listener', 'add_admin', 'remove_admin',
   'add_crisis_word', 'remove_crisis_word',
   'add_crisis_exception', 'remove_crisis_exception'));

-------------------------------------------------------------------------------
-- 例外詞
-------------------------------------------------------------------------------

create table hole_crisis_exceptions (word text primary key);
insert into hole_crisis_exceptions (word) values
  ('想死記'), ('想死记'), ('想死背'),
  ('想死你了'), ('想死你們了'), ('想死你们了'),
  ('跳樓價'), ('跳楼价'), ('跳樓大拍賣'), ('跳楼大拍卖');

alter table hole_crisis_exceptions enable row level security;
create policy "已登入可看危機例外詞" on hole_crisis_exceptions for select to authenticated using (true);
revoke insert, update, delete, truncate on hole_crisis_exceptions from anon, authenticated;
revoke select on hole_crisis_exceptions from anon;

-- 先把例外詞換成分隔符（長的先換），剩下的字再比對關鍵詞。前端 src/crisis.js 是同一套邏輯。
create or replace function hole_mentions_crisis(t text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  s text := coalesce(t, '');
  e text;
begin
  for e in select word from hole_crisis_exceptions order by char_length(word) desc, word loop
    s := replace(s, e, chr(1));
  end loop;
  return exists (select 1 from hole_crisis_words where position(word in s) > 0);
end $$;

create function hole_admin_add_crisis_exception(p_word text) returns void
language plpgsql security definer set search_path = public as $$
declare
  w text := btrim(p_word);
begin
  if not is_hole_admin() then
    raise exception '只有樹洞管理員可以處理';
  end if;
  if w is null or char_length(w) not between 2 and 20 then
    raise exception '例外詞要 2～20 個字';
  end if;
  if exists (select 1 from hole_crisis_words where word = w) then
    raise exception '例外詞不能和關鍵詞一模一樣，否則這個關鍵詞就等於失效';
  end if;
  if not exists (select 1 from hole_crisis_words where position(word in w) > 0) then
    raise exception '例外詞要包含某個關鍵詞，例如「跳樓價」包含「跳樓」';
  end if;
  insert into hole_crisis_exceptions (word) values (w) on conflict do nothing;
  if not found then
    raise exception '這個例外詞已經在名單裡了';
  end if;
  insert into hole_audit_log (admin_id, action, reason) values (auth.uid(), 'add_crisis_exception', w);
end $$;

create function hole_admin_remove_crisis_exception(p_word text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_hole_admin() then
    raise exception '只有樹洞管理員可以處理';
  end if;
  delete from hole_crisis_exceptions where word = p_word;
  if not found then
    raise exception '名單裡沒有這個例外詞';
  end if;
  insert into hole_audit_log (admin_id, action, reason) values (auth.uid(), 'remove_crisis_exception', p_word);
end $$;

revoke execute on function hole_admin_add_crisis_exception(text) from public, anon;
revoke execute on function hole_admin_remove_crisis_exception(text) from public, anon;
grant execute on function hole_admin_add_crisis_exception(text), hole_admin_remove_crisis_exception(text) to authenticated;

-------------------------------------------------------------------------------
-- 多找一位：錯誤訊息照設定值
-------------------------------------------------------------------------------

create or replace function hole_request_extra(aid bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c hole_config;
  a hole_assignments;
  t hole_threads;
  added int;
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
  if a.poster_waiting_since is null or a.poster_waiting_since > now() - c.extra_after then
    raise exception '還沒等滿 % 小時，請再等等', round(extract(epoch from c.extra_after) / 3600);
  end if;
  if a.extra_requested_at is not null then
    raise exception '這次等待已經多找過一位了';
  end if;
  if t.extra_listeners >= c.max_extra_listeners then
    raise exception '這則訊息已經多找過 % 位了', c.max_extra_listeners;
  end if;

  update hole_assignments set extra_requested_at = now() where id = aid;
  update hole_listeners set timeout_count = timeout_count + 1 where user_id = a.listener_id;
  update hole_listeners
  set suspended_at = now(), suspend_reason = '多次逾時', available = false
  where user_id = a.listener_id and suspended_at is null and timeout_count >= c.timeout_suspend;
  update hole_threads set extra_listeners = extra_listeners + 1, last_activity_at = now() where id = t.id;

  added := hole_dispatch(t.id);
  return jsonb_build_object('ok', true, 'dispatched', added);
end $$;

-------------------------------------------------------------------------------
-- 至少留一位樹洞管理員
-------------------------------------------------------------------------------

create or replace function hole_remove_admin(sid text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid;
begin
  if not (is_admin() or is_hole_admin()) then
    raise exception '沒有權限';
  end if;
  -- 鎖住管理員名單，兩人同時移除彼此時不會一起被刪光
  perform 1 from hole_admins for update;
  select id into uid from profiles where student_id = sid;
  if uid is null or not exists (select 1 from hole_admins where user_id = uid) then
    raise exception '這個學號不是樹洞管理員';
  end if;
  if (select count(*) from hole_admins) <= 1 then
    raise exception '至少要留一位樹洞管理員，請先新增另一位再移除';
  end if;
  delete from hole_admins where user_id = uid;
  insert into hole_audit_log (admin_id, action, reason) values (auth.uid(), 'remove_admin', sid);
end $$;

commit;

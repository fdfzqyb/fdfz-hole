import { reactive } from 'vue'
import { supabase } from './supabase'
import { listenerState } from './auth'

// 站內提醒：底部導覽列的數字和分頁標題的 (n)。
// mine：我的對話裡傾聽者傳來、還沒讀的訊息；listen：傾聽的對話裡發出者傳來、還沒讀的訊息；offers：等我接下的單
export const unread = reactive({ mine: 0, listen: 0, offers: 0 })

let running = null
export function refreshUnread() {
  running ??= load().finally(() => (running = null))
  return running
}

async function load() {
  const listener = ['qualified', 'suspended'].includes(listenerState())
  const [mine, assigned] = await Promise.all([
    supabase.rpc('hole_my_threads'),
    listener ? supabase.rpc('hole_my_assignments') : Promise.resolve({ data: [] }),
  ])
  unread.mine = (mine.data ?? []).flatMap((x) => x.conversations).reduce((n, c) => n + (c.unread ?? 0), 0)
  const list = assigned.data ?? []
  unread.listen = list.filter((a) => a.status === 'active').reduce((n, a) => n + (a.unread ?? 0), 0)
  unread.offers = listenerState() === 'qualified' ? list.filter((a) => a.status === 'pending').length : 0
}

// 打開一段對話時呼叫：標成已讀，再更新數字
export async function markRead(aid) {
  await supabase.rpc('hole_mark_read', { aid })
  await refreshUnread()
}

// 有新訊息就重算（RLS 只會送來自己看得到的對話）；手機切回前景時也重算一次
let timer = null
let started = false
export function watchUnread() {
  if (started) return
  started = true
  supabase
    .channel('hole-unread')
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'hole_messages' }, () => {
      clearTimeout(timer)
      timer = setTimeout(refreshUnread, 800)
    })
    .subscribe()
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') refreshUnread()
  })
}

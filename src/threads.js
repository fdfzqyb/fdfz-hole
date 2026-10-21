// 發出者看到的訊息狀態
export function threadStatus(th) {
  if (th.closed_at) return { label: '已結束', cls: 'st-done' }
  const live = th.conversations.filter((c) => c.active).length
  if (live) return { label: '{n} 位在聽', n: live, cls: 'st-live' }
  if (th.waiting) return { label: '等人接下', cls: 'st-wait' }
  return { label: '正在找傾聽者', cls: 'st-wait' }
}

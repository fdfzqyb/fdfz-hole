import { t } from './i18n'

const pad = (n) => String(n).padStart(2, '0')

// 今天 21:40、昨天 08:05、10月12日、2025年10月12日
export function when(value) {
  if (!value) return ''
  const d = new Date(value)
  const now = new Date()
  const hm = `${pad(d.getHours())}:${pad(d.getMinutes())}`
  const day = (x) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime()
  const diff = Math.round((day(now) - day(d)) / 86400000)
  if (diff === 0) return t('今天 {time}', { time: hm })
  if (diff === 1) return t('昨天 {time}', { time: hm })
  if (d.getFullYear() === now.getFullYear()) return t('{m}月{d}日', { m: d.getMonth() + 1, d: d.getDate() })
  return t('{y}年{m}月{d}日', { y: d.getFullYear(), m: d.getMonth() + 1, d: d.getDate() })
}

export function clock(value) {
  const d = new Date(value)
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`
}

// 8 分鐘前、3 小時前、2 天前
export function ago(value) {
  const min = Math.max(0, Math.floor((Date.now() - new Date(value).getTime()) / 60000))
  if (min < 1) return t('剛剛')
  if (min < 60) return t('{n} 分鐘前', { n: min })
  if (min < 60 * 24) return t('{n} 小時前', { n: Math.floor(min / 60) })
  return t('{n} 天前', { n: Math.floor(min / 1440) })
}

// Supabase 回傳的錯誤：資料庫函數 raise 的中文訊息直接顯示，其他的換成通用提示
export function errorText(error) {
  const msg = error?.message ?? ''
  if (/[一-鿿]/.test(msg)) return msg
  console.error(error)
  return '出了點問題，請稍後再試'
}

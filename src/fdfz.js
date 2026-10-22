// fdfz.click 各站共用的設定。每個站都放一份一模一樣的，改了要一起改。

export const ACCOUNT_URL = 'https://account.fdfz.click'

// 正式站在 fdfz.click 底下，登入資訊和語言設定存在 .fdfz.click 的 cookie，所有子網域都讀得到；
// 本機開發（localhost）就只存在本機
const host = location.hostname
export const onFdfz = host === 'fdfz.click' || host.endsWith('.fdfz.click')

export const cookieOptions = {
  domain: onFdfz ? '.fdfz.click' : undefined,
  path: '/',
  sameSite: 'lax',
  secure: onFdfz,
  maxAge: 60 * 60 * 24 * 365,
}

export function readCookie(name) {
  const hit = document.cookie.split('; ').find((c) => c.startsWith(name + '='))
  return hit ? decodeURIComponent(hit.slice(name.length + 1)) : null
}

export function writeCookie(name, value) {
  let c = `${name}=${encodeURIComponent(value)}; Path=/; Max-Age=${cookieOptions.maxAge}; SameSite=Lax`
  if (onFdfz) c += '; Domain=.fdfz.click; Secure'
  document.cookie = c
}

// 只接受 fdfz.click 各站的網址，避免登入頁被拿來轉到釣魚網站。本機開發時也接受 localhost。
export function safeNext(value) {
  if (!value || typeof value !== 'string') return null
  let url
  try {
    url = new URL(value)
  } catch {
    return null
  }
  const h = url.hostname
  if (url.protocol === 'https:' && (h === 'fdfz.click' || h.endsWith('.fdfz.click'))) return url.href
  if (!onFdfz && url.protocol === 'http:' && h === 'localhost') return url.href
  return null
}

// 其他站要送人來帳號中心時用：path 是 /login、/pending 或 /，登入完會回到 back
export function accountUrl(path = '/', back = location.href) {
  return `${ACCOUNT_URL}${path}?next=${encodeURIComponent(back)}`
}

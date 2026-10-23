import { readonly, ref } from 'vue'
import { simplified } from './locales/zh-Hans'
import { readCookie, writeCookie } from './fdfz'

// 語言設定存在 .fdfz.click 的 cookie，各站共用；還沒有 cookie 時沿用以前存在這個網站的設定
const COOKIE = 'fdfz-lang'
const OLD_STORAGE_KEY = 'fdfz-hole-language'
const DEFAULT_LOCALE = 'zh-Hans'

function readLocale() {
  try {
    const saved = readCookie(COOKIE) ?? localStorage.getItem(OLD_STORAGE_KEY)
    return saved === 'zh-Hans' || saved === 'zh-Hant' ? saved : DEFAULT_LOCALE
  } catch {
    return DEFAULT_LOCALE
  }
}

const currentLocale = ref(readLocale())
export const locale = readonly(currentLocale)

export function setLocale(value) {
  if (value !== 'zh-Hans' && value !== 'zh-Hant') return
  currentLocale.value = value
  try {
    writeCookie(COOKIE, value)
  } catch {
    // cookie 被停用時，仍允許在本次使用期間切換語言。
  }
}

// 保留訊息原文和參數，到顯示時才翻譯，已出現的提示也能隨語言更新。
export const message = (key, params = {}) => ({ key, params })

export function t(value, params = {}) {
  const key = typeof value === 'string' ? value : value?.key ?? ''
  const values = typeof value === 'string' ? params : value?.params ?? {}
  const text = currentLocale.value === 'zh-Hans' && Object.hasOwn(simplified, key)
    ? simplified[key]
    : key
  // 只處理固定文案；參數中的姓名和同學寫的內容不做字體轉換。
  return text.replace(/\{(\w+)\}/g, (token, name) => {
    if (!Object.hasOwn(values, name)) return token
    const value = values[name]
    return value && typeof value === 'object' ? t(value) : String(value)
  })
}

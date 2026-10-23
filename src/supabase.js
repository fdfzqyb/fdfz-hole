import { createBrowserClient } from '@supabase/ssr'
import { cookieOptions } from './fdfz'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_KEY

if (!url || !key) {
  console.error('缺少 VITE_SUPABASE_URL 或 VITE_SUPABASE_KEY，請照 README 建立 .env')
}

// 登入資訊存在 cookie（不是 localStorage），fdfz.click 各站共用同一份，一站登入就全站登入
export const supabase = createBrowserClient(url, key, { cookieOptions })

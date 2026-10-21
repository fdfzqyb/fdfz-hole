import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_KEY

if (!url || !key) {
  console.error('缺少 VITE_SUPABASE_URL 或 VITE_SUPABASE_KEY，請照 README 建立 .env')
}

export const supabase = createClient(url, key)

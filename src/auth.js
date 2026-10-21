import { reactive } from 'vue'
import { supabase } from './supabase'

// 帳號和權益牆共用（同一個 Supabase 專案）。註冊、校園卡驗證、改密碼都在權益牆做。
export const WALL_URL = 'https://wall.fdfz.click'

// 全站共用的登入狀態：session 是 Supabase 的登入資訊，profile 是 profiles 表裡自己那一筆，
// hole 是樹洞自己的資料：是不是樹洞管理員、傾聽者資格、可調參數
export const auth = reactive({
  ready: false,
  session: null,
  profile: null,
  error: '', // 連不上 Supabase 時顯示給同學看的訊息
  hole: {
    isAdmin: false,
    listener: null, // hole_listeners 裡自己那一筆，還沒考過測驗是 null
    config: null, // hole_config 唯一那一列
  },
})

let markReady
// 路由會等這個 Promise，確認完登入狀態才決定要去哪一頁
export const authReady = new Promise((resolve) => (markReady = resolve))

export async function loadProfile() {
  if (!auth.session) {
    auth.profile = null
    auth.hole.isAdmin = false
    auth.hole.listener = null
    return
  }
  const { data } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', auth.session.user.id)
    .maybeSingle()
  auth.profile = data
  await loadHole()
}

// 傾聽者資格、承諾、接單狀態改變後要重新讀一次
export async function loadHole() {
  if (!auth.session || !isApproved()) return
  const [admin, listener, config] = await Promise.all([
    supabase.rpc('is_hole_admin'),
    supabase.from('hole_listeners').select('*').eq('user_id', auth.session.user.id).maybeSingle(),
    supabase.from('hole_config').select('*').maybeSingle(),
  ])
  auth.hole.isAdmin = admin.data === true
  auth.hole.listener = listener.data
  auth.hole.config = config.data
}

async function loadSession() {
  const { data, error } = await supabase.auth.getSession()
  if (error) throw error
  auth.session = data.session
  await loadProfile()
}

export async function initAuth() {
  // 網路很慢時不要一直空白：15 秒還沒好就先提示，之後連上了照樣會進站
  const slow = setTimeout(() => {
    auth.error = '連線很慢，還在嘗試連上伺服器…'
  }, 15000)
  try {
    await loadSession()
    auth.error = ''
  } catch (e) {
    console.error(e)
    auth.error = '連不上伺服器，請檢查網路後重新整理。'
    return
  } finally {
    clearTimeout(slow)
  }
  auth.ready = true
  markReady()

  supabase.auth.onAuthStateChange((_event, session) => {
    auth.session = session
    // 不能在這個回呼裡直接 await Supabase 查詢，所以放到下一輪執行
    setTimeout(loadProfile, 0)
  })
}

export const isApproved = () => auth.profile?.verify_status === 'approved'
export const isHoleAdmin = () => isApproved() && auth.hole.isAdmin

// 傾聽者資格：測驗通過、承諾是最新版、沒被暫停（和資料庫的 hole_is_qualified 一致）
export function listenerState() {
  const l = auth.hole.listener
  if (!l?.quiz_passed_at) return 'none'
  if (l.suspended_at) return 'suspended'
  if (l.pledge_version !== auth.hole.config?.pledge_version) return 'pledge'
  return 'qualified'
}

// 輸入八位數字當學號，否則當 email（和權益牆一樣）
export async function signIn(account, password) {
  let email = account.trim()
  if (/^\d{8}$/.test(email)) {
    const { data, error } = await supabase.rpc('login_email', { sid: email, pw: password })
    if (error || !data) return '學號或密碼錯誤'
    email = data
  }
  const { error } = await supabase.auth.signInWithPassword({ email, password })
  if (!error) return null
  if (error.message.includes('Email not confirmed')) return '請先到信箱點擊驗證連結'
  return '帳號或密碼錯誤'
}

export async function signOut() {
  await supabase.auth.signOut()
  auth.profile = null
  auth.hole.isAdmin = false
  auth.hole.listener = null
}

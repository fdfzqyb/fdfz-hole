import { createRouter, createWebHistory } from 'vue-router'
import { auth, authReady, isApproved, isHoleAdmin } from './auth'
import { accountUrl } from './fdfz'

// 登入、等待校園卡審核、改密碼都在帳號中心 account.fdfz.click，這裡舊的網址直接轉過去
const toAccount = (path) => () => {
  window.location.assign(accountUrl(path, location.origin + '/'))
  return false
}

// meta.admin：只有樹洞管理員能進
const routes = [
  { path: '/login', beforeEnter: toAccount('/login'), component: {} },
  { path: '/pending', beforeEnter: toAccount('/pending'), component: {} },
  { path: '/', component: () => import('./views/WriteView.vue') },
  { path: '/mine', component: () => import('./views/MineView.vue') },
  { path: '/mine/:id', component: () => import('./views/ThreadView.vue') },
  { path: '/listen', component: () => import('./views/ListenView.vue') },
  { path: '/listen/:aid', component: () => import('./views/ListenChatView.vue') },
  { path: '/train', component: () => import('./views/TrainView.vue') },
  { path: '/rules', component: () => import('./views/RulesView.vue') },
  { path: '/account', component: () => import('./views/AccountView.vue') },
  { path: '/admin', component: () => import('./views/AdminView.vue'), meta: { admin: true } },
  { path: '/:pathMatch(.*)*', redirect: '/' },
]

export const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior: () => ({ top: 0 }),
})

router.beforeEach(async (to) => {
  await authReady
  if (['/login', '/pending'].includes(to.path)) return true
  // 沒登入、校園卡還沒通過、權益部重設了臨時密碼：都送到帳號中心處理，好了會回到這一頁
  const back = location.origin + to.fullPath
  const fix = !auth.session ? '/login' : !isApproved() ? '/pending' : auth.profile?.must_change_password ? '/' : null
  if (fix) {
    window.location.assign(accountUrl(fix, back))
    return false
  }
  if (to.meta.admin && !isHoleAdmin()) return '/'
  return true
})

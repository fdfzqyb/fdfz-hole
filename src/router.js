import { createRouter, createWebHistory } from 'vue-router'
import { auth, authReady, isApproved, isHoleAdmin } from './auth'

// meta.public：不用登入也能看；meta.admin：只有樹洞管理員能進
const routes = [
  { path: '/login', component: () => import('./views/LoginView.vue'), meta: { public: true } },
  { path: '/pending', component: () => import('./views/PendingView.vue'), meta: { public: true } },
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
  if (to.path === '/login' && auth.session) return isApproved() ? '/' : '/pending'
  if (to.meta.public) return true
  if (!auth.session) return '/login'
  // 校園卡還沒通過，或權益部重設了臨時密碼：都要先回權益牆處理
  if (!isApproved() || auth.profile?.must_change_password) return '/pending'
  if (to.meta.admin && !isHoleAdmin()) return '/'
  return true
})

import { createApp } from 'vue'
import App from './App.vue'
import { router } from './router'
import { initAuth } from './auth'
import './styles.css'

// 馬上顯示畫面（先是「載入中」），登入狀態在背景確認；確認完路由才會繼續
initAuth()
createApp(App).use(router).mount('#app')

<script setup>
// 還沒通過校園卡驗證，或權益部重設了臨時密碼：這兩件事都在權益牆處理
import { t } from '../i18n'
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import { auth, signOut, loadProfile, isApproved, WALL_URL } from '../auth'

const router = useRouter()
const status = computed(() => {
  if (!auth.session) return 'out'
  if (!isApproved()) return auth.profile?.verify_status === 'rejected' ? 'rejected' : 'waiting'
  if (auth.profile?.must_change_password) return 'password'
  return 'ok'
})

async function recheck() {
  await loadProfile()
  if (status.value === 'ok') router.replace('/')
}

async function logout() {
  await signOut()
  router.replace('/login')
}
</script>

<template>
  <div class="page" style="padding-top: 48px">
    <img src="/logo.svg" alt="" style="width: 72px; height: 72px; align-self: center" />
    <div class="card">
      <template v-if="status === 'out'">
        <h2>{{ t('請先登入') }}</h2>
        <router-link to="/login" class="btn block">{{ t('去登入') }}</router-link>
      </template>
      <template v-else-if="status === 'password'">
        <h2>{{ t('請先改密碼') }}</h2>
        <p>{{ t('你正在使用權益部給的臨時密碼。請先到權益牆改成自己的密碼，再回來使用樹洞。') }}</p>
        <a :href="`${WALL_URL}/account`" class="btn block">{{ t('到權益牆改密碼') }}</a>
      </template>
      <template v-else>
        <h2>{{ t('帳號還沒通過校園卡驗證') }}</h2>
        <p v-if="status === 'rejected'">{{ t('你的校園卡驗證沒有通過，請到權益牆查看原因並重新上傳。') }}</p>
        <p v-else>{{ t('樹洞只開放給通過校園卡驗證的同學。驗證在權益牆進行，通過後就能使用樹洞。') }}</p>
        <a :href="`${WALL_URL}/pending`" class="btn block">{{ t('到權益牆查看') }}</a>
      </template>
      <button v-if="status !== 'out'" class="btn plain block" type="button" @click="recheck">{{ t('我處理好了，重新檢查') }}</button>
    </div>
    <button v-if="auth.session" class="btn plain" type="button" @click="logout">{{ t('登出') }}</button>
  </div>
</template>

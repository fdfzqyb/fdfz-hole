<script setup>
import { t } from '../i18n'
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { signIn, loadProfile, isApproved, WALL_URL } from '../auth'

const router = useRouter()
const account = ref('')
const password = ref('')
const error = ref('')
const busy = ref(false)

async function submit() {
  error.value = ''
  busy.value = true
  const msg = await signIn(account.value, password.value)
  if (msg) {
    error.value = msg
    busy.value = false
    return
  }
  await loadProfile()
  busy.value = false
  router.replace(isApproved() ? '/' : '/pending')
}
</script>

<template>
  <div class="page login">
    <img src="/logo.svg" alt="" class="logo" />
    <h1 class="center">{{ t('FDFZ 樹洞') }}</h1>
    <p class="center muted">{{ t('匿名說出想說的話，有受過培訓的同學聽你說。') }}<br />{{ t('用權益牆的帳號登入。') }}</p>

    <form class="vstack" @submit.prevent="submit">
      <label class="field">
        <span>{{ t('學號或 Email') }}</span>
        <input v-model="account" type="text" autocomplete="username" required />
      </label>
      <label class="field">
        <span>{{ t('密碼') }}</span>
        <input v-model="password" type="password" autocomplete="current-password" required />
      </label>
      <p v-if="error" class="error">{{ t(error) }}</p>
      <button class="btn block" :disabled="busy">{{ busy ? t('登入中…') : t('登入') }}</button>
    </form>
    <p class="center muted small">{{ t('忘記密碼？請帶校園卡找權益部重設。') }}</p>

    <p class="center muted" style="margin-top: 24px">{{ t('還沒有帳號？') }}</p>
    <a :href="`${WALL_URL}/register`" class="btn ghost block">{{ t('到權益牆註冊') }}</a>
    <p class="center muted small">{{ t('樹洞和權益牆共用帳號，註冊後要通過校園卡驗證。') }}</p>
  </div>
</template>

<style scoped>
.login {
  padding-top: 48px; min-height: 100vh;
  background: var(--sage);
  box-shadow: 0 0 0 100vmax var(--sage);
  clip-path: inset(0 -100vmax);
}
.logo { display: block; width: 96px; height: 96px; margin: 0 auto 8px; }
h1 { font-size: 30px; }
</style>

<script setup>
import { VERSION, COMMIT } from '../version.js'
import { locale, setLocale, t } from '../i18n'
import { computed, ref, onMounted } from 'vue'
import { supabase } from '../supabase'
import { errorText } from '../format'
import { auth, signOut, listenerState, isHoleAdmin } from '../auth'
import { accountUrl } from '../fdfz'
import TabBar from '../components/TabBar.vue'

const profile = computed(() => auth.profile ?? {})
const email = computed(() => auth.session?.user?.email ?? '')
const LISTENER_LABEL = { none: '還不是傾聽者', pledge: '要重新確認承諾', suspended: '已暫停', qualified: '傾聽者' }

// 有人回我時寄信：預設關閉。信裡不提樹洞、不放內容，同一個人一小時最多一封
const notifyReply = ref(false)
const notifyBusy = ref(true)
const notifyError = ref('')
onMounted(async () => {
  const { data } = await supabase.from('hole_user_prefs').select('notify_reply').maybeSingle()
  notifyReply.value = !!data?.notify_reply
  notifyBusy.value = false
})
async function toggleNotify() {
  const on = !notifyReply.value
  notifyBusy.value = true
  notifyError.value = ''
  const { error: e } = await supabase.rpc('hole_set_notify_reply', { p_on: on })
  notifyBusy.value = false
  if (e) return (notifyError.value = errorText(e))
  notifyReply.value = on
}

async function logout() {
  await signOut()
  window.location.assign(accountUrl('/login', location.origin + '/'))
}
</script>

<template>
  <header class="topbar"><h1>{{ t('帳號') }}</h1></header>
  <div class="page">
    <div class="card info">
      <div><span class="muted">{{ t('姓名') }}</span><b>{{ profile.full_name }}</b></div>
      <div><span class="muted">{{ t('學號') }}</span><b>{{ profile.student_id }}</b></div>
      <div><span class="muted">Email</span><b>{{ email }}</b></div>
      <div><span class="muted">{{ t('傾聽者資格') }}</span><b>{{ t(LISTENER_LABEL[listenerState()]) }}</b></div>
      <div v-if="isHoleAdmin()"><span class="muted">{{ t('身份') }}</span><b>{{ t('樹洞管理員') }}</b></div>
    </div>
    <p class="muted small">{{ t('你的姓名和學號不會出現在任何對話裡。發出者和傾聽者彼此看不到對方是誰。') }}</p>

    <section class="card" aria-labelledby="language-heading">
      <h3 id="language-heading">{{ t('語言') }}</h3>
      <div class="language-options" role="group" aria-labelledby="language-heading">
        <button type="button" class="btn" :class="{ ghost: locale !== 'zh-Hans' }" :aria-pressed="locale === 'zh-Hans'" lang="zh-Hans" @click="setLocale('zh-Hans')">简体中文</button>
        <button type="button" class="btn" :class="{ ghost: locale !== 'zh-Hant' }" :aria-pressed="locale === 'zh-Hant'" lang="zh-Hant" @click="setLocale('zh-Hant')">繁體中文</button>
      </div>
    </section>

    <section class="card" aria-labelledby="notify-heading">
      <h3 id="notify-heading">{{ t('通知') }}</h3>
      <label class="check">
        <input type="checkbox" :checked="notifyReply" :disabled="notifyBusy" @change="toggleNotify" />
        <span>{{ t('傾聽者回覆我時寄信通知') }}<small>{{ t('預設關閉。寄件人是 FDFZ 樹洞（hole@fdfz.click），主旨和內文只寫「你有一則新通知」，不含任何對話內容；一小時最多一封。') }}</small></span>
      </label>
      <p v-if="notifyError" class="error">{{ t(notifyError) }}</p>
      <p class="muted tiny">{{ t('傾聽者收到新單、被提醒回覆的信不受這個開關影響。') }}</p>
    </section>

    <router-link to="/rules" class="btn plain block">{{ t('樹洞守則') }}</router-link>
    <a :href="accountUrl('/')" class="btn plain block">{{ t('帳號設定（改密碼）') }}</a>
    <button class="btn plain block" type="button" @click="logout">{{ t('登出') }}</button>
    <p class="center muted small">{{ t('FDFZ 樹洞') }} v{{ VERSION }}<template v-if="COMMIT"> · {{ COMMIT }}</template></p>
  </div>
  <TabBar />
</template>

<style scoped>
.info { display: grid; gap: 12px; }
.info div { display: flex; justify-content: space-between; gap: 12px; }
.info b { font-weight: 600; text-align: right; word-break: break-all; }
.language-options { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; }
</style>

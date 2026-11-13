<script setup>
// 傾聽者和一位樹洞管理員的一對一對話（找管理員聊）。傾聽者和管理員共用這一頁。
// 和傾聽者手上的對話完全分開：管理員看不到傾聽者和發出者聊了什麼。
// 預設匿名：管理員只看到「一位傾聽者」，傾聽者勾了具名才顯示姓名。
import { t } from '../i18n'
import { ref, computed, watch, onUnmounted, nextTick } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { when, errorText } from '../format'
import Icon from '../components/Icon.vue'
import IdentityNote from '../components/IdentityNote.vue'
import QuickExit from '../components/QuickExit.vue'
import Modal from '../components/Modal.vue'
import TabBar from '../components/TabBar.vue'

const route = useRoute()
const router = useRouter()
const cid = computed(() => Number(route.params.id))
const k = ref(null)
const messages = ref([])
const draft = ref('')
const sending = ref(false)
const error = ref('')
const bottom = ref(null)
let channel = null

const isAdmin = computed(() => k.value?.role === 'admin')
const canSend = computed(() => k.value && k.value.status !== 'closed' && (k.value.role === 'listener' || k.value.status === 'active'))
const backTo = computed(() => (isAdmin.value ? '/admin?tab=consults' : '/listen'))
const title = computed(() => {
  if (!k.value) return t('找管理員聊')
  if (!isAdmin.value) return t('樹洞管理員')
  return k.value.listener_name || t('一位傾聽者')
})

async function load() {
  error.value = ''
  const { data, error: e } = await supabase.rpc('hole_consult_get', { cid: cid.value })
  if (e) return (error.value = errorText(e))
  k.value = data
  messages.value = data.messages
  scrollDown()
}

function scrollDown() {
  nextTick(() => bottom.value?.scrollIntoView({ block: 'nearest' }))
}

function subscribe() {
  channel?.unsubscribe()
  channel = supabase
    .channel(`hole-consult-${cid.value}`)
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'hole_consult_messages', filter: `consult_id=eq.${cid.value}` }, ({ new: m }) => {
      if (messages.value.some((x) => x.id === m.id)) return
      const mine = m.from_listener === !isAdmin.value
      messages.value.push({ id: m.id, from: mine ? 'me' : 'other', body: m.body, created_at: m.created_at })
      scrollDown()
      // 對方回了：重讀一次，順便標成已讀、更新狀態（例如管理員剛接下）
      if (!mine) load()
    })
    .subscribe()
}

function onVisible() {
  if (document.visibilityState === 'visible') load()
}
document.addEventListener('visibilitychange', onVisible)

watch(cid, () => {
  k.value = null
  messages.value = []
  load()
  subscribe()
}, { immediate: true })

onUnmounted(() => {
  channel?.unsubscribe()
  document.removeEventListener('visibilitychange', onVisible)
})

async function send() {
  const body = draft.value.trim()
  if (!body || sending.value) return
  sending.value = true
  error.value = ''
  const { data, error: e } = await supabase.rpc('hole_consult_send', { cid: cid.value, p_body: body })
  sending.value = false
  if (e) return (error.value = errorText(e))
  draft.value = ''
  if (!messages.value.some((x) => x.id === data.id)) {
    messages.value.push({ id: data.id, from: 'me', body, created_at: new Date().toISOString() })
  }
  scrollDown()
}

function onKey(e) {
  if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) send()
}

const closeOpen = ref(false)
const closeBusy = ref(false)
async function close() {
  closeBusy.value = true
  const { error: e } = await supabase.rpc('hole_consult_close', { cid: cid.value })
  closeBusy.value = false
  closeOpen.value = false
  if (e) return (error.value = errorText(e))
  load()
}
</script>

<template>
  <header class="topbar">
    <button class="back" type="button" :aria-label="t('返回')" @click="router.push(backTo)"><Icon name="back" :size="24" /></button>
    <h1>{{ title }}</h1>
    <span v-if="k" class="status" :class="k.status === 'active' ? 'st-live' : k.status === 'closed' ? 'st-done' : 'st-wait'">
      {{ k.status === 'active' ? t('聊天中') : k.status === 'closed' ? t('已結束') : t('等管理員接下') }}
    </span>
    <QuickExit />
  </header>
  <div class="page">
    <p v-if="error" class="error">{{ t(error) }}</p>
    <p v-else-if="!k" class="muted center">{{ t('載入中…') }}</p>
    <template v-else>
      <p v-if="!isAdmin && k.status === 'pending' && k.has_admin" class="note small" role="status">
        <Icon name="clock" :size="20" />
        <span>{{ t('已經派給一位樹洞管理員，等對方接下。30 分鐘沒接會改找別的管理員。你可以先補充想說的。') }}</span>
      </p>
      <p v-else-if="!isAdmin && k.status === 'pending'" class="note warn small" role="status">
        <Icon name="warn" :size="20" />
        <span>{{ t('目前沒有管理員可以接，有人可以接時會自動派給他。如果你現在狀態不好，可以先到傾聽頁把接單切成暫停。') }}</span>
      </p>
      <p v-if="isAdmin" class="note small">
        <Icon name="lock" :size="20" />
        <span>{{ k.named
          ? t('對方選擇讓你看到姓名。這段對話和他手上的對話分開，你看不到他和發出者聊了什麼。')
          : t('對方是匿名的傾聽者。這段對話和他手上的對話分開，你看不到他和發出者聊了什麼。') }}</span>
      </p>

      <div class="card">
        <div class="chat" aria-live="polite">
          <span class="sys">{{ t('{time} 開始', { time: when(k.created_at) }) }}</span>
          <div v-for="m in messages" :key="m.id" class="bub" :class="m.from === 'me' ? 'mine' : 'them'">
            {{ m.body }}<time>{{ when(m.created_at) }}</time>
          </div>
          <span v-if="k.status === 'closed'" class="sys">{{ t('這段對話已結束') }}</span>
          <span ref="bottom" />
        </div>
        <template v-if="canSend">
          <IdentityNote :text="draft" />
          <form class="composer" @submit.prevent="send">
            <label for="consult-reply" class="sr">{{ t('回覆') }}</label>
            <textarea id="consult-reply" v-model="draft" maxlength="2000" :placeholder="isAdmin ? t('先聽聽他遇到什麼，再一起想怎麼回。') : t('說說你遇到什麼，不用貼對話內容。')" @keydown="onKey" />
            <button class="btn" :disabled="sending || !draft.trim()" :aria-label="t('送出')"><Icon name="send" :size="20" /></button>
          </form>
        </template>
      </div>

      <p v-if="!isAdmin" class="muted tiny">{{ t('不要貼上和發出者的對話，也不要寫出能認出對方的細節；描述你遇到的情況就好。') }}</p>
      <button v-if="k.status !== 'closed' && (k.role === 'listener' || k.status === 'active')" class="btn plain block" type="button" @click="closeOpen = true">{{ t('結束這段對話') }}</button>
    </template>
  </div>
  <TabBar />

  <Modal v-model:open="closeOpen" :title="t('結束這段對話？')">
    <p class="small">{{ t('結束後雙方都不能再傳訊息。之後想聊可以再開一段。') }}</p>
    <div class="actions end">
      <button class="btn plain" type="button" @click="closeOpen = false">{{ t('取消') }}</button>
      <button class="btn" type="button" :disabled="closeBusy" @click="close">{{ t('結束') }}</button>
    </div>
  </Modal>
</template>

<style scoped>
.chat { display: flex; flex-direction: column; gap: 10px; }
.bub { max-width: 82%; padding: 10px 14px; border-radius: calc(16px * var(--sq)); corner-shape: squircle; white-space: pre-wrap; overflow-wrap: anywhere; }
.bub.them { background: var(--mist); align-self: flex-start; border-bottom-left-radius: 6px; }
.bub.mine { background: var(--forest); color: #fff; align-self: flex-end; border-bottom-right-radius: 6px; }
.bub time { display: block; font-size: 12px; opacity: .7; }
.sys { align-self: center; font-size: 13px; color: var(--muted); background: var(--mist-deep); padding: 3px 12px; border-radius: 999px; text-align: center; }
.composer { display: flex; gap: 8px; align-items: flex-end; }
.composer textarea { min-height: 46px; height: 46px; flex: 1; }
.composer .btn { --icon-heart: var(--forest); }
</style>

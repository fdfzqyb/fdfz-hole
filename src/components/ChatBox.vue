<script setup>
// 一段一對一對話：原訊息、（換人時帶過來的）之前的對話、訊息列表和輸入框。
// 新訊息用 Realtime 收；hole_messages 只有 assignment_id 和 from_poster，沒有 user id。
// 打開就把這段標成已讀，導覽列的未讀數字跟著更新
import { t } from '../i18n'
import { ref, computed, watch, onUnmounted, nextTick } from 'vue'
import { supabase } from '../supabase'
import { when, errorText } from '../format'
import { markRead } from '../unread'
import Icon from './Icon.vue'

const props = defineProps({
  aid: { type: Number, required: true },
  placeholder: { type: String, default: '' },
  showBody: { type: Boolean, default: true },
  startNote: { type: String, default: '' }, // 對話開頭的系統提示，例如「傾聽者 1 在 21:52 接下了」
})
const emit = defineEmits(['loaded', 'help'])

const conv = ref(null)
const messages = ref([])
const draft = ref('')
const sending = ref(false)
const error = ref('')
const bottom = ref(null)
let channel = null

const amPoster = computed(() => conv.value?.role === 'poster')

async function load() {
  error.value = ''
  const { data, error: e } = await supabase.rpc('hole_get_conversation', { aid: props.aid })
  if (e) return (error.value = errorText(e))
  conv.value = data
  messages.value = data.messages
  emit('loaded', data)
  scrollDown()
  seen()
}

// 畫面上看得到的訊息就算讀過（分頁在背景時不算，切回來 onVisible 會重讀）
function seen() {
  if (document.visibilityState === 'visible') markRead(props.aid)
}

function scrollDown() {
  nextTick(() => bottom.value?.scrollIntoView({ block: 'nearest' }))
}

function subscribe() {
  channel?.unsubscribe()
  channel = supabase
    .channel(`hole-messages-${props.aid}`)
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'hole_messages', filter: `assignment_id=eq.${props.aid}` }, ({ new: m }) => {
      if (messages.value.some((x) => x.id === m.id)) return
      messages.value.push({ id: m.id, from: m.from_poster === amPoster.value ? 'me' : 'other', body: m.body, created_at: m.created_at })
      scrollDown()
      if (m.from_poster !== amPoster.value) seen()
    })
    .subscribe()
}

// 手機切回前景時補讀一次，避免背景期間 Realtime 斷線漏掉訊息
function onVisible() {
  if (document.visibilityState === 'visible') load()
}
document.addEventListener('visibilitychange', onVisible)

watch(() => props.aid, () => {
  conv.value = null
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
  const { data, error: e } = await supabase.rpc('hole_send_message', { aid: props.aid, p_body: body })
  sending.value = false
  if (e) return (error.value = errorText(e))
  draft.value = ''
  if (!messages.value.some((x) => x.id === data.id)) {
    messages.value.push({ id: data.id, from: 'me', body, created_at: new Date().toISOString() })
  }
  if (data.show_help) emit('help')
  scrollDown()
}

// 電腦上 Ctrl/⌘ + Enter 送出；手機上 Enter 換行
function onKey(e) {
  if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) send()
}
</script>

<template>
  <div class="vstack">
    <div v-if="showBody && conv" class="orig small">{{ conv.body }}</div>

    <details v-if="conv?.history?.length" class="history">
      <summary class="small">{{ t('發出者帶過來的之前對話（{n} 則）', { n: conv.history.length }) }}</summary>
      <div class="chat">
        <div v-for="(m, i) in conv.history" :key="i" class="bub small" :class="m.from === 'other' ? 'them' : 'prev'">
          {{ m.body }}<time>{{ m.from === 'other' ? t('發出者') : t('之前的傾聽者') }} · {{ when(m.created_at) }}</time>
        </div>
      </div>
    </details>

    <div class="chat" aria-live="polite">
      <span v-if="startNote" class="sys">{{ startNote }}</span>
      <p v-if="conv && !messages.length" class="sys">{{ t('還沒有訊息') }}</p>
      <div v-for="m in messages" :key="m.id" class="bub" :class="m.from === 'me' ? 'mine' : 'them'">
        {{ m.body }}<time>{{ when(m.created_at) }}</time>
      </div>
      <span v-if="conv && !conv.active" class="sys">{{ t('這段對話已結束') }}</span>
      <span ref="bottom" />
    </div>

    <p v-if="error" class="error">{{ t(error) }}</p>

    <form v-if="conv?.active" class="composer" @submit.prevent="send">
      <label :for="`reply-${aid}`" class="sr">{{ t('回覆') }}</label>
      <textarea :id="`reply-${aid}`" v-model="draft" maxlength="2000" :placeholder="placeholder" @keydown="onKey" />
      <button class="btn" :disabled="sending || !draft.trim()" :aria-label="t('送出')"><Icon name="send" :size="20" /></button>
    </form>
  </div>
</template>

<style scoped>
.chat { display: flex; flex-direction: column; gap: 10px; }
.bub { max-width: 82%; padding: 10px 14px; border-radius: 16px; white-space: pre-wrap; overflow-wrap: anywhere; }
.bub.them { background: var(--mist); align-self: flex-start; border-bottom-left-radius: 6px; }
.bub.prev { background: #E6E9F0; align-self: flex-end; border-bottom-right-radius: 6px; }
.bub.mine { background: var(--forest); color: #fff; align-self: flex-end; border-bottom-right-radius: 6px; }
.bub time { display: block; font-size: 12px; opacity: .7; }
.sys { align-self: center; font-size: 13px; color: var(--muted); background: var(--mist-deep); padding: 3px 12px; border-radius: 999px; text-align: center; }
.composer { display: flex; gap: 8px; align-items: flex-end; }
.composer textarea { min-height: 46px; height: 46px; flex: 1; }
.composer .btn { --icon-heart: var(--forest); }
.history { border: 1px dashed var(--border); border-radius: 12px; padding: 10px 12px; }
.history summary { cursor: pointer; color: var(--muted); }
.history .chat { margin-top: 10px; }
</style>

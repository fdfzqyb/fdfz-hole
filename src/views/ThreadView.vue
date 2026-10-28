<script setup>
// 發出者看自己的一則訊息：和每位傾聽者各自一對一的對話、換人、多找一位、結束、檢舉
import { t } from '../i18n'
import { ref, computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { auth } from '../auth'
import { TOPIC_LABEL } from '../constants'
import { HELP } from '../help'
import { when, clock, errorText } from '../format'
import { threadStatus } from '../threads'
import Icon from '../components/Icon.vue'
import Modal from '../components/Modal.vue'
import ChatBox from '../components/ChatBox.vue'
import HelpCard from '../components/HelpCard.vue'
import TabBar from '../components/TabBar.vue'

const route = useRoute()
const router = useRouter()
const thread = ref(null)
const selected = ref(null)
const error = ref('')
const notice = ref('')
const showHelp = ref(route.query.help === '1')

async function load() {
  const { data, error: e } = await supabase.rpc('hole_my_threads')
  if (e) return (error.value = errorText(e))
  thread.value = (data ?? []).find((x) => String(x.id) === route.params.id) ?? null
  if (!thread.value) return (error.value = '找不到這則訊息')
  const convs = thread.value.conversations
  if (!convs.some((c) => c.assignment_id === selected.value)) {
    selected.value = (convs.find((c) => c.active) ?? convs.at(-1))?.assignment_id ?? null
  }
}
watch(() => route.params.id, load, { immediate: true })

// 傾聽者依接下的先後稱為「傾聽者 1、2…」，不含任何身份
const convs = computed(() => (thread.value?.conversations ?? []).map((c, i) => ({ ...c, n: i + 1 })))
const current = computed(() => convs.value.find((c) => c.assignment_id === selected.value) ?? null)
const who = (c) => t('傾聽者 {n}', { n: c.n })
const isOpen = computed(() => thread.value && !thread.value.closed_at)
const activeAid = computed(() => (current.value?.active ? current.value.assignment_id : convs.value.find((c) => c.active)?.assignment_id) ?? null)
const maxSwaps = computed(() => auth.hole.config?.max_swaps ?? 5)

// 多找一位
const extraBusy = ref(false)
async function requestExtra() {
  extraBusy.value = true
  const { data, error: e } = await supabase.rpc('hole_request_extra', { aid: current.value.assignment_id })
  extraBusy.value = false
  if (e) return (notice.value = errorText(e))
  notice.value = data.dispatched ? '已經多派出一位傾聽者，等他接下。' : '已登記多找一位，現在沒有可接單的傾聽者，有人就會派出。'
  load()
}

// 換人
const swapOpen = ref(false)
const carry = ref(false)
const swapBusy = ref(false)
const swapLimit = ref(false)
function startSwap() {
  carry.value = false
  swapLimit.value = false
  swapOpen.value = true
}
async function swap() {
  swapBusy.value = true
  const { data, error: e } = await supabase.rpc('hole_swap', { aid: current.value.assignment_id, carry_history: carry.value })
  swapBusy.value = false
  if (e) {
    swapOpen.value = false
    return (notice.value = errorText(e))
  }
  if (data.limit) return (swapLimit.value = true)
  swapOpen.value = false
  notice.value = '已經換人，系統正在找新的傾聽者。'
  selected.value = null
  load()
}

// 結束整則訊息
const closeOpen = ref(false)
const closeBusy = ref(false)
async function closeThread() {
  closeBusy.value = true
  const { error: e } = await supabase.rpc('hole_close_thread', { tid: thread.value.id })
  closeBusy.value = false
  closeOpen.value = false
  if (e) return (notice.value = errorText(e))
  load()
}

// 檢舉
const reportOpen = ref(false)
const reportNote = ref('')
const reportBusy = ref(false)
const reportDone = ref(false)
const reportError = ref('')
function startReport() {
  reportNote.value = ''
  reportDone.value = false
  reportError.value = ''
  reportOpen.value = true
}
async function report() {
  reportBusy.value = true
  const { error: e } = await supabase.rpc('hole_flag', { aid: current.value.assignment_id, p_kind: 'report', note: reportNote.value.trim() || null })
  reportBusy.value = false
  if (e) return (reportError.value = errorText(e))
  reportDone.value = true
}
</script>

<template>
  <header class="topbar">
    <button class="back" type="button" :aria-label="t('返回')" @click="router.push('/mine')"><Icon name="back" :size="24" /></button>
    <h1>{{ t('我的對話') }}</h1>
  </header>
  <div class="page">
    <p v-if="error" class="error">{{ t(error) }}</p>
    <p v-else-if="!thread" class="muted center">{{ t('載入中…') }}</p>
    <template v-else>
      <div class="row">
        <span class="muted small">{{ t(TOPIC_LABEL[thread.topic]) }} · {{ when(thread.created_at) }}</span>
        <span class="status" :class="threadStatus(thread).cls">{{ t(threadStatus(thread).label, threadStatus(thread)) }}</span>
      </div>

      <div v-if="showHelp" class="note warn" role="status">
        <Icon name="warn" :size="20" />
        <span>
          <b>{{ t('謝謝你說出來。如果你現在有傷害自己的念頭，請先找能馬上陪你的人。') }}</b>
          {{ t(HELP.hotlineName) }} {{ HELP.hotline }}；{{ HELP.counselor }}。<br />
          <span class="tiny">{{ t('這是系統依字詞自動顯示的提示，不代表我們判斷你有危險。') }}</span>
        </span>
      </div>
      <p v-if="notice" class="note" role="status"><Icon name="check" :size="20" /><span>{{ t(notice) }}</span></p>

      <!-- 還沒有人接下 -->
      <div v-if="!convs.length" class="card">
        <div class="orig small">{{ thread.body }}</div>
        <p v-if="thread.closed_at" class="muted small">{{ t('這則訊息已經結束。') }}</p>
        <p v-else-if="thread.waiting" class="muted small">{{ t('已經派給 {n} 位傾聽者，等他們接下。30 分鐘內沒人接，會自動改找別人。', { n: thread.waiting }) }}</p>
        <p v-else class="muted small">{{ t('目前沒有可以接單的傾聽者。系統每 5 分鐘會再找一次，有人就會派出。') }}</p>
      </div>

      <div v-else class="card">
        <div v-if="convs.length > 1" class="seg" role="tablist" :aria-label="t('傾聽者')">
          <button
            v-for="c in convs" :key="c.assignment_id" type="button" role="tab"
            :aria-selected="c.assignment_id === selected" :class="{ ended: !c.active }"
            @click="selected = c.assignment_id"
          ><span class="av">{{ c.n }}</span>{{ who(c) }}</button>
        </div>
        <p class="muted tiny">{{ t('傾聽者也是同學，要上課和休息，回覆可能要等幾小時。') }}</p>
        <ChatBox
          v-if="current"
          :aid="current.assignment_id"
          :start-note="t('{who} 在 {time} 接下了', { who: who(current), time: clock(current.accepted_at) })"
          :placeholder="t('寫給{who}…', { who: who(current) })"
          @help="showHelp = true"
        />

        <div v-if="current?.can_request_extra" class="note warn">
          <Icon name="clock" :size="20" />
          <span>
            {{ t('{who} 已經超過 50 小時沒回覆。你可以多找一位傾聽者，{who} 也會保留。', { who: who(current) }) }}
            <button class="btn small alertfill" type="button" style="margin-top: 8px" :disabled="extraBusy" @click="requestExtra">{{ t('多找一位') }}</button>
          </span>
        </div>

        <div v-if="isOpen" class="row" style="border-top: 1px solid var(--border); padding-top: 12px">
          <div class="actions">
            <button v-if="current?.active" class="btn plain small" type="button" @click="startSwap">{{ t('換一位傾聽者') }}</button>
            <button class="btn plain small" type="button" @click="closeOpen = true">{{ t('結束對話') }}</button>
          </div>
          <button v-if="current" class="btn danger small" type="button" @click="startReport">{{ t('檢舉') }}</button>
        </div>
      </div>

      <button v-if="isOpen && !convs.length" class="btn plain" type="button" @click="closeOpen = true">{{ t('結束這則訊息') }}</button>

      <HelpCard :aid="activeAid" :tid="thread.id" />
    </template>
  </div>
  <TabBar />

  <Modal v-model:open="swapOpen" :title="swapLimit ? t('已經換了很多次') : t('換掉{who}？', { who: current ? who(current) : '' })">
    <template v-if="!swapLimit">
      <p>{{ t('不用說理由。{who} 只會看到「對方已結束這段對話」，之後也不會再收到你的訊息。其他傾聽者不受影響。', { who: current ? who(current) : '' }) }}</p>
      <label class="check">
        <input v-model="carry" type="checkbox" />
        <span>{{ t('把這段對話也給新的人看') }}<small>{{ t('不勾的話，新傾聽者只看到你的原訊息。') }}</small></span>
      </label>
      <p class="muted tiny">{{ t('這則訊息已換過 {n} 次，最多 {max} 次。', { n: thread?.swap_count ?? 0, max: maxSwaps }) }}</p>
      <div class="actions end">
        <button class="btn plain" type="button" @click="swapOpen = false">{{ t('先不換') }}</button>
        <button class="btn" type="button" :disabled="swapBusy" @click="swap">{{ t('換人') }}</button>
      </div>
    </template>
    <template v-else>
      <p>{{ t('這則訊息已經換了 {max} 次傾聽者，不能再換了。我們已經請樹洞管理員關注。', { max: maxSwaps }) }}</p>
      <p class="note"><Icon name="phone" :size="20" /><span><b>{{ t(HELP.hotlineName) }}</b>{{ HELP.hotline }}</span></p>
      <p class="note"><Icon name="user" :size="20" /><span><b>{{ HELP.counselor }}</b>{{ HELP.counselorWhere }}</span></p>
      <div class="actions end"><button class="btn" type="button" @click="swapOpen = false">{{ t('知道了') }}</button></div>
    </template>
  </Modal>

  <Modal v-model:open="closeOpen" :title="t('結束這則訊息？')">
    <p>{{ t('所有傾聽者都會看到「對方已結束這段對話」，之後不能再發言。對話紀錄你仍然看得到。') }}</p>
    <div class="actions end">
      <button class="btn plain" type="button" @click="closeOpen = false">{{ t('先不要') }}</button>
      <button class="btn" type="button" :disabled="closeBusy" @click="closeThread">{{ t('結束') }}</button>
    </div>
  </Modal>

  <Modal v-model:open="reportOpen" :title="t('檢舉這段對話')">
    <template v-if="!reportDone">
      <p class="muted small">{{ t('樹洞管理員會查看這段對話。對話不會因此結束；不想聊了也可以直接換人。') }}</p>
      <label class="field">
        <span>{{ t('發生了什麼？（選填）') }}</span>
        <textarea v-model="reportNote" maxlength="500" style="min-height: 80px" />
      </label>
      <p v-if="reportError" class="error">{{ t(reportError) }}</p>
      <div class="actions end">
        <button class="btn plain" type="button" @click="reportOpen = false">{{ t('取消') }}</button>
        <button class="btn danger" type="button" :disabled="reportBusy" @click="report">{{ t('送出檢舉') }}</button>
      </div>
    </template>
    <template v-else>
      <p>{{ t('已經送出，管理員會處理。') }}</p>
      <div class="actions end"><button class="btn" type="button" @click="reportOpen = false">{{ t('知道了') }}</button></div>
    </template>
  </Modal>
</template>

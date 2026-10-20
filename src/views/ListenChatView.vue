<script setup>
// 傾聽者和一位匿名同學的一對一對話：回覆、需要協助、退出、檢舉
import { t } from '../i18n'
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { TOPIC_LABEL, LEAVE_REASONS } from '../constants'
import { clock, errorText } from '../format'
import Icon from '../components/Icon.vue'
import Modal from '../components/Modal.vue'
import ChatBox from '../components/ChatBox.vue'
import TabBar from '../components/TabBar.vue'

const route = useRoute()
const router = useRouter()
const aid = computed(() => Number(route.params.aid))
const info = ref(null) // hole_my_assignments 裡這一筆（接下時間）
const conv = ref(null)
const notice = ref('')

onMounted(async () => {
  const { data } = await supabase.rpc('hole_my_assignments')
  info.value = (data ?? []).find((a) => a.assignment_id === aid.value) ?? null
})

// 需要協助：交給管理員，對話照常
const helpOpen = ref(false)
const helpNote = ref('')
const helpBusy = ref(false)
const helpError = ref('')
async function askHelp() {
  helpBusy.value = true
  helpError.value = ''
  const { error: e } = await supabase.rpc('hole_flag', { aid: aid.value, p_kind: 'need_help', note: helpNote.value.trim() || null })
  helpBusy.value = false
  if (e) return (helpError.value = errorText(e))
  helpOpen.value = false
  helpNote.value = ''
  notice.value = '已經通知樹洞管理員。你可以繼續陪對方聊，不用自己扛。'
}

// 退出
const exitOpen = ref(false)
const reason = ref('over_capacity')
const exitNote = ref('')
const exitBusy = ref(false)
const exitError = ref('')
async function leave() {
  exitBusy.value = true
  exitError.value = ''
  const { error: e } = await supabase.rpc('hole_leave', { aid: aid.value, reason: reason.value, note: exitNote.value.trim() || null })
  exitBusy.value = false
  if (e) return (exitError.value = errorText(e))
  exitOpen.value = false
  router.push('/listen')
}

// 檢舉
const reportOpen = ref(false)
const reportNote = ref('')
const reportBusy = ref(false)
const reportError = ref('')
async function report() {
  reportBusy.value = true
  reportError.value = ''
  const { error: e } = await supabase.rpc('hole_flag', { aid: aid.value, p_kind: 'report', note: reportNote.value.trim() || null })
  reportBusy.value = false
  if (e) return (reportError.value = errorText(e))
  reportOpen.value = false
  reportNote.value = ''
  notice.value = '檢舉已送出，管理員會處理。'
}
</script>

<template>
  <header class="topbar">
    <button class="back" type="button" :aria-label="t('返回')" @click="router.push('/listen')"><Icon name="back" :size="24" /></button>
    <h1>{{ t('匿名同學') }}</h1>
    <span v-if="conv" class="status st-live">{{ t(TOPIC_LABEL[conv.topic]) }}</span>
  </header>
  <div class="page">
    <p v-if="notice" class="note" role="status"><Icon name="check" :size="20" /><span>{{ t(notice) }}</span></p>
    <div class="card">
      <ChatBox
        :aid="aid"
        :start-note="info?.accepted_at ? t('你在 {time} 接下', { time: clock(info.accepted_at) }) : ''"
        :placeholder="t('慢慢回，不用急著給建議。')"
        @loaded="conv = $event"
      />
    </div>

    <template v-if="conv?.active">
      <p class="note warn"><Icon name="warn" :size="20" /><span><b>{{ t('看到自傷、傷人或受侵害的信號') }}</b>{{ t('按「需要協助」交給管理員，不要自己扛。') }}</span></p>
      <div class="actions">
        <button class="btn alertfill" type="button" style="flex: 1" @click="helpOpen = true">{{ t('需要協助') }}</button>
        <button class="btn plain" type="button" style="flex: 1" @click="exitOpen = true">{{ t('退出這段對話') }}</button>
      </div>
    </template>

    <div class="card">
      <h3>{{ t('聽的時候記得') }}</h3>
      <ul class="small tips">
        <li>{{ t('不評判、不說教，先別急著給建議。') }}</li>
        <li>{{ t('不問對方是誰，不約見面，不截圖外傳。') }}</li>
        <li>{{ t('在學校遇到誰，都不要提起這段對話。') }}</li>
        <li>{{ t('認出對方是誰時，退出這段對話，讓系統改派給別人。') }}</li>
      </ul>
      <button class="btn danger small" type="button" style="align-self: flex-start" @click="reportOpen = true">{{ t('檢舉這段對話') }}</button>
    </div>
  </div>
  <TabBar />

  <Modal v-model:open="helpOpen" :title="t('把這段對話交給管理員？')">
    <p>{{ t('管理員會收到通知並查看這段對話。你可以繼續陪對方聊。') }}</p>
    <label class="field">
      <span>{{ t('你注意到什麼？（選填）') }}</span>
      <textarea v-model="helpNote" maxlength="500" :placeholder="t('例如：對方提到最近不想活了')" style="min-height: 80px" />
    </label>
    <p v-if="helpError" class="error">{{ t(helpError) }}</p>
    <div class="actions end">
      <button class="btn plain" type="button" @click="helpOpen = false">{{ t('取消') }}</button>
      <button class="btn alertfill" type="button" :disabled="helpBusy" @click="askHelp">{{ t('通知管理員') }}</button>
    </div>
  </Modal>

  <Modal v-model:open="exitOpen" :title="t('為什麼要退出？')">
    <p class="muted small">{{ t('對方只會看到「傾聽者已結束這段對話」，系統會另找一位。') }}</p>
    <label v-for="r in LEAVE_REASONS" :key="r.key" class="opt">
      <input v-model="reason" type="radio" name="why" :value="r.key" />
      <span><b v-if="r.hint">{{ t(r.label) }}</b><template v-else>{{ t(r.label) }}</template><template v-if="r.hint"><br /><span class="muted small">{{ t(r.hint) }}</span></template></span>
    </label>
    <textarea v-if="reason === 'crisis'" v-model="exitNote" maxlength="500" :placeholder="t('你注意到什麼？（選填）')" style="min-height: 70px" />
    <p v-if="exitError" class="error">{{ t(exitError) }}</p>
    <div class="actions end">
      <button class="btn plain" type="button" @click="exitOpen = false">{{ t('繼續聊') }}</button>
      <button class="btn" type="button" :disabled="exitBusy" @click="leave">{{ t('退出') }}</button>
    </div>
  </Modal>

  <Modal v-model:open="reportOpen" :title="t('檢舉這段對話')">
    <p class="muted small">{{ t('例如對方騷擾、辱罵你，或內容和傾訴無關。如果是對方有危險，請改按「需要協助」。') }}</p>
    <label class="field">
      <span>{{ t('發生了什麼？（選填）') }}</span>
      <textarea v-model="reportNote" maxlength="500" style="min-height: 80px" />
    </label>
    <p v-if="reportError" class="error">{{ t(reportError) }}</p>
    <div class="actions end">
      <button class="btn plain" type="button" @click="reportOpen = false">{{ t('取消') }}</button>
      <button class="btn danger" type="button" :disabled="reportBusy" @click="report">{{ t('送出檢舉') }}</button>
    </div>
  </Modal>
</template>

<style scoped>
.tips { margin: 0; padding-left: 20px; display: flex; flex-direction: column; gap: 4px; }
</style>

<script setup>
// 求助資源一直顯示（不靠關鍵詞觸發）。按「我現在需要馬上有人幫忙」時顯示熱線和心理老師，
// 可以同時通知樹洞管理員（預設勾選）：有進行中的對話就掛在那段對話上，還沒有人接下就掛在整則訊息上
import { t } from '../i18n'
import { ref, computed } from 'vue'
import { supabase } from '../supabase'
import { HELP } from '../help'
import { errorText } from '../format'
import Icon from './Icon.vue'
import Modal from './Modal.vue'

const props = defineProps({
  aid: { type: Number, default: null }, // 進行中那段對話
  tid: { type: Number, default: null }, // 沒有進行中的對話時，改用這則訊息通知管理員；兩個都沒有就不能通知
})

const canNotify = computed(() => !!(props.aid || props.tid))
const open = ref(false)
const notify = ref(true)
const note = ref('')
const busy = ref(false)
const done = ref(false)
const error = ref('')

function start() {
  notify.value = true
  note.value = ''
  done.value = false
  error.value = ''
  open.value = true
}

async function send() {
  if (!canNotify.value || !notify.value) return (open.value = false)
  busy.value = true
  error.value = ''
  const n = note.value.trim() || null
  const { error: e } = props.aid
    ? await supabase.rpc('hole_flag', { aid: props.aid, p_kind: 'need_help', note: n })
    : await supabase.rpc('hole_ask_help', { tid: props.tid, note: n })
  busy.value = false
  if (e) return (error.value = errorText(e))
  done.value = true
}
</script>

<template>
  <div class="card">
    <div class="hstack" style="flex-wrap: nowrap; align-items: flex-start">
      <Icon name="phone" style="margin-top: 2px" />
      <span class="small">
        <b>{{ t('需要馬上有人陪？') }}</b><br />
        {{ HELP.counselor }}，{{ HELP.counselorWhere }}<br />
        {{ t(HELP.hotlineName) }} {{ HELP.hotline }}
      </span>
    </div>
    <button class="btn danger block" type="button" @click="start">{{ t('我現在需要馬上有人幫忙') }}</button>
  </div>

  <Modal v-model:open="open" :title="t('我們陪你找人')">
    <template v-if="!done">
      <p>{{ t('如果你現在有危險，請先打電話，或去找身邊的人，這比等網上回覆快。') }}</p>
      <div class="vstack" style="gap: 8px">
        <p class="note"><Icon name="phone" :size="20" /><span><b>{{ t(HELP.hotlineName) }}</b>{{ HELP.hotline }}</span></p>
        <p class="note"><Icon name="user" :size="20" /><span><b>{{ HELP.counselor }}</b>{{ HELP.counselorWhere }}</span></p>
      </div>
      <template v-if="canNotify">
        <label class="check">
          <input v-model="notify" type="checkbox" />
          <span>{{ t('同時通知樹洞管理員') }}<small>{{ aid ? t('管理員會看到你的對話。為了聯絡你，管理員可能會查看你的身份，查詢會留紀錄。') : t('管理員會看到你寫的訊息。為了聯絡你，管理員可能會查看你的身份，查詢會留紀錄。') }}</small></span>
        </label>
        <textarea v-if="notify" v-model="note" maxlength="500" :placeholder="t('想讓管理員知道什麼？（選填）')" style="min-height: 70px" />
      </template>
      <p v-else class="muted small">{{ t('發出一則訊息之後，才能從這裡通知樹洞管理員。現在請直接聯絡上面的資源。') }}</p>
      <p v-if="error" class="error">{{ t(error) }}</p>
      <div class="actions end">
        <button class="btn plain" type="button" @click="open = false">{{ t('返回') }}</button>
        <button v-if="canNotify && notify" class="btn alertfill" type="button" :disabled="busy" @click="send">{{ t('送出求助') }}</button>
      </div>
    </template>
    <template v-else>
      <p>{{ t('已經通知樹洞管理員。等待的時候，也請先撥打上面的電話。') }}</p>
      <div class="actions end"><button class="btn" type="button" @click="open = false">{{ t('知道了') }}</button></div>
    </template>
  </Modal>
</template>

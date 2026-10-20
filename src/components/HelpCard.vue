<script setup>
// 求助資源一直顯示（不靠關鍵詞觸發）。按「我現在需要馬上有人幫忙」時顯示熱線和諮詢中心，
// 有進行中的對話時可以同時通知樹洞管理員（預設勾選）
import { t } from '../i18n'
import { ref } from 'vue'
import { supabase } from '../supabase'
import { HELP } from '../help'
import { errorText } from '../format'
import Icon from './Icon.vue'
import Modal from './Modal.vue'

const props = defineProps({
  aid: { type: Number, default: null }, // 進行中那段對話；沒有就不能通知管理員
})

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
  if (!props.aid || !notify.value) return (open.value = false)
  busy.value = true
  error.value = ''
  const { error: e } = await supabase.rpc('hole_flag', { aid: props.aid, p_kind: 'need_help', note: note.value.trim() || null })
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
        {{ HELP.center }}，{{ HELP.place }}，{{ HELP.hours }}，{{ HELP.centerPhone }}<br />
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
        <p class="note"><Icon name="user" :size="20" /><span><b>{{ HELP.center }}</b>{{ HELP.place }}，{{ HELP.hours }}，{{ HELP.centerPhone }}</span></p>
      </div>
      <template v-if="aid">
        <label class="check">
          <input v-model="notify" type="checkbox" />
          <span>{{ t('同時通知樹洞管理員') }}<small>{{ t('管理員會看到你的對話。為了聯絡你，管理員可能會查看你的身份，查詢會留紀錄。') }}</small></span>
        </label>
        <textarea v-if="notify" v-model="note" maxlength="500" :placeholder="t('想讓管理員知道什麼？（選填）')" style="min-height: 70px" />
      </template>
      <p v-else class="muted small">{{ t('還沒有傾聽者接下你的訊息時，這裡沒辦法通知管理員，請直接聯絡上面的資源。') }}</p>
      <p v-if="error" class="error">{{ t(error) }}</p>
      <div class="actions end">
        <button class="btn plain" type="button" @click="open = false">{{ t('返回') }}</button>
        <button v-if="aid && notify" class="btn alertfill" type="button" :disabled="busy" @click="send">{{ t('送出求助') }}</button>
      </div>
    </template>
    <template v-else>
      <p>{{ t('已經通知樹洞管理員。等待的時候，也請先撥打上面的電話。') }}</p>
      <div class="actions end"><button class="btn" type="button" @click="open = false">{{ t('知道了') }}</button></div>
    </template>
  </Modal>
</template>

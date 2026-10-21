<script setup>
// 傾聽工作台：接單開關、等你接下的單（只看得到話題）、進行中的對話、避開的話題
import { t } from '../i18n'
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { auth, loadHole, listenerState } from '../auth'
import { TOPICS, TOPIC_LABEL } from '../constants'
import { ago, when, errorText } from '../format'
import Icon from '../components/Icon.vue'
import TabBar from '../components/TabBar.vue'

const router = useRouter()
const list = ref(null)
const lastMsg = ref({}) // assignment_id → 最後一則訊息
const error = ref('')
const busy = ref(false)

const state = computed(() => listenerState())
const me = computed(() => auth.hole.listener)

async function load() {
  error.value = ''
  await loadHole()
  if (state.value !== 'qualified' && state.value !== 'suspended') return
  const { data, error: e } = await supabase.rpc('hole_my_assignments')
  if (e) return (error.value = errorText(e))
  list.value = data
  // 進行中的對話最多幾段，各讀一次最後一則訊息，判斷是在等誰
  const active = data.filter((a) => a.status === 'active')
  const results = await Promise.all(active.map((a) => supabase.rpc('hole_get_conversation', { aid: a.assignment_id })))
  const map = {}
  active.forEach((a, i) => (map[a.assignment_id] = results[i].data?.messages?.at(-1) ?? null))
  lastMsg.value = map
}
onMounted(load)

const pending = computed(() => (list.value ?? []).filter((a) => a.status === 'pending'))
const active = computed(() => (list.value ?? []).filter((a) => a.status === 'active'))
const past = computed(() => (list.value ?? []).filter((a) => !['pending', 'active'].includes(a.status)))
const maxActive = computed(() => auth.hole.config?.max_active ?? 3)
const done = computed(() => (list.value ?? []).filter((a) => a.accepted_at).length)

const PAST_LABEL = { ended: '對方已結束', left: '你已退出', expired: '已轉給別人', declined: '已婉拒' }

async function setAvailable(value) {
  busy.value = true
  const { error: e } = await supabase.rpc('hole_set_listener', { p_available: value })
  busy.value = false
  if (e) return (error.value = errorText(e))
  await loadHole()
}

async function toggleAvoid(key) {
  const now = me.value.avoid_topics ?? []
  const next = now.includes(key) ? now.filter((x) => x !== key) : [...now, key]
  const { error: e } = await supabase.rpc('hole_set_listener', { p_avoid_topics: next })
  if (e) return (error.value = errorText(e))
  await loadHole()
}

async function accept(a) {
  busy.value = true
  const { error: e } = await supabase.rpc('hole_accept', { aid: a.assignment_id })
  busy.value = false
  if (e) {
    error.value = errorText(e)
    return load()
  }
  router.push(`/listen/${a.assignment_id}`)
}

async function decline(a) {
  busy.value = true
  const { error: e } = await supabase.rpc('hole_decline', { aid: a.assignment_id })
  busy.value = false
  if (e) error.value = errorText(e)
  load()
}
</script>

<template>
  <header class="topbar"><h1>{{ t('傾聽') }}</h1></header>
  <div class="page">
    <p v-if="error" class="error">{{ t(error) }}</p>

    <!-- 還不是傾聽者 -->
    <div v-if="state === 'none' || state === 'pledge'" class="card">
      <h3>{{ state === 'pledge' ? t('傾聽者承諾已更新') : t('成為傾聽者') }}</h3>
      <p v-if="state === 'pledge'">{{ t('承諾條文改版了，重新確認後就能繼續接單。') }}</p>
      <p v-else>{{ t('同學匿名寫下的訊息，會隨機派給受過培訓的傾聽者。完成約 10 分鐘的培訓、通過測驗並勾選承諾，就能開始接單。') }}</p>
      <router-link to="/train" class="btn block">{{ state === 'pledge' ? t('重新確認承諾') : t('開始培訓') }}</router-link>
    </div>

    <p v-else-if="state === 'suspended'" class="note warn">
      <Icon name="warn" :size="20" />
      <span><b>{{ t('你的傾聽者資格已暫停') }}</b>{{ t('原因：{reason}。手上的對話已轉給其他傾聽者。有疑問請聯絡樹洞管理員。', { reason: me.suspend_reason || t('未註明') }) }}</span>
    </p>

    <template v-if="state === 'qualified'">
      <div class="card">
        <button type="button" class="switch" role="switch" :aria-checked="me.available" :disabled="busy" @click="setAvailable(!me.available)">
          <span>
            <b>{{ me.available ? t('可接單') : t('暫停中') }}</b><br />
            <span class="muted small">{{ me.available ? t('有人發訊息時可能會派給你') : t('暫停期間不會收到新訊息，手上的對話照常') }}</span>
          </span>
          <span class="knob" aria-hidden="true" />
        </button>
        <div class="stats">
          <div><b>{{ active.length }}/{{ maxActive }}</b><span>{{ t('進行中') }}</span></div>
          <div><b>{{ done }}</b><span>{{ t('接過的對話') }}</span></div>
          <div><b>{{ me.timeout_count }}</b><span>{{ t('逾時') }}</span></div>
        </div>
      </div>

      <template v-if="pending.length">
        <div class="row"><h2 class="sec-t">{{ t('等你接下') }}</h2><span class="muted tiny">{{ t('只有你收到這幾則') }}</span></div>
        <div v-for="a in pending" :key="a.assignment_id" class="card">
          <div class="row">
            <span class="status st-live">{{ t(TOPIC_LABEL[a.topic]) }}</span>
            <span class="muted small"><Icon name="clock" :size="16" /> {{ ago(a.offered_at) }}</span>
          </div>
          <div class="veil"><Icon name="lock" :size="20" />{{ t('按「接下」後才看得到內容') }}</div>
          <div class="actions">
            <button class="btn" type="button" style="flex: 1" :disabled="busy" @click="accept(a)">{{ t('接下') }}</button>
            <button class="btn plain" type="button" style="flex: 1" :disabled="busy" @click="decline(a)">{{ t('這次不行') }}</button>
          </div>
          <p class="muted tiny">{{ t('30 分鐘內沒接，會自動轉給別人，不算逾時。') }}</p>
        </div>
      </template>
    </template>

    <template v-if="active.length">
      <h2 class="sec-t">{{ t('進行中') }}</h2>
      <router-link v-for="a in active" :key="a.assignment_id" :to="`/listen/${a.assignment_id}`" class="card thread-card">
        <div class="row">
          <span class="muted small">{{ t(TOPIC_LABEL[a.topic]) }} · {{ lastMsg[a.assignment_id] ? ago(lastMsg[a.assignment_id].created_at) : t('{time}接下', { time: ago(a.accepted_at) }) }}</span>
          <span v-if="lastMsg[a.assignment_id]?.from === 'me'" class="status st-wait">{{ t('等對方') }}</span>
          <span v-else class="status st-alert">{{ t('等你回覆') }}</span>
        </div>
        <p class="excerpt">{{ lastMsg[a.assignment_id]?.body ?? a.body }}</p>
      </router-link>
      <p class="muted tiny">{{ t('對方等了 12 小時沒收到回覆，系統會寄信提醒你；等滿 24 小時，對方可以選擇多找一位傾聽者，這時會記你一次逾時。') }}</p>
    </template>

    <template v-if="state === 'qualified'">
      <div class="card">
        <h3>{{ t('避開的話題') }}</h3>
        <div class="chips">
          <button v-for="x in TOPICS" :key="x.key" type="button" class="chip avoid" :aria-pressed="(me.avoid_topics ?? []).includes(x.key)" @click="toggleAvoid(x.key)">{{ t(x.label) }}</button>
        </div>
        <p class="muted tiny">{{ t('按下的話題之後不會派給你；已經派出的不受影響。') }}</p>
      </div>
      <p class="note"><Icon name="ear" :size="20" /><span>{{ t('累了就切到「暫停」。手上的對話也可以退出，系統會轉給別人。') }}</span></p>
    </template>

    <template v-if="past.length">
      <h2 class="sec-t">{{ t('之前的對話') }}</h2>
      <router-link v-for="a in past" :key="a.assignment_id" :to="`/listen/${a.assignment_id}`" class="card thread-card">
        <div class="row">
          <span class="muted small">{{ t(TOPIC_LABEL[a.topic]) }} · {{ when(a.accepted_at) }}</span>
          <span class="status st-done">{{ t(PAST_LABEL[a.status] ?? '已結束') }}</span>
        </div>
        <p class="excerpt">{{ a.body }}</p>
      </router-link>
    </template>
  </div>
  <TabBar />
</template>

<style scoped>
.switch { display: flex; align-items: center; justify-content: space-between; gap: 12px; border: 0; background: none; padding: 0; cursor: pointer; width: 100%; text-align: left; }
.switch .knob { width: 50px; height: 30px; border-radius: 999px; background: var(--forest); position: relative; flex: none; transition: background .2s; }
.switch .knob::after { content: ""; position: absolute; top: 3px; left: 23px; width: 24px; height: 24px; border-radius: 50%; background: #fff; transition: left .2s; }
.switch[aria-checked="false"] .knob { background: #A3ADA7; }
.switch[aria-checked="false"] .knob::after { left: 3px; }
</style>

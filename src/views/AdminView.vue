<script setup>
// 樹洞管理：只看得到被檢舉、被標記「需要協助」或發出者自己求助的對話。
// 看對話、查身份、暫停資格、標記處理、增刪危機關鍵詞，每一步都寫進 hole_audit_log，所有管理員都看得到。
// 統計只有次數和時間，不含任何內容或身份
import { t } from '../i18n'
import { ref, computed, watch } from 'vue'
import { supabase } from '../supabase'
import { auth } from '../auth'
import { TOPIC_LABEL, LEAVE_LABEL } from '../constants'
import { when, errorText } from '../format'
import Icon from '../components/Icon.vue'
import Modal from '../components/Modal.vue'
import TabBar from '../components/TabBar.vue'

const TABS = [
  { key: 'open', label: '未處理' },
  { key: 'resolved', label: '已處理' },
  { key: 'listeners', label: '傾聽者' },
  { key: 'stats', label: '統計' },
  { key: 'words', label: '關鍵詞' },
  { key: 'log', label: '操作紀錄' },
  { key: 'admins', label: '管理員' },
]
const tab = ref('open')
const reports = ref(null)
const openCount = ref(0)
const listeners = ref(null)
const log = ref(null)
const stats = ref(null)
const words = ref(null)
const error = ref('')
const notice = ref('')

async function load() {
  error.value = ''
  if (tab.value === 'open' || tab.value === 'resolved') {
    reports.value = null
    const { data, error: e } = await supabase.rpc('hole_admin_reports', { p_status: tab.value })
    if (e) return (error.value = errorText(e))
    reports.value = data
    if (tab.value === 'open') openCount.value = data.length
  } else if (tab.value === 'listeners') {
    const { data, error: e } = await supabase.rpc('hole_admin_listeners')
    if (e) return (error.value = errorText(e))
    listeners.value = data
  } else if (tab.value === 'log') {
    const { data, error: e } = await supabase.from('hole_audit_log').select('*').order('created_at', { ascending: false }).limit(100)
    if (e) return (error.value = errorText(e))
    log.value = data
  } else if (tab.value === 'stats') {
    const { data, error: e } = await supabase.rpc('hole_admin_stats', { p_weeks: 8 })
    if (e) return (error.value = errorText(e))
    stats.value = data
  } else if (tab.value === 'words') {
    const { data, error: e } = await supabase.from('hole_crisis_words').select('word').order('word')
    if (e) return (error.value = errorText(e))
    words.value = data.map((x) => x.word)
  }
}
watch(tab, () => {
  notice.value = ''
  load()
}, { immediate: true })

function kindLabel(r) {
  if (r.kind === 'swap_limit') return '換人次數達上限'
  if (r.kind === 'report') return r.by_poster ? '發出者檢舉' : '傾聽者檢舉'
  if (r.by_poster) return r.has_listener ? '發出者自己求助' : '發出者求助（還沒有傾聽者接下）'
  return r.leave_reason === 'crisis' ? '傾聽者退出並要求危機協助' : '傾聽者標記需要協助'
}
const isUrgent = (r) => r.kind === 'need_help'

// 看對話（每次都記錄）
const convs = ref({})
const viewing = ref(null)
async function viewConversation(r) {
  viewing.value = r.id
  const { data, error: e } = await supabase.rpc('hole_admin_view_conversation', { report_id: r.id })
  viewing.value = null
  if (e) return (error.value = errorText(e))
  convs.value = { ...convs.value, [r.id]: data }
}

// 查身份
const revealFor = ref(null)
const revealWho = ref('poster')
const revealReason = ref('')
const revealBusy = ref(false)
const revealError = ref('')
const revealed = ref({})
function startReveal(r) {
  revealFor.value = r
  revealWho.value = 'poster'
  revealReason.value = ''
  revealError.value = ''
}
async function reveal() {
  revealBusy.value = true
  revealError.value = ''
  const r = revealFor.value
  const { data, error: e } = await supabase.rpc('hole_admin_reveal_identity', { report_id: r.id, who: revealWho.value, reason: revealReason.value.trim() })
  revealBusy.value = false
  if (e) return (revealError.value = errorText(e))
  revealed.value = { ...revealed.value, [r.id]: { ...data, who: revealWho.value } }
  revealFor.value = null
}

// 標記已處理／暫停傾聽者
const actFor = ref(null) // { report, kind: 'resolve' | 'suspend' }
const actNote = ref('')
const actBusy = ref(false)
const actError = ref('')
function startAct(report, kind) {
  actFor.value = { report, kind }
  actNote.value = ''
  actError.value = ''
}
async function act() {
  const { report, kind } = actFor.value
  actBusy.value = true
  actError.value = ''
  const { error: e } = kind === 'resolve'
    ? await supabase.rpc('hole_admin_resolve_report', { report_id: report.id, note: actNote.value.trim() || null })
    : await supabase.rpc('hole_admin_suspend_listener', { report_id: report.id, reason: actNote.value.trim() })
  actBusy.value = false
  if (e) return (actError.value = errorText(e))
  actFor.value = null
  notice.value = kind === 'resolve' ? '已標記處理。' : '已暫停這位傾聽者，他手上的對話已轉給別人。'
  load()
}

// 評分只給管理員參考，不會自動暫停資格；「沒幫助」至少 3 次且多於「有幫助」時提醒
const lowRated = (l) => l.rated_unhelpful >= 3 && l.rated_unhelpful > l.rated_helpful

async function restore(l) {
  const { error: e } = await supabase.rpc('hole_admin_restore_listener', { uid: l.user_id, reason: null })
  if (e) return (error.value = errorText(e))
  notice.value = '已恢復資格，逾時次數歸零。'
  load()
}

// 管理員名單（只能用學號新增或移除；名單本身只看得到人數）
const sid = ref('')
const adminBusy = ref(false)
async function changeAdmin(add) {
  if (!/^\d{8}$/.test(sid.value.trim())) return (error.value = '請輸入八位學號')
  adminBusy.value = true
  error.value = ''
  const { error: e } = await supabase.rpc(add ? 'hole_add_admin' : 'hole_remove_admin', { sid: sid.value.trim() })
  adminBusy.value = false
  if (e) return (error.value = errorText(e))
  notice.value = add ? '已新增樹洞管理員。' : '已移除樹洞管理員。'
  sid.value = ''
}

// 統計：分鐘數換成好讀的長度
function minutes(m) {
  if (m == null) return '—'
  if (m < 60) return t('{n} 分鐘', { n: m })
  if (m < 48 * 60) return t('{n} 小時', { n: Math.round(m / 6) / 10 })
  return t('{n} 天', { n: Math.round(m / 144) / 10 })
}
function weekLabel(start) {
  const d = new Date(start + 'T00:00:00')
  const e = new Date(d.getTime() + 6 * 86400000)
  return `${d.getMonth() + 1}/${d.getDate()}–${e.getMonth() + 1}/${e.getDate()}`
}

// 危機關鍵詞：訊息裡出現任何一個詞，發出者就會看到心理老師和求助熱線
const newWord = ref('')
const wordBusy = ref(false)
const removing = ref(null)
async function addWord() {
  const w = newWord.value.trim()
  if (!w) return
  wordBusy.value = true
  error.value = ''
  notice.value = ''
  const { error: e } = await supabase.rpc('hole_admin_add_crisis_word', { p_word: w })
  wordBusy.value = false
  if (e) return (error.value = errorText(e))
  notice.value = t('已新增「{w}」。', { w })
  newWord.value = ''
  load()
}
async function removeWord() {
  const w = removing.value
  wordBusy.value = true
  error.value = ''
  notice.value = ''
  const { error: e } = await supabase.rpc('hole_admin_remove_crisis_word', { p_word: w })
  wordBusy.value = false
  removing.value = null
  if (e) return (error.value = errorText(e))
  notice.value = t('已移除「{w}」。', { w })
  load()
}

const ACTION_LABEL = {
  view_conversation: '查看對話',
  reveal_identity: '查詢身份',
  resolve_report: '標記已處理',
  suspend_listener: '暫停傾聽者',
  restore_listener: '恢復傾聽者',
  add_admin: '新增管理員',
  remove_admin: '移除管理員',
  add_crisis_word: '新增危機關鍵詞',
  remove_crisis_word: '移除危機關鍵詞',
}
const myId = computed(() => auth.session?.user?.id)
</script>

<template>
  <header class="topbar"><h1>{{ t('樹洞管理') }}</h1></header>
  <div class="page">
    <div class="chips">
      <button v-for="x in TABS" :key="x.key" type="button" class="chip" :aria-pressed="tab === x.key" @click="tab = x.key">
        {{ t(x.label) }}<span v-if="x.key === 'open' && openCount" class="count">{{ openCount }}</span>
      </button>
    </div>
    <p v-if="error" class="error">{{ t(error) }}</p>
    <p v-if="notice" class="note" role="status"><Icon name="check" :size="20" /><span>{{ t(notice) }}</span></p>

    <!-- 檢舉與求助 -->
    <template v-if="tab === 'open' || tab === 'resolved'">
      <p class="note"><Icon name="shield" :size="20" /><span>{{ t('你只看得到被檢舉、被標記「需要協助」，或發出者自己求助的對話。查看對話和查詢身份都會留紀錄。') }}</span></p>
      <p v-if="!reports" class="muted center">{{ t('載入中…') }}</p>
      <p v-else-if="!reports.length" class="empty">{{ tab === 'open' ? t('目前沒有待處理的事。') : t('還沒有處理過的紀錄。') }}</p>
      <div v-for="r in reports ?? []" :key="r.id" class="card" :class="{ urgent: isUrgent(r) && r.status === 'open' }">
        <div class="row">
          <span class="muted small">{{ t(TOPIC_LABEL[r.topic]) }} · {{ t(kindLabel(r)) }} · {{ when(r.created_at) }}</span>
          <span class="status" :class="r.status === 'open' ? 'st-alert' : 'st-done'">{{ r.status === 'open' ? t('未處理') : t('已處理') }}</span>
        </div>
        <p v-if="r.note" class="case small"><b>{{ t('留言：') }}</b>{{ r.note }}</p>
        <p v-if="r.leave_reason && r.leave_reason !== 'crisis'" class="muted small">{{ t('傾聽者已退出：{reason}', { reason: t(LEAVE_LABEL[r.leave_reason]) }) }}</p>
        <p class="muted small">{{ !r.has_listener ? (r.conversation_active ? t('訊息還在等傾聽者接下。') : t('訊息已結束。')) : r.conversation_active ? t('對話還在進行。') : t('對話已結束。') }}<template v-if="r.swap_count"> {{ t('這則訊息換過 {n} 次傾聽者。', { n: r.swap_count }) }}</template></p>
        <p v-if="r.resolved_note" class="small">{{ t('處理說明：{note}', { note: r.resolved_note }) }}</p>

        <div v-if="convs[r.id]" class="vstack">
          <div class="orig small">{{ convs[r.id].body }}</div>
          <div v-for="(m, i) in convs[r.id].messages" :key="i" class="bub small" :class="m.from">
            {{ m.body }}<time>{{ m.from === 'poster' ? t('發出者') : t('傾聽者') }} · {{ when(m.created_at) }}</time>
          </div>
          <p v-if="!convs[r.id].messages.length" class="muted small">{{ r.has_listener ? t('這段對話還沒有訊息。') : t('還沒有傾聽者接下，只有發出者寫的原訊息。') }}</p>
        </div>

        <dl v-if="revealed[r.id]" class="idbox">
          <dt>{{ t('對象') }}</dt><dd>{{ revealed[r.id].who === 'poster' ? t('發出者') : t('傾聽者') }}</dd>
          <dt>{{ t('姓名') }}</dt><dd>{{ revealed[r.id].full_name }}</dd>
          <dt>{{ t('學號') }}</dt><dd>{{ revealed[r.id].student_id }}</dd>
          <dt>Email</dt><dd>{{ revealed[r.id].email }}</dd>
        </dl>

        <div class="actions">
          <button v-if="!convs[r.id]" class="btn small" type="button" :disabled="viewing === r.id" @click="viewConversation(r)">{{ t('查看對話') }}</button>
          <button class="btn danger small" type="button" @click="startReveal(r)">{{ t('查詢身份') }}</button>
          <template v-if="r.status === 'open'">
            <button v-if="r.kind === 'report' && r.by_poster" class="btn plain small" type="button" @click="startAct(r, 'suspend')">{{ t('暫停這位傾聽者') }}</button>
            <button class="btn plain small" type="button" @click="startAct(r, 'resolve')">{{ t('標記已處理') }}</button>
          </template>
        </div>
      </div>
    </template>

    <!-- 傾聽者 -->
    <template v-if="tab === 'listeners'">
      <p v-if="!listeners" class="muted center">{{ t('載入中…') }}</p>
      <p v-else-if="!listeners.length" class="empty">{{ t('還沒有人通過測驗。') }}</p>
      <div v-for="l in listeners ?? []" :key="l.user_id" class="card">
        <div class="row">
          <b>{{ l.full_name }} · {{ l.student_id }}</b>
          <span v-if="l.suspended_at" class="status st-alert">{{ t('已暫停') }}</span>
          <span v-else-if="l.qualified" class="status" :class="l.available ? 'st-live' : 'st-wait'">{{ l.available ? t('可接單') : t('暫停中') }}</span>
          <span v-else class="status st-wait">{{ t('還沒勾選承諾') }}</span>
        </div>
        <p class="muted small">{{ t('測驗通過：{time}', { time: when(l.quiz_passed_at) }) }}<template v-if="l.pledged_at"> · {{ t('承諾：{time}', { time: when(l.pledged_at) }) }}</template> · {{ t('逾時 {n} 次', { n: l.timeout_count }) }}</p>
        <p v-if="l.rated_helpful + l.rated_okay + l.rated_unhelpful" class="small" :class="{ alert: lowRated(l) }">
          {{ t('發出者評分：有幫助 {a}、普通 {b}、沒幫助 {c}', { a: l.rated_helpful, b: l.rated_okay, c: l.rated_unhelpful }) }}<template v-if="lowRated(l)"> · {{ t('「沒幫助」偏多，可以留意') }}</template>
        </p>
        <template v-if="l.suspended_at">
          <p class="small">{{ t('暫停原因：{reason}', { reason: l.suspend_reason || t('未註明') }) }}</p>
          <button class="btn plain small" type="button" style="align-self: flex-start" @click="restore(l)">{{ t('恢復資格') }}</button>
        </template>
      </div>
    </template>

    <!-- 統計 -->
    <template v-if="tab === 'stats'">
      <p class="note"><Icon name="lock" :size="20" /><span>{{ t('只有次數和時間，不含任何訊息內容或身份。週一開始算。') }}</span></p>
      <p v-if="!stats" class="muted center">{{ t('載入中…') }}</p>
      <template v-else>
        <div class="card">
          <h3>{{ t('現在') }}</h3>
          <div class="stats">
            <div><b>{{ stats.listeners_available }}</b><span>{{ t('可接單的傾聽者') }}</span></div>
            <div><b>{{ stats.threads_open }}</b><span>{{ t('進行中的訊息') }}</span></div>
            <div><b :class="{ alert: stats.threads_waiting }">{{ stats.threads_waiting }}</b><span>{{ t('還沒有人接下') }}</span></div>
          </div>
          <p class="muted small">{{ t('通過測驗、承諾是最新版、沒被暫停的傾聽者共 {n} 位。', { n: stats.listeners_qualified }) }}</p>
        </div>
        <div v-for="(w, i) in stats.weeks" :key="w.week_start" class="card">
          <div class="row">
            <h3>{{ weekLabel(w.week_start) }}</h3>
            <span v-if="i === 0" class="muted small">{{ t('本週（到目前為止）') }}</span>
          </div>
          <dl class="wk small">
            <dt>{{ t('新訊息') }}</dt><dd>{{ w.posted }}<template v-if="w.posted"> · {{ t('{n} 則有人接下', { n: w.got_listener }) }}</template></dd>
            <dt>{{ t('多久有人接') }}</dt><dd>{{ w.wait_median_min == null ? '—' : t('一半在 {a} 內，平均 {b}', { a: minutes(w.wait_median_min), b: minutes(w.wait_avg_min) }) }}</dd>
            <dt>{{ t('接下後第一次回覆') }}</dt><dd>{{ w.first_reply_avg_min == null ? '—' : t('平均 {a}', { a: minutes(w.first_reply_avg_min) }) }}</dd>
            <dt>{{ t('對話則數') }}</dt><dd>{{ t('發出者 {a}、傾聽者 {b}', { a: w.messages_poster, b: w.messages_listener }) }}</dd>
            <dt>{{ t('婉拒／沒接') }}</dt><dd>{{ t('婉拒 {a}、30 分鐘沒接 {b}', { a: w.declined, b: w.not_accepted }) }}</dd>
            <dt>{{ t('等回覆') }}</dt><dd :class="{ alert: w.late }">{{ t('25 小時提醒 {a}、50 小時逾時 {b}', { a: w.reminded, b: w.late }) }}</dd>
            <dt>{{ t('求助／檢舉') }}</dt><dd :class="{ alert: w.need_help }">{{ t('需要協助 {a}、檢舉 {b}', { a: w.need_help, b: w.reports }) }}</dd>
          </dl>
        </div>
      </template>
    </template>

    <!-- 危機關鍵詞 -->
    <template v-if="tab === 'words'">
      <div class="card">
        <h3>{{ t('危機關鍵詞') }}</h3>
        <p class="muted small">{{ t('發出者的訊息裡出現任何一個詞，就會看到心理老師和求助熱線。系統只比對字面，簡體和繁體要分別加；增刪都會寫進操作紀錄。') }}</p>
        <form class="addword" @submit.prevent="addWord">
          <input v-model="newWord" type="text" maxlength="20" :placeholder="t('例如：撐不下去')" :aria-label="t('新增關鍵詞')" />
          <button class="btn" type="submit" :disabled="wordBusy || !newWord.trim()">{{ t('新增') }}</button>
        </form>
        <p v-if="!words" class="muted small">{{ t('載入中…') }}</p>
        <p v-else-if="!words.length" class="empty">{{ t('名單是空的，目前不會顯示任何求助提示。') }}</p>
        <div v-else class="chips">
          <button v-for="w in words" :key="w" type="button" class="chip" :aria-label="t('移除「{w}」', { w })" @click="removing = w">{{ w }}<Icon name="close" :size="16" /></button>
        </div>
      </div>
    </template>

    <!-- 操作紀錄 -->
    <template v-if="tab === 'log'">
      <p class="note"><Icon name="lock" :size="20" /><span>{{ t('所有樹洞管理員都看得到這份紀錄：誰、何時、為什麼查看對話或身份。') }}</span></p>
      <p v-if="!log" class="muted center">{{ t('載入中…') }}</p>
      <p v-else-if="!log.length" class="empty">{{ t('還沒有紀錄。') }}</p>
      <div v-else class="card log small">
        <div v-for="x in log" :key="x.id">
          <b>{{ t(ACTION_LABEL[x.action] ?? x.action) }}</b>
          <template v-if="x.target"> · {{ x.target === 'poster' ? t('發出者') : t('傾聽者') }}</template>
          <template v-if="x.report_id"> · {{ t('事件 #{id}', { id: x.report_id }) }}</template>
          · {{ x.admin_id === myId ? t('你') : t('其他管理員') }} · {{ when(x.created_at) }}
          <br v-if="x.reason" /><span v-if="x.reason" class="muted">{{ x.reason }}</span>
        </div>
      </div>
    </template>

    <!-- 管理員 -->
    <template v-if="tab === 'admins'">
      <div class="card">
        <h3>{{ t('新增或移除樹洞管理員') }}</h3>
        <p class="muted small">{{ t('樹洞管理員可以查看被檢舉或求助的對話，必要時查詢身份。對方要先通過校園卡驗證。') }}</p>
        <label class="field">
          <span>{{ t('學號') }}</span>
          <input v-model="sid" type="text" inputmode="numeric" maxlength="8" />
        </label>
        <div class="actions">
          <button class="btn" type="button" :disabled="adminBusy" @click="changeAdmin(true)">{{ t('新增') }}</button>
          <button class="btn danger" type="button" :disabled="adminBusy" @click="changeAdmin(false)">{{ t('移除') }}</button>
        </div>
      </div>
    </template>
  </div>
  <TabBar />

  <Modal :open="!!revealFor" :title="t('查詢身份')" @update:open="revealFor = null">
    <p class="small">{{ t('這次查詢會寫進操作紀錄，所有管理員都看得到誰、何時、為什麼查。') }}</p>
    <div class="chips">
      <button type="button" class="chip" :aria-pressed="revealWho === 'poster'" @click="revealWho = 'poster'">{{ t('發出者') }}</button>
      <button v-if="revealFor?.has_listener" type="button" class="chip" :aria-pressed="revealWho === 'listener'" @click="revealWho = 'listener'">{{ t('傾聽者') }}</button>
    </div>
    <label class="field">
      <span>{{ t('查詢理由（必填）') }}</span>
      <textarea v-model="revealReason" :placeholder="t('例如：發出者提到自傷念頭，需要通知心理老師')" style="min-height: 80px" />
    </label>
    <p v-if="revealError" class="error">{{ t(revealError) }}</p>
    <div class="actions end">
      <button class="btn plain" type="button" @click="revealFor = null">{{ t('取消') }}</button>
      <button class="btn danger" type="button" :disabled="revealBusy || revealReason.trim().length < 4" @click="reveal">{{ t('查詢並記錄') }}</button>
    </div>
  </Modal>

  <Modal :open="!!removing" :title="t('移除這個關鍵詞？')" @update:open="removing = null">
    <p class="small">{{ t('移除「{w}」後，訊息裡出現這個詞就不會再顯示求助提示。這次操作會寫進操作紀錄。', { w: removing }) }}</p>
    <div class="actions end">
      <button class="btn plain" type="button" @click="removing = null">{{ t('取消') }}</button>
      <button class="btn danger" type="button" :disabled="wordBusy" @click="removeWord">{{ t('移除') }}</button>
    </div>
  </Modal>

  <Modal :open="!!actFor" :title="actFor?.kind === 'suspend' ? t('暫停這位傾聽者？') : t('標記已處理')" @update:open="actFor = null">
    <p v-if="actFor?.kind === 'suspend'" class="small">{{ t('他手上所有進行中的對話會轉給別人，之後不會再派單給他，直到有管理員恢復資格。') }}</p>
    <label class="field">
      <span>{{ actFor?.kind === 'suspend' ? t('理由（必填）') : t('處理說明（選填）') }}</span>
      <textarea v-model="actNote" :placeholder="actFor?.kind === 'suspend' ? '' : t('例如：已聯絡心理老師跟進')" style="min-height: 80px" />
    </label>
    <p v-if="actError" class="error">{{ t(actError) }}</p>
    <div class="actions end">
      <button class="btn plain" type="button" @click="actFor = null">{{ t('取消') }}</button>
      <button class="btn" :class="{ danger: actFor?.kind === 'suspend' }" type="button" :disabled="actBusy || (actFor?.kind === 'suspend' && actNote.trim().length < 4)" @click="act">{{ t('確認') }}</button>
    </div>
  </Modal>
</template>

<style scoped>
.urgent { outline: 1.5px solid var(--alert); }
.count { margin-left: 6px; }
p.alert, dd.alert, b.alert { color: var(--alert); font-weight: 600; }
.wk { display: grid; grid-template-columns: auto 1fr; gap: 6px 14px; margin: 0; }
.wk dt { color: var(--muted); }
.wk dd { margin: 0; font-variant-numeric: tabular-nums; }
.addword { display: flex; gap: 8px; }
.addword input { flex: 1; min-width: 0; }
.case { border-left: 3px solid var(--alert); padding-left: 12px; white-space: pre-line; }
.bub { max-width: 82%; padding: 8px 12px; border-radius: 14px; white-space: pre-wrap; overflow-wrap: anywhere; }
.bub.poster { background: var(--mist); align-self: flex-start; }
.bub.listener { background: var(--leaf-soft); align-self: flex-end; }
.bub time { display: block; font-size: 12px; opacity: .7; }
.idbox { display: grid; grid-template-columns: auto 1fr; gap: 4px 16px; background: var(--mist); border-radius: 12px; padding: 12px 14px; margin: 0; }
.idbox dt { color: var(--muted); }
.idbox dd { margin: 0; font-weight: 700; word-break: break-all; }
.log { gap: 10px; }
.log > div { border-left: 3px solid var(--leaf); padding-left: 12px; }
</style>

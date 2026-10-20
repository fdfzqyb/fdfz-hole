<script setup>
// 成為傾聽者：培訓 → 測驗 → 承諾。測驗答案只在資料庫，交卷後才知道分數
import { t } from '../i18n'
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { auth, loadHole, listenerState } from '../auth'
import { PLEDGE } from '../constants'
import { when, errorText } from '../format'
import Icon from '../components/Icon.vue'
import TabBar from '../components/TabBar.vue'

const router = useRouter()
const step = ref(1)
const error = ref('')

onMounted(async () => {
  await loadHole()
  const s = listenerState()
  if (s === 'pledge') step.value = 3
  if (s === 'qualified') step.value = 4
})

// 培訓內容
const MODULES = [
  {
    title: '怎麼聽',
    points: [
      '先接住感受，再談事情：「聽起來你很失望」比「別想太多」有用。',
      '多用開放式問題，讓對方說得更多，例如「那時候你在想什麼？」',
      '不評判、不說教。對方做了你不認同的事，你的角色仍然是聽，不是糾正。',
      '對方要你替他做決定時，陪他把想法說清楚，決定留給他。',
    ],
  },
  {
    title: '界線',
    points: [
      '不追問身份，不透露自己是誰，不交換聯絡方式，不約見面。',
      '不截圖、不轉述，就算去掉可辨認的細節也不行。',
      '認出對方是誰時，退出這段對話，讓系統改派給別人，在現實中也絕口不提。',
      '對方越來越依賴你時，溫和說明你無法隨時在線，陪他找其他支持。',
    ],
  },
  {
    title: '危機識別',
    points: [
      '自傷或輕生的念頭（包括「睡著不醒也好」這類說法）、傷害他人的打算、正在或曾經受到侵害，都是危機信號。',
      '看到信號就按「需要協助」交給管理員，同時繼續陪對方。不要答應保密，也不要自己扛。',
      '直接而溫和地問「你有想過結束生命嗎？」不會讓對方產生這個念頭，反而能讓他說出來。',
      '不追問侵害的細節，不替對方決定要不要報警；這些交給管理員和專業的人。',
    ],
  },
  {
    title: '照顧自己',
    points: [
      '可以不接、可以暫停，也可以退出對話並選「我現在狀態不好」。',
      '對方的經歷勾起你自己的難受時，先照顧好自己，系統會另找人。',
      '聽完一段沉重的對話後，你也可以去心理諮詢中心聊聊，不用透露對話內容。',
    ],
  },
]

// 測驗
const quiz = ref(null)
const index = ref(0)
const answers = ref({})
const result = ref(null)
const submitting = ref(false)

async function startQuiz() {
  error.value = ''
  step.value = 2
  result.value = null
  const { data, error: e } = await supabase.rpc('hole_get_quiz')
  if (e) return (error.value = errorText(e))
  quiz.value = data
  index.value = 0
  answers.value = {}
}

const question = computed(() => quiz.value?.questions?.[index.value])
const total = computed(() => quiz.value?.questions?.length ?? 0)
const chosen = computed({
  get: () => answers.value[question.value?.id],
  set: (v) => (answers.value[question.value.id] = v),
})
const isLast = computed(() => index.value === total.value - 1)

async function next() {
  if (chosen.value === undefined) return
  if (!isLast.value) return index.value++
  submitting.value = true
  error.value = ''
  const { data, error: e } = await supabase.rpc('hole_submit_quiz', { answers: answers.value })
  submitting.value = false
  if (e) return (error.value = errorText(e))
  result.value = data
  if (data.passed) await loadHole()
}

// 承諾
const pledged = ref(PLEDGE.map(() => false))
const allPledged = computed(() => pledged.value.every(Boolean))
const pledging = ref(false)

async function sign() {
  pledging.value = true
  error.value = ''
  const { error: e } = await supabase.rpc('hole_sign_pledge', { p_version: auth.hole.config?.pledge_version })
  pledging.value = false
  if (e) return (error.value = errorText(e))
  await loadHole()
  router.push('/listen')
}

const STEPS = ['培訓', '測驗', '承諾']
const passRatio = computed(() => Math.round((auth.hole.config?.quiz_pass_ratio ?? 0.8) * 100))
</script>

<template>
  <header class="topbar">
    <button class="back" type="button" :aria-label="t('返回')" @click="router.push('/listen')"><Icon name="back" :size="24" /></button>
    <h1>{{ t('成為傾聽者') }}</h1>
  </header>
  <div class="page">
    <ol class="steps">
      <li v-for="(s, i) in STEPS" :key="s" :class="{ on: step === i + 1, done: step > i + 1 }" :aria-current="step === i + 1 ? 'step' : undefined">
        <span>{{ t(['第一步', '第二步', '第三步'][i]) }}</span><b>{{ t(s) }}</b>
      </li>
    </ol>
    <p v-if="error" class="error">{{ t(error) }}</p>

    <!-- 培訓 -->
    <template v-if="step === 1">
      <p class="muted">{{ t('四個單元，約 10 分鐘。讀完再開始測驗。') }}</p>
      <div v-for="(m, i) in MODULES" :key="m.title" class="card">
        <h3><span class="av">{{ i + 1 }}</span> {{ t(m.title) }}</h3>
        <ul class="points">
          <li v-for="p in m.points" :key="p">{{ t(p) }}</li>
        </ul>
      </div>
      <button class="btn block" type="button" @click="startQuiz">{{ t('開始測驗') }}</button>
    </template>

    <!-- 測驗 -->
    <template v-if="step === 2">
      <p v-if="!quiz && !error" class="muted center">{{ t('載入中…') }}</p>
      <div v-else-if="quiz?.retry_after" class="card">
        <h3>{{ t('還不能重考') }}</h3>
        <p>{{ t('上次測驗沒有通過，{time}之後可以重考。這段時間可以再讀一次培訓內容。', { time: when(quiz.retry_after) }) }}</p>
        <button class="btn ghost" type="button" @click="step = 1">{{ t('回到培訓') }}</button>
      </div>
      <div v-else-if="quiz && !total" class="card"><p>{{ t('測驗題目還沒設定，請聯絡樹洞管理員。') }}</p></div>

      <div v-else-if="result" class="card">
        <template v-if="result.passed">
          <h3>{{ t('測驗通過') }}</h3>
          <p>{{ t('{total} 題答對 {score} 題，紅線題全對。最後逐條確認傾聽者承諾。', result) }}</p>
          <button class="btn block" type="button" @click="step = 3">{{ t('下一步') }}</button>
        </template>
        <template v-else>
          <h3>{{ t('這次沒有通過') }}</h3>
          <p>{{ t('{total} 題答對 {score} 題。', result) }}<template v-if="!result.redline_ok">{{ t('紅線題（保密和危機處理）有答錯，紅線題必須全對。') }}</template></p>
          <p class="muted small">{{ t('{time}之後可以重考。測驗不會告訴你錯在哪一題，請再讀一次培訓內容。', { time: when(result.retry_after) }) }}</p>
          <button class="btn ghost" type="button" @click="step = 1">{{ t('回到培訓') }}</button>
        </template>
      </div>

      <template v-else-if="question">
        <div class="card">
          <div class="row">
            <span class="muted small">{{ t('第 {n} 題，共 {total} 題', { n: index + 1, total }) }}</span>
            <span v-if="question.redline" class="status st-alert">{{ t('紅線題 · 須答對') }}</span>
          </div>
          <div class="bar" aria-hidden="true"><i :style="{ width: `${((index + 1) / total) * 100}%` }" /></div>
          <h2 class="q">{{ question.prompt }}</h2>
          <fieldset class="vstack" style="gap: 10px">
            <legend class="sr">{{ t('選一個答案') }}</legend>
            <label v-for="(o, i) in question.options" :key="i" class="opt">
              <input v-model="chosen" type="radio" :name="`q${question.id}`" :value="i" />
              <span>{{ o }}</span>
            </label>
          </fieldset>
          <div class="actions">
            <button v-if="index > 0" class="btn plain" type="button" @click="index--">{{ t('上一題') }}</button>
            <button class="btn" type="button" style="flex: 1" :disabled="chosen === undefined || submitting" @click="next">{{ isLast ? t('交卷') : t('下一題') }}</button>
          </div>
        </div>
        <p class="note"><Icon name="shield" :size="20" /><span>{{ t('保密和危機處理的紅線題必須全對，整份要答對 {p}% 以上。沒通過的話，過幾天可以重考。', { p: passRatio }) }}</span></p>
      </template>
    </template>

    <!-- 承諾 -->
    <template v-if="step === 3">
      <div class="card">
        <h3>{{ t('傾聽者承諾') }}</h3>
        <label v-for="(p, i) in PLEDGE" :key="i" class="check">
          <input v-model="pledged[i]" type="checkbox" />
          <span>{{ t(p) }}</span>
        </label>
      </div>
      <button class="btn block" type="button" :disabled="!allPledged || pledging" @click="sign">{{ t('確認，成為傾聽者') }}</button>
    </template>

    <!-- 已經是傾聽者 -->
    <div v-if="step === 4" class="card">
      <h3>{{ t('你已經是傾聽者') }}</h3>
      <p>{{ t('可以回頭再讀一次培訓內容。') }}</p>
      <div class="actions">
        <button class="btn ghost" type="button" @click="step = 1">{{ t('看培訓內容') }}</button>
        <router-link to="/listen" class="btn">{{ t('回到傾聽') }}</router-link>
      </div>
    </div>
  </div>
  <TabBar />
</template>

<style scoped>
.steps { list-style: none; margin: 0; padding: 0; display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px; }
.steps li { border: 1px solid var(--border); background: var(--white); border-radius: 12px; padding: 8px; display: flex; flex-direction: column; align-items: center; gap: 2px; }
.steps li span { font-size: 12px; color: var(--muted); }
.steps li.on { background: var(--forest); border-color: var(--forest); color: #fff; }
.steps li.on span { color: var(--leaf-soft); }
.steps li.done { background: var(--leaf-soft); border-color: var(--leaf-soft); }
.card h3 { display: flex; align-items: center; gap: 8px; }
.points { margin: 0; padding-left: 20px; display: flex; flex-direction: column; gap: 6px; }
.q { font-size: 19px; }
fieldset { border: 0; padding: 0; margin: 0; }
.bar { height: 6px; background: var(--mist-deep); border-radius: 999px; overflow: hidden; }
.bar i { display: block; height: 100%; background: var(--leaf); }
</style>

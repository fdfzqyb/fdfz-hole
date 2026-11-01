<script setup>
import { t } from '../i18n'
import { ref, computed, onMounted, watch } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { TOPICS } from '../constants'
import { HELP } from '../help'
import { errorText } from '../format'
import { mentionsCrisis as matchCrisis } from '../crisis'
import { loadDraft, saveDraft, clearDraft, draftEnabled, setDraftEnabled } from '../draft'
import IdentityNote from '../components/IdentityNote.vue'
import QuickExit from '../components/QuickExit.vue'
import Icon from '../components/Icon.vue'
import HelpCard from '../components/HelpCard.vue'
import TabBar from '../components/TabBar.vue'

const router = useRouter()
const body = ref('')
const topic = ref('')
const avoidClassmates = ref(true)
const busy = ref(false)
const error = ref('')
const words = ref([])
const exceptions = ref([])
const activeAid = ref(null)
const activeTid = ref(null)
// 再找上次那位：之前回覆過你、你沒換掉的傾聽者（一段對話一個選項，對方仍然匿名）
const pastListeners = ref([])
const prefer = ref('')

// 草稿只存在這台裝置，24 小時後自動清掉；可以關掉
const keepDraft = ref(draftEnabled())
const restored = ref(false)
const saved = loadDraft()
if (saved) {
  body.value = saved.body
  topic.value = saved.topic ?? ''
  restored.value = true
}
let saveTimer = null
watch([body, topic], () => {
  clearTimeout(saveTimer)
  saveTimer = setTimeout(() => saveDraft(body.value, topic.value), 400)
})
watch(keepDraft, (on) => setDraftEnabled(on))
function discardDraft() {
  clearTimeout(saveTimer)
  clearDraft()
  body.value = ''
  topic.value = ''
  restored.value = false
}

onMounted(async () => {
  // 危機字詞只做溫和提示：不擋送出、不通知任何人
  // 例外詞（例如「跳樓價」）先拿掉再比對，避免日常用語跳出提示
  const [w, ex, mine] = await Promise.all([
    supabase.from('hole_crisis_words').select('word'),
    supabase.from('hole_crisis_exceptions').select('word'),
    supabase.rpc('hole_my_threads'),
  ])
  words.value = (w.data ?? []).map((x) => x.word)
  exceptions.value = (ex.data ?? []).map((x) => x.word)
  // 按「我現在需要馬上有人幫忙」時，通知管理員要掛在一段進行中的對話上；用最近那則訊息的。
  // 還沒有人接下的話，掛在最近一則還沒結束的訊息上
  const threads = mine.data ?? []
  const conv = threads.flatMap((x) => x.conversations).find((c) => c.active)
  activeAid.value = conv?.assignment_id ?? null
  activeTid.value = threads.find((x) => !x.closed_at)?.id ?? null
  pastListeners.value = threads.flatMap((th) => th.conversations
    .map((c, i) => ({ ...c, n: i + 1 }))
    .filter((c) => c.can_request_again)
    .map((c) => ({ aid: c.assignment_id, n: c.n, body: th.body })))
})
const preferOptions = computed(() => pastListeners.value.map((x) => ({
  aid: x.aid,
  label: t('「{text}」的傾聽者 {n}', { text: x.body.length > 10 ? x.body.slice(0, 10) + '…' : x.body, n: x.n }),
})))
const mentionsCrisis = computed(() => matchCrisis(body.value, words.value, exceptions.value))

async function submit() {
  error.value = ''
  if (!body.value.trim()) return (error.value = '先寫下想說的話')
  if (!topic.value) return (error.value = '選一個話題')
  busy.value = true
  const { data, error: e } = await supabase.rpc('hole_post', {
    p_topic: topic.value,
    p_body: body.value.trim(),
    p_avoid_classmates: avoidClassmates.value,
    p_prefer: prefer.value ? Number(prefer.value) : null,
  })
  busy.value = false
  if (e) return (error.value = errorText(e))
  clearTimeout(saveTimer)
  clearDraft()
  const query = {}
  if (data.show_help) query.help = 1
  if (data.preferred != null) query.prefer = data.preferred ? 1 : 0
  router.push({ path: `/mine/${data.thread_id}`, query })
}
</script>

<template>
  <header class="home-head">
    <div class="brand">
      <img src="/logo.svg" alt="" />
      <h1>{{ t('FDFZ 樹洞') }}</h1>
      <QuickExit />
    </div>
    <p class="lede">{{ t('想說什麼都可以。會私下派給兩位受過培訓的同學聽，你們看不到彼此是誰，內容也不公開。') }}</p>
  </header>
  <div class="page">
    <form class="card" @submit.prevent="submit">
      <label class="field">
        <span>{{ t('想說的話') }}</span>
        <textarea v-model="body" class="msg" maxlength="2000" :placeholder="t('不用整理好，想到什麼就寫什麼。')" />
      </label>
      <p v-if="restored" class="muted tiny draft-row">
        {{ t('已載入上次沒送出的草稿。') }}
        <button type="button" class="linkbtn" @click="discardDraft">{{ t('清除草稿') }}</button>
      </p>
      <IdentityNote :text="body" />
      <div v-if="mentionsCrisis" class="note warn" role="status">
        <Icon name="warn" :size="20" />
        <span>
          <b>{{ t('你現在還好嗎？如果有傷害自己的念頭，請先找能馬上陪你的人。') }}</b>
          {{ HELP.counselor }}；{{ t(HELP.hotlineName) }} {{ HELP.hotline }}。{{ t('訊息照樣可以送出。') }}<br />
          <span class="tiny">{{ t('這是系統依字詞自動顯示的提示，不代表我們判斷你有危險。') }}</span>
        </span>
      </div>
      <div>
        <span id="lbl-topic" class="field-t">{{ t('話題') }}</span>
        <div class="chips" role="group" aria-labelledby="lbl-topic">
          <button v-for="x in TOPICS" :key="x.key" type="button" class="chip" :aria-pressed="topic === x.key" @click="topic = x.key">{{ t(x.label) }}</button>
        </div>
        <span class="field-s">{{ t('傾聽者按「接下」之前只看得到話題。') }}</span>
      </div>
      <label class="check">
        <input v-model="avoidClassmates" type="checkbox" />
        <span>{{ t('不要派給同班的同學') }}<small>{{ t('學號前六位和你相同的人不會收到。') }}</small></span>
      </label>
      <label v-if="preferOptions.length" class="field">
        <span>{{ t('想再找之前聊過的傾聽者？（選填）') }}</span>
        <select v-model="prefer">
          <option value="">{{ t('不指定，隨機派') }}</option>
          <option v-for="x in preferOptions" :key="x.aid" :value="String(x.aid)">{{ x.label }}</option>
        </select>
        <small>{{ t('會先派給那位，對方仍然看不到你是誰，也可以婉拒；婉拒或暫停接單時改成隨機派。') }}</small>
      </label>
      <label class="check">
        <input v-model="keepDraft" type="checkbox" />
        <span>{{ t('在這台裝置存草稿') }}<small>{{ t('沒送出的內容只存在這台裝置的瀏覽器，24 小時後自動清掉。共用電腦請關掉。') }}</small></span>
      </label>
      <p v-if="error" class="error">{{ t(error) }}</p>
      <button class="btn block" :disabled="busy"><Icon name="send" />{{ busy ? t('送出中…') : t('送出') }}</button>
      <p class="muted tiny center">{{ t('傾聽者也是同學，要上課和休息，回覆可能要等幾小時。') }}</p>
    </form>

    <div class="card">
      <h3>{{ t('送出之後會怎樣') }}</h3>
      <ol class="how">
        <li><span class="av">1</span><span>{{ t('系統隨機選出兩位傾聽者，不會選到你換掉過的人。') }}</span></li>
        <li><span class="av">2</span><span>{{ t('他們先看到話題，按「接下」才讀到全文。30 分鐘內沒人接，會自動改找別人。') }}</span></li>
        <li><span class="av">3</span><span>{{ t('每位都和你一對一聊，彼此看不到對方的回覆。') }}</span></li>
        <li><span class="av">4</span><span>{{ t('聊得不合可以隨時換人，不用說理由。') }}</span></li>
      </ol>
    </div>

    <p class="note">
      <Icon name="lock" :size="20" />
      <span>{{ t('遇到安全疑慮時，管理員可以查到你是誰。每次查詢都會留紀錄，所有管理員都看得到。') }}<router-link to="/rules">{{ t('讀完整守則') }}</router-link></span>
    </p>
    <HelpCard :aid="activeAid" :tid="activeTid" />
  </div>
  <TabBar />
</template>

<style scoped>
.msg { min-height: 190px; line-height: 1.85; }
.how { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 12px; }
.how li { display: flex; gap: 12px; align-items: flex-start; }
.draft-row { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; margin: -4px 0 0; }
.linkbtn { background: none; border: 0; padding: 0; color: var(--forest); cursor: pointer; font-size: inherit; text-decoration: underline; }
</style>

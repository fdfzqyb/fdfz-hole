<script setup>
import { t } from '../i18n'
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { TOPICS } from '../constants'
import { HELP } from '../help'
import { errorText } from '../format'
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
const activeAid = ref(null)
const activeTid = ref(null)

onMounted(async () => {
  // 危機字詞只做溫和提示：不擋送出、不通知任何人
  const [w, mine] = await Promise.all([
    supabase.from('hole_crisis_words').select('word'),
    supabase.rpc('hole_my_threads'),
  ])
  words.value = (w.data ?? []).map((x) => x.word)
  // 按「我現在需要馬上有人幫忙」時，通知管理員要掛在一段進行中的對話上；用最近那則訊息的。
  // 還沒有人接下的話，掛在最近一則還沒結束的訊息上
  const threads = mine.data ?? []
  const conv = threads.flatMap((x) => x.conversations).find((c) => c.active)
  activeAid.value = conv?.assignment_id ?? null
  activeTid.value = threads.find((x) => !x.closed_at)?.id ?? null
})
const mentionsCrisis = computed(() => words.value.some((w) => body.value.includes(w)))

async function submit() {
  error.value = ''
  if (!body.value.trim()) return (error.value = '先寫下想說的話')
  if (!topic.value) return (error.value = '選一個話題')
  busy.value = true
  const { data, error: e } = await supabase.rpc('hole_post', {
    p_topic: topic.value,
    p_body: body.value.trim(),
    p_avoid_classmates: avoidClassmates.value,
  })
  busy.value = false
  if (e) return (error.value = errorText(e))
  router.push({ path: `/mine/${data.thread_id}`, query: data.show_help ? { help: 1 } : {} })
}
</script>

<template>
  <header class="home-head">
    <div class="brand">
      <img src="/logo.svg" alt="" />
      <h1>{{ t('FDFZ 樹洞') }}</h1>
    </div>
    <p class="lede">{{ t('想說什麼都可以。會私下派給兩位受過培訓的同學聽，你們看不到彼此是誰，內容也不公開。') }}</p>
  </header>
  <div class="page">
    <form class="card" @submit.prevent="submit">
      <label class="field">
        <span>{{ t('想說的話') }}</span>
        <textarea v-model="body" class="msg" maxlength="2000" :placeholder="t('不用整理好，想到什麼就寫什麼。')" />
      </label>
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
</style>

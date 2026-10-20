<script setup>
import { t } from '../i18n'
import { useRouter } from 'vue-router'
import { HELP } from '../help'
import Icon from '../components/Icon.vue'
import TabBar from '../components/TabBar.vue'

const router = useRouter()
const SECTIONS = [
  {
    title: '匿名',
    points: [
      '發出者和傾聽者彼此看不到對方是誰，對話裡不會出現姓名、學號或任何帳號資訊。',
      '派給誰由系統在後台隨機決定，任何人都無法指定或預測。',
      '對話不公開，只有你和那位傾聽者看得到。',
    ],
  },
  {
    title: '管理員什麼時候看得到',
    points: [
      '管理員不能隨意翻看對話，只看得到被檢舉、被標記「需要協助」，或發出者自己求助的那一段。',
      '遇到安全疑慮時，管理員可以查到發出者或傾聽者是誰。每次查詢都必須填理由並留下紀錄，所有管理員都看得到這份紀錄。',
    ],
  },
  {
    title: '不可以',
    points: [
      '試圖查出對方是誰，或透露自己是誰、交換聯絡方式、約見面。',
      '截圖、轉述，或在現實中提起對話內容。',
      '騷擾、辱罵對方，或發和傾訴無關的內容。',
    ],
  },
  {
    title: '你可以',
    points: [
      '發出者隨時可以換傾聽者，不用說理由；也可以隨時結束對話。',
      '傾聽者可以婉拒、暫停接單，或退出對話。',
      '任何一方都可以檢舉。',
    ],
  },
]
</script>

<template>
  <header class="topbar">
    <button class="back" type="button" :aria-label="t('返回')" @click="router.back()"><Icon name="back" :size="24" /></button>
    <h1>{{ t('樹洞守則') }}</h1>
  </header>
  <div class="page">
    <div v-for="s in SECTIONS" :key="s.title" class="card">
      <h3>{{ t(s.title) }}</h3>
      <ul class="points"><li v-for="p in s.points" :key="p">{{ t(p) }}</li></ul>
    </div>
    <div class="card">
      <h3>{{ t('樹洞不是急救') }}</h3>
      <p>{{ t('傾聽者是同學，不是專業人員，回覆也可能要等幾小時。如果你現在有危險，請直接聯絡：') }}</p>
      <p class="note"><Icon name="phone" :size="20" /><span><b>{{ t(HELP.hotlineName) }}</b>{{ HELP.hotline }}</span></p>
      <p class="note"><Icon name="user" :size="20" /><span><b>{{ HELP.center }}</b>{{ HELP.place }}，{{ HELP.hours }}，{{ HELP.centerPhone }}</span></p>
    </div>
  </div>
  <TabBar />
</template>

<style scoped>
.points { margin: 0; padding-left: 20px; display: flex; flex-direction: column; gap: 6px; }
</style>

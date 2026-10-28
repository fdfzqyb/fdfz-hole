<script setup>
import { watch } from 'vue'
import { locale, t } from './i18n'
import { auth } from './auth'
import { unread } from './unread'

const reload = () => window.location.reload()

watch(locale, (value) => {
  document.documentElement.lang = value
}, { immediate: true })

// 有未讀訊息或等著接下的單時，分頁標題前面加上 (n)
watch(() => [locale.value, unread.mine + unread.listen + unread.offers], ([, n]) => {
  document.title = (n ? `(${n}) ` : '') + t('FDFZ 樹洞')
}, { immediate: true })
</script>

<template>
  <router-view v-if="auth.ready" />
  <div v-else class="boot">
    <img src="/logo.svg" alt="" class="boot-logo" />
    <p v-if="!auth.error" class="muted">{{ t('載入中…') }}</p>
    <template v-else>
      <p>{{ t(auth.error) }}</p>
      <button class="btn" @click="reload">{{ t('重新整理') }}</button>
    </template>
  </div>
</template>

<style scoped>
.boot {
  min-height: 100vh;
  display: grid;
  place-content: center;
  justify-items: center;
  gap: 12px;
  padding: 24px;
  text-align: center;
}
.boot-logo { width: 72px; height: 72px; }
</style>

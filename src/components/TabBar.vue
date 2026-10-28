<script setup>
import { t } from '../i18n'
import { watch } from 'vue'
import { useRoute } from 'vue-router'
import { isHoleAdmin } from '../auth'
import { unread, refreshUnread, watchUnread } from '../unread'
import Icon from './Icon.vue'

const route = useRoute()

// 我的對話：傾聽者傳來的未讀訊息；傾聽：等著接下的單加上發出者傳來的未讀訊息。每次換頁重新算，有新訊息也會更新
watchUnread()
watch(() => route.fullPath, refreshUnread, { immediate: true })

const on = (...prefixes) => prefixes.some((p) => (p === '/' ? route.path === '/' : route.path.startsWith(p)))
</script>

<template>
  <nav class="tabbar" :aria-label="t('樹洞')">
    <router-link to="/" :class="{ on: on('/') }"><Icon name="leaf" :size="24" />{{ t('說說話') }}</router-link>
    <router-link to="/mine" :class="{ on: on('/mine') }">
      <Icon name="chat" :size="24" />{{ t('我的對話') }}<span v-if="unread.mine" class="badge">{{ unread.mine }}</span>
    </router-link>
    <router-link to="/listen" :class="{ on: on('/listen', '/train') }">
      <Icon name="ear" :size="24" />{{ t('傾聽') }}<span v-if="unread.offers + unread.listen" class="badge">{{ unread.offers + unread.listen }}</span>
    </router-link>
    <router-link v-if="isHoleAdmin()" to="/admin" :class="{ on: on('/admin') }"><Icon name="shield" :size="24" />{{ t('管理') }}</router-link>
    <router-link to="/account" :class="{ on: on('/account', '/rules') }"><Icon name="user" :size="24" />{{ t('帳號') }}</router-link>
  </nav>
</template>

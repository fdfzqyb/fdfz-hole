<script setup>
import { t } from '../i18n'
import { ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '../supabase'
import { isHoleAdmin, listenerState } from '../auth'
import Icon from './Icon.vue'

const route = useRoute()
const offers = ref(0)

// 傾聽者有幾張單等著接下；每次換頁重新算
async function loadOffers() {
  if (listenerState() !== 'qualified') return (offers.value = 0)
  const { data } = await supabase.rpc('hole_my_assignments')
  offers.value = (data ?? []).filter((a) => a.status === 'pending').length
}
watch(() => route.fullPath, loadOffers, { immediate: true })

const on = (...prefixes) => prefixes.some((p) => (p === '/' ? route.path === '/' : route.path.startsWith(p)))
</script>

<template>
  <nav class="tabbar" :aria-label="t('樹洞')">
    <router-link to="/" :class="{ on: on('/') }"><Icon name="leaf" :size="24" />{{ t('說說話') }}</router-link>
    <router-link to="/mine" :class="{ on: on('/mine') }"><Icon name="chat" :size="24" />{{ t('我的對話') }}</router-link>
    <router-link to="/listen" :class="{ on: on('/listen', '/train') }">
      <Icon name="ear" :size="24" />{{ t('傾聽') }}<span v-if="offers" class="badge">{{ offers }}</span>
    </router-link>
    <router-link v-if="isHoleAdmin()" to="/admin" :class="{ on: on('/admin') }"><Icon name="shield" :size="24" />{{ t('管理') }}</router-link>
    <router-link to="/account" :class="{ on: on('/account', '/rules') }"><Icon name="user" :size="24" />{{ t('帳號') }}</router-link>
  </nav>
</template>

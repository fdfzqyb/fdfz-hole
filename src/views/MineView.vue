<script setup>
import { t } from '../i18n'
import { ref, computed, onMounted } from 'vue'
import { supabase } from '../supabase'
import { TOPIC_LABEL } from '../constants'
import { when, errorText } from '../format'
import { threadStatus } from '../threads'
import TabBar from '../components/TabBar.vue'

const threads = ref(null)
const error = ref('')

onMounted(async () => {
  const { data, error: e } = await supabase.rpc('hole_my_threads')
  if (e) return (error.value = errorText(e))
  threads.value = data
})

const open = computed(() => (threads.value ?? []).filter((x) => !x.closed_at))
const closed = computed(() => (threads.value ?? []).filter((x) => x.closed_at))
</script>

<template>
  <header class="topbar"><h1>{{ t('我的對話') }}</h1></header>
  <div class="page">
    <p v-if="error" class="error">{{ t(error) }}</p>
    <p v-else-if="!threads" class="muted center">{{ t('載入中…') }}</p>
    <template v-else>
      <div v-if="!threads.length" class="card center">
        <p class="muted">{{ t('你還沒發過訊息。') }}</p>
        <router-link to="/" class="btn">{{ t('說說話') }}</router-link>
      </div>

      <router-link v-for="th in open" :key="th.id" :to="`/mine/${th.id}`" class="card thread-card">
        <div class="row">
          <span class="muted small">{{ t(TOPIC_LABEL[th.topic]) }} · {{ when(th.created_at) }}</span>
          <span class="status" :class="threadStatus(th).cls">{{ t(threadStatus(th).label, threadStatus(th)) }}</span>
        </div>
        <h3>{{ th.body }}</h3>
      </router-link>

      <template v-if="closed.length">
        <h2 class="sec-t">{{ t('之前的對話') }}</h2>
        <router-link v-for="th in closed" :key="th.id" :to="`/mine/${th.id}`" class="card thread-card">
          <div class="row">
            <span class="muted small">{{ t(TOPIC_LABEL[th.topic]) }} · {{ when(th.created_at) }}</span>
            <span class="status st-done">{{ t('已結束') }}</span>
          </div>
          <h3>{{ th.body }}</h3>
        </router-link>
      </template>
    </template>
  </div>
  <TabBar />
</template>

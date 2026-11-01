<script setup>
// 內容看起來含有學號、手機、微信號等，就提醒一下。只提示、不擋送出。
import { computed } from 'vue'
import { t } from '../i18n'
import { identityHints } from '../identity'
import Icon from './Icon.vue'

const props = defineProps({ text: { type: String, default: '' } })
const hints = computed(() => identityHints(props.text))
</script>

<template>
  <div v-if="hints.length" class="note" role="status">
    <Icon name="lock" :size="20" />
    <span>
      <b>{{ t('這段內容可能讓人認出你') }}</b>
      {{ t('看起來有{what}。對方看不到你是誰，但這些資訊會讓匿名失效，確定要寫的話照樣可以送出。', { what: hints.map((h) => t(h)).join('、') }) }}
    </span>
  </div>
</template>

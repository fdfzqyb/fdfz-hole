<script setup>
// 用瀏覽器內建的 <dialog>：會擋住背景、按 Esc 可關閉。open 由外層用 v-model:open 控制
import { ref, watch, onMounted } from 'vue'

const props = defineProps({ open: Boolean, title: String })
const emit = defineEmits(['update:open'])
const el = ref(null)

function sync() {
  if (!el.value) return
  if (props.open && !el.value.open) el.value.showModal()
  if (!props.open && el.value.open) el.value.close()
}
watch(() => props.open, sync)
onMounted(sync)
</script>

<template>
  <dialog ref="el" :aria-label="title" @close="emit('update:open', false)">
    <form @submit.prevent>
      <h2 v-if="title">{{ title }}</h2>
      <slot />
    </form>
  </dialog>
</template>

<script setup>
// 自繪圖標，原檔在 src/icons/，畫法和權益牆一樣。線條跟著文字顏色（currentColor），
// 填充色用 --icon-accent，放在深色按鈕上時由外層 CSS 改這個變數
const svgs = import.meta.glob('../icons/*.svg', { query: '?raw', import: 'default', eager: true })

const props = defineProps({
  name: { type: String, required: true },
  size: { type: Number, default: 22 },
})
const svg = svgs[`../icons/${props.name}.svg`]
</script>

<template>
  <span class="ic" :style="{ width: size + 'px', height: size + 'px' }" aria-hidden="true" v-html="svg" />
</template>

<style scoped>
.ic { display: inline-block; flex: none; line-height: 0; vertical-align: -0.2em; }
.ic :deep(svg) { width: 100%; height: 100%; }
</style>

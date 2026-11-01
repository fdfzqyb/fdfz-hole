<script setup>
// 快速離開：旁邊有人時一鍵跳到中性頁面，並清掉這台裝置上的草稿。
// 用 location.replace，按「上一頁」不會回到樹洞這一頁。
import { t } from '../i18n'
import { clearDraft } from '../draft'
import { EXIT_URL } from '../constants'

function leave() {
  clearDraft()
  window.location.replace(EXIT_URL)
}
</script>

<template>
  <button type="button" class="quick-exit" :title="t('快速離開：跳到別的網頁，並清掉草稿')" @click="leave">{{ t('快速離開') }}</button>
</template>

<style scoped>
.quick-exit {
  margin-left: auto; flex: none;
  padding: 6px 12px; min-height: 32px;
  border: 1px solid var(--border); border-radius: 999px;
  background: var(--white); color: var(--muted, #5b6b62);
  font: inherit; font-size: 13px; cursor: pointer;
}
.quick-exit:hover { color: var(--ink); border-color: var(--ink); }
</style>

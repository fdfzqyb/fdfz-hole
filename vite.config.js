import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { readFileSync } from 'node:fs'
import { execSync } from 'node:child_process'

// 版本號手動改 package.json（見 CHANGELOG.md）；commit 編號在建置時自動帶入
const { version } = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8'))

function commit() {
  // Cloudflare Workers Builds 會提供 WORKERS_CI_COMMIT_SHA，本機則讀 git
  const sha = process.env.WORKERS_CI_COMMIT_SHA
  if (sha) return sha.slice(0, 7)
  try {
    return execSync('git rev-parse --short HEAD', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim()
  } catch {
    return ''
  }
}

export default defineConfig({
  plugins: [vue()],
  define: {
    __APP_VERSION__: JSON.stringify(version),
    __APP_COMMIT__: JSON.stringify(commit()),
  },
})

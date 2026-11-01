// 發訊息頁的草稿：只存在這台裝置的瀏覽器，24 小時後自動清掉；送出或快速離開時清除。
// 使用者可以關掉「存草稿」，關掉後這台裝置不再存任何內容。
const KEY = 'fdfz-hole-draft'
const OFF_KEY = 'fdfz-hole-draft-off'
const TTL = 24 * 60 * 60 * 1000

export function draftEnabled() {
  try {
    return localStorage.getItem(OFF_KEY) !== '1'
  } catch {
    return false
  }
}

export function setDraftEnabled(on) {
  try {
    if (on) localStorage.removeItem(OFF_KEY)
    else {
      localStorage.setItem(OFF_KEY, '1')
      localStorage.removeItem(KEY)
    }
  } catch {
    // 瀏覽器不給存就算了，草稿只是方便用
  }
}

export function loadDraft() {
  try {
    const d = JSON.parse(localStorage.getItem(KEY) ?? 'null')
    if (!d || Date.now() - d.savedAt > TTL) {
      localStorage.removeItem(KEY)
      return null
    }
    return d
  } catch {
    return null
  }
}

export function saveDraft(body, topic) {
  if (!draftEnabled()) return
  try {
    if (!body.trim()) localStorage.removeItem(KEY)
    else localStorage.setItem(KEY, JSON.stringify({ body, topic, savedAt: Date.now() }))
  } catch {
    // 同上
  }
}

export function clearDraft() {
  try {
    localStorage.removeItem(KEY)
  } catch {
    // 同上
  }
}

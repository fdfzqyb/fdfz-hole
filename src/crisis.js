// 危機字詞比對：先把例外詞（例如「跳樓價」「想死記」）換成分隔符，剩下的字再找關鍵詞。
// 和資料庫 hole_mentions_crisis 同一套邏輯，只做溫和提示，不擋送出。
export function mentionsCrisis(text, words, exceptions = []) {
  let s = text ?? ''
  const sorted = [...exceptions].sort((a, b) => b.length - a.length || (a < b ? -1 : 1))
  for (const e of sorted) s = s.split(e).join('\u0001')
  return words.some((w) => s.includes(w))
}

// 送出前提醒「這段話可能讓人認出你」：只比對字面格式，只提示、不擋送出。
// 學號是 8 位數字；手機是 1 開頭的 11 位數字；微信、QQ 後面接帳號；宿舍樓號和房號；Email。
const RULES = [
  { label: '學號', re: /(?<!\d)\d{8}(?!\d)/ },
  { label: '手機號碼', re: /(?<!\d)1[3-9]\d{9}(?!\d)/ },
  { label: 'Email', re: /[\w.+-]+@[\w-]+\.[\w.]+/ },
  { label: '微信或 QQ', re: /(微信|微訊|wechat|weixin|wx|vx|v信|qq|扣扣)\s*(號|号|是|：|:)?\s*[A-Za-z0-9_-]{5,}/i },
  { label: '宿舍房號', re: /\d+\s*(號樓|号楼|棟|栋|齋|斋|舍)\s*\d{2,4}|\d{3,4}\s*(寢室|寝室|宿舍)/ },
]

export function identityHints(text) {
  const s = text ?? ''
  // 前後有其他數字的長串（例如訂單號）不算學號或手機
  return RULES.filter((r) => r.re.test(s)).map((r) => r.label)
}

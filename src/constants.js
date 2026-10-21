// 話題標籤：鍵名和資料庫 hole_topic 一致，不能改；顯示文字可以改
export const TOPICS = [
  { key: 'study', label: '學業' },
  { key: 'family', label: '家庭' },
  { key: 'social', label: '人際' },
  { key: 'emotion', label: '情緒' },
  { key: 'other', label: '其他' },
]
export const TOPIC_LABEL = Object.fromEntries(TOPICS.map((x) => [x.key, x.label]))

// 傾聽者退出原因：鍵名和資料庫 hole_leave_reason 一致
export const LEAVE_REASONS = [
  { key: 'over_capacity', label: '超出我的能力' },
  { key: 'not_ok', label: '我現在狀態不好' },
  { key: 'crisis', label: '需要危機協助', hint: '立刻通知管理員，並把這段對話交給管理員查看。' },
]
export const LEAVE_LABEL = Object.fromEntries(LEAVE_REASONS.map((x) => [x.key, x.label]))

// 傾聽者承諾。改了條文要同時把 hole_config.pledge_version 改成新版本號，所有傾聽者會被要求重新勾選
export const PLEDGE = [
  '我不會試圖查出對方是誰，也不會透露自己是誰。',
  '我不會截圖、轉述，或在現實中提起任何對話內容。',
  '看到自傷、傷人或受侵害的信號時，我會按「需要協助」，不自己處理。',
  '我不評判、不說教，對方想換人時尊重他的決定。',
  '我狀態不好時會先暫停接單，或退出對話。',
]

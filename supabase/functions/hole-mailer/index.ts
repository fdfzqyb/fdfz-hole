// FDFZ 树洞 寄信：每 5 分钟由 pg_cron 叫一次，把 hole_email_outbox 里待寄的通知用 Resend 寄出。
// 信里只说「有事要处理」和网址，绝不放消息内容或话题。
// 需要的 Secrets：RESEND_API_KEY（必填）、MAIL_FROM（选填，寄件人）。
// SUPABASE_URL、SUPABASE_SERVICE_ROLE_KEY 由 Supabase 自动提供。

const SITE = 'https://hole.fdfz.click'

const MAILS: Record<string, { subject: string; path: string; lines: string[] }> = {
  new_offer: {
    subject: '树洞：有一则新消息派给你',
    path: '/listen',
    lines: [
      '有同学在树洞写下了一则消息，系统派给了你。',
      '请在 30 分钟内打开树洞选择「接下」或「这次不行」；没处理的话会自动转给别人，不算超时。',
      '最近不方便接单，可以在「倾听」页切换到暂停。',
    ],
  },
  reply_reminder: {
    subject: '树洞：有人在等你回复',
    path: '/listen',
    lines: [
      '你手上有一段对话，对方已经等了 12 小时。',
      '方便的话请打开树洞回复；等满 24 小时，对方可以选择多找一位倾听者，这时会记你一次超时。',
      '如果现在状态不好，也可以退出这段对话，系统会转给别人。',
    ],
  },
  admin_alert: {
    subject: '树洞：有求助或举报需要处理',
    path: '/admin',
    lines: [
      '树洞有一则求助或举报需要管理员处理。',
      '请尽快登录树洞，到「管理」页查看。',
    ],
  },
}

const env = (name: string) => Deno.env.get(name) ?? ''
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))
const escape = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

async function rpc(name: string, body: unknown) {
  const key = env('SUPABASE_SERVICE_ROLE_KEY')
  const res = await fetch(`${env('SUPABASE_URL')}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  if (!res.ok) throw new Error(`${name}: ${res.status} ${await res.text()}`)
  return res.status === 204 ? null : res.json()
}

function render(kind: string) {
  const m = MAILS[kind]
  const url = SITE + m.path
  const foot = '这封信由 FDFZ 树洞自动寄出，不用回复。'
  const text = [...m.lines, '', url, '', foot].join('\n')
  const html = `<div style="font-family:sans-serif;font-size:15px;line-height:1.7;color:#1f2a24;max-width:520px">
${m.lines.map((l) => `<p>${escape(l)}</p>`).join('\n')}
<p><a href="${url}" style="display:inline-block;background:#2f5d4a;color:#fff;padding:10px 20px;border-radius:999px;text-decoration:none">打开树洞</a></p>
<p style="color:#6b7670;font-size:13px">${escape(foot)}</p>
</div>`
  return { subject: m.subject, text, html }
}

async function send(to: string, kind: string) {
  const { subject, text, html } = render(kind)
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${env('RESEND_API_KEY')}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: env('MAIL_FROM') || 'FDFZ 树洞 <hole@fdfz.click>', to: [to], subject, text, html }),
  })
  if (!res.ok) throw Object.assign(new Error(`resend: ${res.status} ${await res.text()}`), { status: res.status })
}

Deno.serve(async () => {
  if (!env('RESEND_API_KEY')) return new Response('RESEND_API_KEY not set', { status: 500 })
  const rows: { ids: number[]; kind: string; email: string }[] = await rpc('hole_outbox_claim', { max_rows: 100 })
  let sent = 0
  let failed = 0
  for (const row of rows) {
    if (!MAILS[row.kind]) continue
    try {
      await send(row.email, row.kind)
      sent++
    } catch (e) {
      // 网络问题、Resend 忙线（429、5xx）就放回去，下一轮再试；地址无效之类的 4xx 重试也没用，直接放弃
      console.error(e)
      failed++
      const status = (e as { status?: number }).status
      if (!status || status === 429 || status >= 500) await rpc('hole_outbox_release', { p_ids: row.ids }).catch(console.error)
    }
    // Resend 免费方案每秒最多 2 封
    await sleep(600)
  }
  return Response.json({ sent, failed })
})

# FDFZ 樹洞

同學匿名寫下想說的話，系統私下派給受過培訓的同學傾聽與回覆，內容不公開。網址 hole.fdfz.click。

- 前端：Vite + Vue，部署在 Cloudflare Workers（和權益牆一樣）
- 後端：和權益牆共用同一個 Supabase 專案與帳號。資料庫結構在專案資料夾的 `backend/hole/hole_schema.sql`，接在權益牆的 `supabase/schema.sql` 之後執行
- 註冊、校園卡驗證、改密碼都在權益牆做，樹洞只負責登入

## 上線前要填的

1. **`.env.production`**：把權益牆的 `.env.production` 整份複製過來（兩站用同一個 Supabase，網址和 publishable key 相同）。
2. **`src/help.js`**：心理諮詢中心名稱、地點、開放時間、電話，以及熱線號碼。方括號是佔位字，發訊息頁、求助視窗、守則都從這裡讀。
3. Supabase → Authentication → URL Configuration → Redirect URLs 加上 `https://hole.fdfz.click/**`（Site URL 不要改）。

## 在自己電腦上執行

需要 [Node.js](https://nodejs.org)（LTS 版）。

```bash
npm install
cp .env.example .env   # 填上 Supabase 的網址和 publishable key
npm run dev
```

## 部署到 Cloudflare

Cloudflare 控制台 → Workers & Pages → 建立 → 連接 GitHub，選這個 repository：

- Build command：`npm run build`
- Deploy command：`npx wrangler deploy`（預設值）
- Worker 名稱：`fdfz-hole`（要和 `wrangler.jsonc` 一致）

部署完成後到 Worker → Settings → Domains & Routes → Add → Custom domain，填 `hole.fdfz.click`。之後每次推到 `main` 都會自動重新部署。

## 頁面一覽

| 頁面 | 路徑 | 誰能看 |
| --- | --- | --- |
| 登入 | `/login` | 所有人 |
| 帳號未驗證／要改臨時密碼 | `/pending` | 登入後還不能使用的人 |
| 說說話（發訊息） | `/` | 已驗證同學 |
| 我的對話、單則訊息（換人、多找一位、結束、檢舉） | `/mine`、`/mine/:id` | 發出者本人 |
| 傾聽工作台、傾聽者對話 | `/listen`、`/listen/:aid` | 傾聽者 |
| 培訓、測驗、承諾 | `/train` | 已驗證同學 |
| 守則 | `/rules` | 已驗證同學 |
| 帳號、語言 | `/account` | 已驗證同學 |
| 樹洞管理（求助與檢舉、查身份、傾聽者、操作紀錄、管理員） | `/admin` | 樹洞管理員 |

## 文字與語言

和權益牆一樣有簡體（預設）和繁體兩種介面，在帳號頁切換。程式裡的文字一律寫繁體，包在 `t('…')` 裡，再到 `src/locales/zh-Hans.js` 加一行「繁體: 簡體」對照。同學寫的內容和資料庫裡的測驗題照原文顯示。

改了 `src/constants.js` 的傾聽者承諾條文，要同時把資料庫 `hole_config.pledge_version` 改成新版本號，所有傾聽者會被要求重新勾選。

## 寄信功能

有新訊息派給傾聽者、傾聽者 12 小時沒回、有求助或檢舉時，資料庫會在 `hole_email_outbox` 記一筆。`supabase/functions/hole-mailer` 這個 Edge Function 每 5 分鐘由 pg_cron 叫一次，把這些記錄用 [Resend](https://resend.com) 寄出。

- 信裡只說「有事要處理」和樹洞網址，**不放訊息內容和話題**。
- 同一個人同一類通知在 5 分鐘內有好幾筆，只寄一封。
- 超過一天還沒寄的記錄直接略過（例如寄信功能上線前累積的）。
- 寄失敗時：網路問題或 Resend 忙線會下一輪重試；地址無效之類的錯誤不重試。

設定步驟：

1. Resend 註冊，Domains → Add Domain 填 `fdfz.click`，照它給的 DNS 記錄加到 Cloudflare（或用它的 Cloudflare 自動設定），按 Verify。
2. Resend → API Keys → Create，權限選 Sending access。
3. Supabase → Edge Functions → Secrets 新增 `RESEND_API_KEY`。寄件人預設是 `FDFZ 树洞 <hole@fdfz.click>`，要改就再加 `MAIL_FROM`。
4. Supabase → Edge Functions → Deploy a new function → Via Editor，名稱 `hole-mailer`，貼上 `supabase/functions/hole-mailer/index.ts` 部署；到函數設定關掉 Verify JWT（pg_cron 叫它時沒有登入資訊；任何人叫它也只是提早寄出該寄的信）。
5. Supabase → Database → Extensions 開啟 `pg_net`，再到 SQL Editor 執行 `supabase/hole_mailer.sql`。

改了 `index.ts` 要回到 Supabase 的函數頁重新貼上部署，Cloudflare 不會幫你部署它。

# 德州撲克多人即時虛擬籌碼房間 — Phase 1

本專案完全獨立於舊版離線記帳 App V2.1。

## 已實作
- 建立房間，設定房間名稱、盲注、起始籌碼、2–12 人座位上限
- 隨機邀請碼與網址分享
- Supabase 匿名登入，手機身分持久保存（同一瀏覽器資料）
- 玩家提交加入申請；房主核准／拒絕；核准時自動分配空位
- 參與者名單每 2.5 秒輪詢同步，切回頁面立即刷新
- 房主預先指定代理房主（**僅記錄指定，不含自動接管**）

## 尚未實作
- 下注、底池、發牌階段、勝負結算、補碼、離桌回桌、Button 移動、代理接管
- 即時推播 WebSocket（目前是近即時輪詢）
- 跨裝置身分移轉、密碼登入、房間封存、進階風控

## iPhone 部署步驟
1. 在 [Supabase](https://supabase.com/dashboard) 建立新 Project。
2. 進入 Authentication → Providers，啟用 Anonymous Sign-ins（匿名登入）。
3. 進入 SQL Editor，新建 Query，貼上 `schema.sql` 全部內容，執行一次。**請用全新 Supabase 專案**，不要與其他 App 共用。
4. 在 Project Settings / Connect 或 API Keys 找到 Project URL 和 **Publishable key**（或 legacy `anon` key）。編輯 `config.js` 內的兩個欄位。**不可放入 secret / service_role key。**
5. GitHub 建立**全新** public repository（例如 `poker-room-live`），上傳 `index.html`、`styles.css`、`app.js`、`config.js`、`README.md`。`schema.sql` 可以一起上傳，因為不含任何密鑰。
6. Repository Settings → Pages → Deploy from a branch → `main` / `(root)` → Save。等待部署，打開 GitHub Pages 網址。
7. 房主建立房間並分享連結；其他手機開啟連結、輸入暱稱申請；房主核准後，各手機等待 2.5 秒內更新。

## 重要安全說明
- Supabase Publishable / anon key 是設計給前端公開使用的，權限保護依靠後端 RPC 與資料庫授權。請勿使用高權限金鑰。
- 此版本透過匿名登入辨識裝置。Safari 無痕模式、清除網站資料、不同瀏覽器、主畫面 PWA 與 Safari 的資料隔離可能導致身分不同；原裝置身分無法自動恢復。正式版需強化帳號恢復。
- 房間邀請碼不是房主權限。只有房主的匿名登入身分可核准或指定代理。
- 房間名稱及玩家暱稱為使用者輸入；前端做 HTML 跳脫，資料庫做長度檢查。
- **此版是連線功能測試版，不可當作正式牌局下注或籌碼結算工具。**
- 第一次打開需網路載入 Supabase SDK，所有多人功能都需要網路。

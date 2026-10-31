# Art Museum Games — 開發脈絡

《高美館失落的藝術能量》闖關活動網站。玩家用手機選組別、填名字，依組別路線走完三個樓層，每層作答後由關主確認，最後集合領取小組任務。

## 架構
- **不自己架設機器**，只靠 git 部署：靜態網站（GitHub Pages）＋ Supabase（資料庫、照片、關主登入）。
- 瀏覽器載入 HTML，用 `supabase-js` 直接呼叫 Supabase API，沒有自己的後端。

```
玩家手機 ──開網頁──▶ GitHub Pages（HTML / CSS / JS）
   │ supabase-js
   ▼
Supabase
  ├─ Postgres：題目、組別、玩家、答案、過關紀錄（RLS 把關）
  ├─ Storage：玩家上傳的照片（answers bucket）
  └─ Auth：只有關主要登入
```

| 檔案 | 用途 |
|---|---|
| `index.html` | 遊戲說明、規則、選組別填名字；關主登入 |
| `game.html` | 玩家闖關頁：作答、上傳照片、掃關主 QR code |
| `staff.html` | 關主工作台：顯示與列印各樓層 QR code |
| `js/app.js` | 共用：Supabase client、玩家身分、icon、提示訊息 |
| `js/scene.js` | 背景場景：楓樹葉叢與枝條隨風擺動、楓葉飄落、雲朵飄過 |
| `js/config.js` | Supabase URL 和 publishable key |
| `sql/` | 資料庫結構，要依序執行 |

## 活動內容
組別路線、樓層說明、題目都存在資料庫，**要調整時改資料表就好，不用動程式**。

| 組別 | 路線 |
|---|---|
| 第一、二組 | 二樓 → 三樓 → 四樓 |
| 第三、四組 | 三樓 → 四樓 → 二樓 |
| 第五、六組 | 四樓 → 二樓 → 三樓 |

| 資料表 | 內容 | 要改什麼時動它 |
|---|---|---|
| `teams` | 組別名稱、路線 `route`（樓層 id 陣列） | 分組、路線 |
| `stages` | 樓層名稱、標題、說明；`id` 就是樓層數字（2、3、4） | 樓層介紹 |
| `questions` | 題目、提示、題型 `kind`（`text` / `photo`）、是否必填 `required` | 題目 |

遊戲說明、規則寫在 `index.html`，最後的恭喜文字寫在 `game.html`，集合時間 11:00 也寫在這兩個檔案裡。

## 遊戲流程
1. 玩家選組別、填名字（1～20 字），`join_game()` 發一組隨機玩家編號，存在這支手機的 localStorage。
2. `game.html` 只展開路線上的下一個樓層，其他樓層顯示「尚未開放」或「已過關」。
3. 文字答案打字後自動儲存；照片縮到最長邊 1600px、轉成 JPEG 後上傳。
4. 玩家掃關主的 QR code，`claim_stage_as_player()` 檢查**是路線上的下一層**而且**必填題都答完**才算過關。
5. 三層都過關後，顯示恭喜畫面，請玩家找組員到三樓中間找關主領取小組任務。

玩家的紀錄綁在手機上：按「離開」、清除瀏覽器資料或換手機後就找不回來，只能重新加入。

## 答案和照片在哪裡看
網站上沒有查看回覆的頁面，要到 Supabase 後台看：
- **答案**：`player_answers` 資料表。`player_id` 對照 `players` 看是誰，`question_id` 對照 `questions` 看是哪一題。
- **照片**：Storage → `answers` bucket，每位玩家一個資料夾（資料夾名稱是玩家編號），檔名開頭是題號。
- bucket 是私有的，玩家不能讀取任何照片。手機上看到的是存在 localStorage 的小縮圖，方便關主確認。

## Supabase 專案
- 專案名稱：**Art Museum Games**
- 方案：Free（最多 2 個活躍專案；**閒置一週會自動暫停**；沒有自動備份）。活動前一兩天要先登入後台確認專案在運作。
- 區域：東北亞（Tokyo 或 Seoul，建立時選定，之後不能更改）
- URL：`https://<project-ref>.supabase.co`（在專案首頁或右上角 Connect 取得）
- 前端只能使用 **anon / publishable key**；`service_role` / `secret` key **絕對不能**放進前端或 commit 到 repo。

### 建立資料庫
在 SQL Editor 依序執行，每個檔案只執行一次（重複執行會因為資料表已存在而報錯）：
1. `sql/001_stage_game.sql`：關卡、關主名單、QR 密碼
2. `sql/002_nickname_players.sql`：玩家、過關紀錄
3. `sql/003_floor_game.sql`：組別、樓層、題目、答案、照片 bucket

`001` 裡的 `progress` 表和 `claim_stage()` 是給登入玩家用的，現在的前端沒有呼叫。

### 設定關主
關主用 Email + 密碼登入。先在 Authentication → Users 建立帳號，再把帳號加進 `staff` 表：

```sql
insert into public.staff (user_id)
select id from auth.users where email = 'staff@example.com';
```

## 權限（RLS）
因為瀏覽器直接連資料庫，權限必須寫在資料庫裡。**每張 public 表都要開 RLS**，開啟後預設全部擋下，要寫 policy 才會放行。

| 資料 | 誰能讀 | 誰能寫 |
|---|---|---|
| `teams`、`stages`、`questions` | 所有人 | 只有後台 |
| `stage_codes`（QR 密碼） | 關主 | 只有後台 |
| `players`、`player_progress`、`player_answers` | 只能透過函式 | 只能透過函式 |
| `answers` bucket | 只有後台 | 資料夾名稱必須是存在的玩家編號 |

- 玩家沒有登入，所以不用 `auth.uid()` 辨識，而是透過 `security definer` 函式存取：`join_game` 發玩家編號，`get_player`、`save_answer`、`claim_stage_as_player` 帶編號查詢或寫入。玩家編號就等於通行證。
- 讀取被擋時**不會報錯，只會回傳 `[]`**；寫入被擋時會報 `violates row-level security policy`。
- 前端不能信任的規則（例如樓層順序、必填題），要寫在函式裡，不能只寫在前端。

## 部署
- 網站放在 GitHub Pages（Settings → Pages），`git push` 後自動更新。
- **改了 CSS / JS 要更新 HTML 裡的 `?v=` 版本號**，不然瀏覽器會用快取的舊檔。
- **QR code 要在正式網址上開關主頁再列印**：內容是依當下網址產生的，在 localhost 列印會變成 localhost 連結。
- 本機預覽：`.claude/launch.json` 的 `site` 設定（port 5173）。

## 踩過的坑
- `Failed to fetch`：請求沒有送到 Supabase，通常是 URL 還是佔位文字，或網路/Supabase 事故。不是帳密規則的問題。用 F12 → Network 確認。
- `Could not find the table 'public.xxx' in the schema cache`：表不存在，或 API 快取沒更新（`notify pgrst, 'reload schema';`）。
- `relation "xxx" already exists`：這個 SQL 檔已經執行過了。先查資料表確認內容，不用再跑一次。
- 直接用 `file://` 打開 HTML 可以運作，但建議走 `http://localhost`；相機掃描也需要 localhost 或 HTTPS。
- Supabase 專案根網址 `/` 會回 `requested path is invalid`，這是正常的，它只是 API 不是網站。
- 建專案時 Region 不要選籠統的「Asia-Pacific」，要指定具體區域。
- 瀏覽器自動翻譯會把 Supabase 後台和錯誤訊息翻掉，建議關閉。

# 股市助手（Stock Helper）— 產品／技術說明（給 AI 優化用）

> 文件目的：讓 AI／工程師快速理解產品定位、功能、架構、限制與可優化方向。  
> 當前主版本：**1.0.4+5**（Android Flutter 為主；另有次要 Streamlit Web）。  
> 語言／市場：繁體中文（台灣），追蹤**台股**為主。  
> 最後整理：2026-09-14（台北）

---

## 1. 產品一句話

**本機優先的台股小助手**：觀察清單＋報價、資金配置建議、持股成本／損益、賣出與已實現收益，並支援券商截圖 OCR 匯入持股；底部有 AdMob 橫幅廣告。

## 2. 目標使用者與場景

- 個人投資者，想在手機快速看自選股與持倉損益。
- 不想先註冊帳號、資料預設留在裝置本機。
- 從券商 App 截圖持股表，希望少打代號／股數／均價。

**非目標（目前）**：券商下單、真實交易、多裝置雲端同步帳本、投顧建議、美股為主產品。

## 3. 平台與發行現況

| 項目 | 狀態 |
|------|------|
| 主產品 | Flutter Android（package `com.wick.stock_helper`） |
| 顯示名稱 | 股市助手 |
| 版本 | `1.0.4+5`（versionName 1.0.4 / versionCode 5） |
| 次要 | Streamlit Web（本機測試用，非主交付） |
| iOS | 暫停 |
| Play 內部測試 | 已上 1.0.4；連結 `https://play.google.com/apps/internaltest/4701345674234769347` |
| Play 封閉測試 | Alpha／內測 1.0.4 送審中（地區 TW／HK／SG）；`https://play.google.com/apps/testing/com.wick.stock_helper` |
| 正式版 | 尚未（新帳號需封閉測試 ≥12 人×14 天等條件） |
| 分發副本 | 桌面 `股票助手\`、Drive `股票助手/Android\`（apk／aab） |

**隱私政策（公開）**：Google 文件（Play 已綁定）。

## 4. 功能地圖（使用者視角）

App 底部四個分頁：

### 4.1 觀察清單（Watchlist）
- 新增／管理台股代號。
- 顯示中文名稱（名稱服務／對照）。
- 報價：收盤時用前收／收盤價；開市可即時價，畫面上約每 10 秒刷新。

### 4.2 持倉／成本損益（Holdings）
- 手動輸入：代號、名稱、股數、買入均價。
- **同代號合併**：加權平均成本。
- 顯示成本、現值、未實現損益（依報價）。
- 點持股可**賣出**（股數＋賣價）→ 產生已實現損益並減少持股。
- **圖片匯入（1.0.4）**：相簿／相機 → 本機 OCR → 解析股名／代號／股數／成本均價 → 預覽可改 → 確認寫入（可多列、可勾選）。  
  - 券商表常只有「股名」無代號時：用名稱對照表補代號（例如 元大高股息→0056）。  
  - 忽略「種類／現股」等欄。  
  - OCR **不上傳**持股圖到開發者伺服器（on-device ML Kit）。

### 4.3 總收益（Realized）
- 依年→月瀏覽已實現損益統計。
- 紀錄以刪除為主；刪除時可**還原股數回持倉**（undo／restore 邏輯）。

### 4.4 配置（Allocate）
- 依「股數」或「資金」做等分／配置建議（輔助下單前計算，非券商下單）。

### 4.5 全域
- 主題：淺色／深色／跟隨系統。
- 底部 **AdMob Banner**（延遲約 2 秒初始化，避免啟動閃退；失敗則佔位，不應拖垮 App）。

## 5. 技術架構（Flutter）

### 5.1 路徑
- 本機專案：`C:\Users\user\Documents\stock-helper-flutter`（目前**無遠端 git 主線**，以本機＋Desktop／Drive 產物為準）。
- Flutter SDK：`C:\flutter`

### 5.2 主要模組

```
lib/
  main.dart                 # App shell、Tab、主題、廣告區
  theme.dart
  models/models.dart        # Holding、SellRecord、賣出合併邏輯
  screens/
    watchlist_screen.dart
    holdings_screen.dart    # 持倉 UI＋圖片匯入入口
    realized_screen.dart
    allocate_screen.dart
  services/
    storage.dart            # shared_preferences 持久化
    quotes.dart             # 報價抓取／刷新
    names.dart              # 代號↔中文名；OCR 名稱→代號
    holdings_ocr.dart       # OCR 文字解析
    allocator.dart
    ticker.dart
  widgets/
    ad_banner_placeholder.dart  # 延遲 AdMob Banner
```

### 5.3 依賴（關鍵）
- `http` — 報價／名稱相關網路請求  
- `shared_preferences` — 本機資料  
- `intl` — 格式化  
- `google_mobile_ads` — Banner  
- `image_picker` + `google_mlkit_text_recognition` — 圖片匯入 OCR  

### 5.4 資料與隱私模型
- 預設：**本機儲存**，無強制登入。
- 持股／賣出紀錄不送到開發者自有後端。
- 廣告 SDK 可能依 Google 政策收集廣告 ID 等（Play 已宣告含廣告＋Advertising ID）。

### 5.5 廣告
- App ID / Banner unit 已接 AdMob。  
- 歷史問題：啟動時同步 `MobileAds.initialize` 曾導致強制關閉 → 改為延遲初始化。  
- 優化時勿在 `main()` 阻塞式初始化廣告。

## 6. 並行產品線（次要）
- Streamlit Web：功能對齊部分持倉／賣出／總收益，用於桌機瀏覽器測試（`localhost:8501`），**非** Play 主交付。

## 7. 已知限制與痛點（優化輸入）

1. **OCR**：券商 UI 版面差異大；僅名稱時靠對照表，冷門股／簡稱可能對不到或對錯。  
2. **報價來源／穩定性**：依賴外部行情，開休市邏輯需維持正確。  
3. **無雲端帳本**：換機需自行備份；多裝置不同步。  
4. **無帳號體系**：無法個人化雲端、也無法做社交／分享持倉（刻意簡化）。  
5. **Play 正式上架**：仍受測試人數／審核門檻限制。  
6. **商店顯示名稱**：曾出現套件名 `(unreviewed)`，審核通過後才穩。  
7. **APK 體積**：接入 ML Kit 後 APK 明顯變大（約 90MB+），可考慮 on-demand／精簡模型。  
8. **程式碼保護**：曾用 R8／混淆；廣告相關問題時曾關閉 minify，需在穩定與體積／保護間取捨。

## 8. 建議優化方向（給 AI 提案用，非已排程）

### UX／產品
- OCR 結果信心分數、對不到代號時的搜尋選股。  
- 批次匯入後的差異對照（新增／合併／略過）。  
- 持倉與觀察清單更清楚的空狀態與導引。  
- 匯出／備份（JSON／CSV）與還原。  
- 小工具／通知：自選股漲跌提醒（需謹慎權限與耗電）。

### 技術
- 將專案納入 Git／CI；Release 自動化（APK＋AAB＋Drive＋Play）。  
- 報價層抽象＋快取＋錯誤重試與離線顯示。  
- OCR parser 單元測試擴充（更多券商截圖 fixture）。  
- 廣告：同意聲明、GDPR／地區、延遲與預載策略。  
- 體積：ML Kit 動態下發或可選功能模組。  
- 可選：輕量後端／Google 登入做雲端同步（需改隱私政策與 Data safety）。

### 變現／成長
- AdMob 中介／原生廣告位（勿再阻塞啟動）。  
- Play 封閉測試湊滿 12 人×14 天 → 正式版。  
- ASO：商店文案、圖示、截圖與「股市助手」品牌一致性。

## 9. 給 AI 的工作約定（優化時請遵守）

1. **Android Flutter 為主交付**；改 Web／iOS 除非明確要求。  
2. 每次穩定功能更新：產出 **APK＋AAB**，同步桌面 `股票助手` 與 Drive `股票助手/Android`。  
3. 不要破壞：本機資料模型、賣出還原邏輯、延遲 AdMob、OCR 本機處理。  
4. 變更報價／OCR／儲存格式時：提供遷移或相容策略。  
5. 回報請用：問題 → 假設 → 改動檔案 → 驗證方式 → 風險。

## 10. 快速驗證清單

- [ ] 冷啟動不閃退；約 2 秒後橫幅可出或優雅失敗  
- [ ] 觀察清單開／休市報價行為正確  
- [ ] 手動加持股、合併均價正確  
- [ ] 賣出→總收益出現；刪除總收益可還原股數  
- [ ] 圖片匯入你提供的券商表（股名｜種類｜股數｜成本均價）能帶出三檔並可改代號  
- [ ] 主題切換持久化  

## 11. 關鍵識別資訊

- Package：`com.wick.stock_helper`  
- Play 開發者／App：已建立於 Google Play Console（內部／封閉測試進行中）  
- 聯絡：`chen780614@gmail.com`  

---

**文件結束。** 後續優化請以本文件為上下文起點，並在實作前列出假設與驗收標準。

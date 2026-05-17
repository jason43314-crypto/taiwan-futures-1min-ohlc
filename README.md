# Taiwan Futures 1-Minute OHLC (TXF / MTX / TMF)

台灣期貨交易所（TAIFEX）大台指、小台指、微型台指期貨的 **1 分 K OHLC** 歷史資料，匯出自個人 PostgreSQL（`quant_db.futures_1min`）。

## 商品對映

| 檔名 tag | product_id | 商品 | TAIFEX 代碼 |
|----------|-----------|------|-------------|
| FITXN    | `FITXN*1` | 大台指期（TXF）連續合約 | TX |
| FIMTXN   | `FIMTXN*1` | 小台指期（MXF）連續合約 | MTX |
| FITMN    | `FITMN*1` | 微型台指期（TMF）連續合約 | TMF |

> `*1` 表示連續合約（近月接續），非個別月份合約。

## 資料範圍

- **時間**：2001-01-02 ~ 2026-05-16
- **粒度**：1 分 K
- **筆數**：每商品約 3.75M 筆，合計 ~11.25M 筆
- **欄位**：`datetime, product_id, open, high, low, close, volume, trading_date, is_synthetic`

## 重要注意事項

1. **2001~2020 僅含日盤**，沒有夜盤資料；2020 之後才完整含夜盤。
2. **微台 TMF 實際 2022-05-09 才上市**，2001~2022 期間的微台資料皆為 `is_synthetic=true` 的補零量 bar（OHLC = 前一根 close、volume = 0），用於時間軸對齊，**研究時應依需求過濾**。
3. **`is_synthetic=true`** 也存在於其他商品的無成交分鐘（補零量 bar）。需要真實成交分鐘時請 `WHERE is_synthetic = false`。
4. **`trading_date` 語義**：
   - 日盤：歸當天
   - 夜盤 15:00~23:59：歸下一交易日
   - 00:00~05:00：若當天是交易日歸當天，否則歸下一交易日
   - 週五夜盤：歸下週一

## 還原方式（PostgreSQL）

```bash
# 1. 建空資料庫（如尚未建立）
psql -U postgres -c "CREATE DATABASE quant_db;"

# 2. 建立表結構
psql -U postgres -d quant_db -f schema.sql

# 3. 依序匯入所有 data 檔（Linux/Mac）
for f in data_*.sql; do
  psql -U postgres -d quant_db -f "$f"
done

# Windows PowerShell：
Get-ChildItem data_*.sql | ForEach-Object {
  psql -U postgres -d quant_db -f $_.FullName
}
```

## 檔案結構

- `schema.sql` — 表結構（`futures_1min` + 索引 + UNIQUE constraint）
- `data_<TAG>_<YEAR>.sql` — 各商品 × 各年份的資料檔（plain SQL，含 `COPY ... FROM stdin`）
- `export_to_sql.ps1` — 匯出腳本（從 PostgreSQL 重新匯出時使用）

## 資料來源

- TAIFEX 盤後逐筆 CSV（2001 起）
- XQ Log（部分歷史回填）
- 期交所即時收集（2026/04起）

## 授權與免責

僅供研究與學術用途。資料準確性不保證，使用者自行承擔風險。實盤交易請以官方資料源為準。

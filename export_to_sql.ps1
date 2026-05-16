# export_to_sql.ps1 — 將 quant_db.futures_1min 匯出為 plain SQL 檔（每商品 × 每年一檔）
# 輸出：D:\quant\sql_export\schema.sql + data_<商品>_<年>.sql
# 用法：powershell -ExecutionPolicy Bypass -File D:\quant\sql_export\export_to_sql.ps1

# ── 讀取 .env 取得 DB_PASSWORD ───────────────────────────────────
$envFile = "D:\trading_system\.env"                                 # trading_system 既有 .env 路徑
if (Test-Path $envFile) {                                           # 確認 .env 存在
    Get-Content $envFile | ForEach-Object {                         # 逐行讀取 .env
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {                    # KEY=VALUE 格式
            [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim())  # 設定環境變數
        }
    }
}

$psql = "D:\PostgreSQL\16\bin\psql.exe"                             # psql 執行檔
$env:PGPASSWORD = $env:DB_PASSWORD                                  # 設定 pg 密碼避免互動式輸入
$dbArgs = @("-h", "localhost", "-p", "5432", "-U", "postgres", "-d", "quant_db")  # DB 連線參數

$outDir = "D:\quant\sql_export"                                     # 輸出目錄
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }  # 確保存在

# ── 商品代碼與檔名安全字串對映（product_id 含 *，檔名要清理）──
$products = @{
    "FITXN*1"  = "FITXN"                                            # 大台
    "FIMTXN*1" = "FIMTXN"                                           # 小台
    "FITMN*1"  = "FITMN"                                            # 微台
}

# ── 1. 產生 schema.sql（表結構 + 索引）──────────────────────────
Write-Host "[1/2] 產生 schema.sql ..."
$schemaFile = Join-Path $outDir "schema.sql"                        # schema 檔路徑
$schemaSql = @"
-- futures_1min schema (quant_db)
-- 匯入順序：先 psql -f schema.sql，再依序 psql -f data_*.sql

BEGIN;

CREATE TABLE IF NOT EXISTS futures_1min (
    id           SERIAL PRIMARY KEY,
    datetime     TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    product_id   VARCHAR(20) NOT NULL,
    open         NUMERIC(10,2),
    high         NUMERIC(10,2),
    low          NUMERIC(10,2),
    close        NUMERIC(10,2),
    volume       BIGINT,
    trading_date DATE,
    is_synthetic BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT futures_1min_datetime_product_id_key UNIQUE (datetime, product_id)
);

CREATE INDEX IF NOT EXISTS idx_futures_1min_product_dt ON futures_1min (product_id, datetime DESC);
CREATE INDEX IF NOT EXISTS idx_futures_1min_td_product ON futures_1min (trading_date, product_id);
CREATE INDEX IF NOT EXISTS idx_futures_1min_trading_date ON futures_1min (trading_date);

COMMIT;
"@
Set-Content -Path $schemaFile -Value $schemaSql -Encoding ASCII      # 寫入 schema.sql（ASCII 避免 BOM）

# ── 2. 抓取每商品的年份範圍 ──────────────────────────────────────
Write-Host "[2/2] 產生 data_*.sql ..."

$totalFiles = 0                                                     # 累計檔案數
$totalRows = 0                                                      # 累計筆數

foreach ($prodId in $products.Keys) {                                  # 逐商品處理
    $tag = $products[$prodId]                                          # 檔名 tag (FITXN / FIMTXN / FITMN)

    # 抓該商品實際存在的年份
    $yearSql = "SELECT DISTINCT EXTRACT(YEAR FROM datetime)::int AS y FROM futures_1min WHERE product_id = '$prodId' ORDER BY y;"
    $years = & $psql @dbArgs -t -A -c $yearSql | Where-Object { $_ -match '^\d+$' }  # 取年份清單

    foreach ($y in $years) {                                        # 逐年產出
        $outFile = Join-Path $outDir ("data_{0}_{1}.sql" -f $tag, $y)  # 例：data_FITXN_2024.sql

        # 用 \copy 方式產生 COPY block，再用標頭/尾部包成 plain SQL
        # 範圍：[year-01-01 00:00, (year+1)-01-01 00:00)
        $copySql = @"
\copy (SELECT datetime, product_id, open, high, low, close, volume, trading_date, is_synthetic FROM futures_1min WHERE product_id = '$prodId' AND datetime >= '$y-01-01' AND datetime < '$([int]$y+1)-01-01' ORDER BY datetime) TO STDOUT
"@

        # 先把資料 COPY 出來到暫存
        $tmpData = Join-Path $outDir ("_tmp_{0}_{1}.tsv" -f $tag, $y)  # 暫存 TSV
        & $psql @dbArgs -c $copySql | Out-File -FilePath $tmpData -Encoding ASCII  # 寫入暫存（ASCII 避免 BOM）

        # 計算筆數
        $rowCount = (Get-Content $tmpData | Measure-Object -Line).Lines  # 計算行數

        if ($rowCount -eq 0) {                                      # 該年該商品無資料則跳過
            Remove-Item $tmpData -Force
            continue
        }

        # 組成 plain SQL：header + COPY ... FROM stdin + data + \. + footer
        $header = @"
-- futures_1min: $prodId year $y ($rowCount rows)
-- 匯入：psql -U postgres -d quant_db -f $(Split-Path $outFile -Leaf)

BEGIN;

COPY futures_1min (datetime, product_id, open, high, low, close, volume, trading_date, is_synthetic) FROM stdin;
"@
        $footer = @"
\.

COMMIT;
"@

        # 寫入 SQL 檔（header + 暫存資料內容 + footer，全 ASCII 避免 BOM 破壞 COPY 匯入）
        Set-Content -Path $outFile -Value $header -Encoding ASCII    # 寫 header
        Get-Content $tmpData | Add-Content -Path $outFile -Encoding ASCII  # 接資料
        Add-Content -Path $outFile -Value $footer -Encoding ASCII    # 接 footer

        Remove-Item $tmpData -Force                                  # 清暫存

        $size = [math]::Round((Get-Item $outFile).Length / 1MB, 1)   # 檔案大小 MB
        Write-Host ("  [{0}] {1}: {2:N0} rows, {3} MB" -f $tag, $y, $rowCount, $size)
        $totalFiles++                                                # 累計檔案數
        $totalRows += $rowCount                                      # 累計筆數
    }
}

Write-Host ""
Write-Host ("完成：{0} 個檔案，{1:N0} 筆資料" -f $totalFiles, $totalRows)  # 總結
Write-Host ("輸出目錄：{0}" -f $outDir)                              # 輸出位置

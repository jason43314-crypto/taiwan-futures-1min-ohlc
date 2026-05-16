-- futures_1min schema (quant_db)
-- ?????? psql -f schema.sql???? psql -f data_*.sql

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

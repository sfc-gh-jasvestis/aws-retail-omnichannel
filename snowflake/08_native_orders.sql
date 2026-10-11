-- ============================================================================
-- 08_native_orders.sql - Snowflake-only build: live order fulfilment feed without AWS.
-- Creates RAW.LIVE_ORDERS (same columns as the Snowpipe target created by
-- aws/setup_aws.py) and APP.SIMULATE_ORDERS(N), which inserts synthetic order fulfilment
-- events with the same value ranges and ~10% LATE rate as
-- aws/publish_orders.py. Rows are inserted directly; this simulates an order fulfilment
-- feed and is not Snowpipe Streaming.
-- Run before 06_intelligence.sql (the alert reads RAW.LIVE_ORDERS).
-- Idempotent: safe to run in the AWS build too.
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS APP;

CREATE TABLE IF NOT EXISTS RAW.LIVE_ORDERS (
  STORE_ID VARCHAR, EVENT_TS TIMESTAMP_NTZ, ORDER_VALUE_SGD FLOAT, READY_MINUTES FLOAT,
  STATUS VARCHAR, SENT_TS TIMESTAMP_NTZ, SOURCE_FILE VARCHAR,
  LOADED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP());

CREATE OR REPLACE PROCEDURE APP.SIMULATE_ORDERS(N NUMBER)
RETURNS NUMBER
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
  IF (N < 1 OR N > 1000) THEN
    RETURN 0;
  END IF;
  INSERT INTO RAW.LIVE_ORDERS (STORE_ID, EVENT_TS, ORDER_VALUE_SGD, READY_MINUTES, STATUS, SENT_TS, SOURCE_FILE)
    WITH g AS (
      SELECT 'STR-' || LPAD(UNIFORM(0, 39, RANDOM())::VARCHAR, 4, '0') AS STORE_ID,
             UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.1 AS IS_LATE,
             SYSDATE() AS TS, SEQ4() AS I
      FROM TABLE(GENERATOR(ROWCOUNT => 1000))
    )
    -- NORMAL() needs constant arguments, so the status offset is applied outside it.
    SELECT STORE_ID, TS,
           ROUND(72 * EXP(NORMAL(0, 0.5, RANDOM())), 2),
           ROUND(IFF(IS_LATE, 210, 70) * EXP(NORMAL(0, 0.35, RANDOM())), 0),
           IFF(IS_LATE, 'LATE', 'FULFILLED'), TS, 'APP.SIMULATE_ORDERS'
    FROM g
    WHERE I < :N;
  RETURN SQLROWCOUNT;
END;
$$;

-- Optional continuous feed for longer demos (suspended; RESUME to start, SUSPEND after).
CREATE OR REPLACE TASK APP.TASK_SIMULATE_ORDERS
  WAREHOUSE = __DEMO_WH__
  SCHEDULE = '1 MINUTE'
AS
  CALL APP.SIMULATE_ORDERS(5);

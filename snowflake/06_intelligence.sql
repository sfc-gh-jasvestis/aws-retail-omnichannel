-- ============================================================================
-- 06_INTELLIGENCE.SQL - search, anomaly detection, semantic view, agent,
-- live late-order alert and on-demand refresh DAG.
-- Run with snowflake/run_intelligence.py (substitutes checked __DEMO_DB__ /
-- __DEMO_WH__ / __ALERT_EMAIL__). Requires 00-05, plus 08 (Snowflake only) or
-- aws/setup_aws.py (AWS build) for RAW.LIVE_ORDERS.
-- Alerts and tasks are created SUSPENDED; run them with EXECUTE ALERT / EXECUTE TASK.
-- ============================================================================
USE DATABASE __DEMO_DB__;
CREATE SCHEMA IF NOT EXISTS SEARCH;
CREATE SCHEMA IF NOT EXISTS APP;

-- ---------- Synthetic fulfilment disruption SOPs (clearly synthetic) ----------
CREATE OR REPLACE TABLE SEARCH.PLAYBOOK_DOCS AS
WITH causes AS (
  SELECT DISTINCT r.DISRUPTION_CAUSE, s.CATEGORY
  FROM RAW.STORE_DAILY r JOIN RAW.STORES s ON s.ID = r.ENTITY_ID
  WHERE r.DISRUPTION_HOURS > 0
)
SELECT
  'PLB-' || LPAD(ROW_NUMBER() OVER (ORDER BY CATEGORY, DISRUPTION_CAUSE)::VARCHAR, 3, '0') AS DOC_ID,
  'SOP' AS DOC_TYPE,
  CATEGORY,
  DISRUPTION_CAUSE,
  CATEGORY || ' - ' || DISRUPTION_CAUSE || ' fulfilment disruption SOP' AS TITLE,
  'Synthetic demo SOP. Channel: ' || CATEGORY || '. Disruption cause: ' || DISRUPTION_CAUSE || '. '
  || 'Step 1: open a fulfilment incident for the node and shorten the promised ready time shown to new customers until the incident is triaged. '
  || 'Step 2: ' || CASE
       WHEN DISRUPTION_CAUSE = 'Picker shortage' THEN 'move pickers from the nearest node with spare capacity, batch small orders into multi-order pick waves, and close the latest same-day order cut-off one hour earlier.'
       WHEN DISRUPTION_CAUSE = 'Courier no-show' THEN 'release the affected orders to the backup courier pool, tell customers the revised delivery window by app notification, and log the no-show for the weekly courier review.'
       WHEN DISRUPTION_CAUSE = 'Stock count overdue' THEN 'run the overdue cycle count on the fastest-moving lines first, hide items with unconfirmed stock from online availability, and confirm the next count date with the store manager.'
       WHEN DISRUPTION_CAUSE = 'Inventory mismatch' THEN 'recount the mismatched lines, offer the customer a substitute or a refund before picking starts, and correct the online stock figure for the node.'
       WHEN DISRUPTION_CAUSE = 'Pickup counter backlog' THEN 'open a second pickup counter, send customers a ready-for-collection message only when the order is staged, and move staged orders to numbered shelves.'
       WHEN DISRUPTION_CAUSE = 'Locker capacity full' THEN 'send overflow parcels to the nearest locker bank with free compartments, extend the collection window for parcels already loaded, and tell customers the new locker location by app notification.'
       WHEN DISRUPTION_CAUSE = 'Carrier pickup missed' THEN 'book the next carrier collection, move urgent orders to the same-day courier pool, and update the dispatch date shown to customers.'
       WHEN DISRUPTION_CAUSE = 'Packing station outage' THEN 'route orders to the backup packing bench, print labels from the store office, and stop accepting ship-from-store orders for the node until both benches are working.'
       WHEN DISRUPTION_CAUSE = 'Listing sync delay' THEN 'pause the affected marketplace listings, resend the stock and price feed, and cancel only the orders that cannot be filled within the promised time.'
       WHEN DISRUPTION_CAUSE = 'Payment gateway outage' THEN 'hold unpaid marketplace orders out of the pick queue, retry payment confirmation every 15 minutes, and tell customers their order is waiting for payment confirmation.'
       WHEN DISRUPTION_CAUSE = 'Mega-sale order surge' THEN 'switch every node in the planning area to sale-day staffing, cap new same-day orders per hour, and send customers a realistic ready time at checkout.'
       ELSE 'review the disruption against the node profile and escalate if unexplained.'
     END
  || ' Step 3: if late orders at the node stay above 10% or the average order-to-ready time stays above 6 hours after one day, keep the incident open and request a node capacity review. '
  || 'Step 4: record the resolution; if a cycle count was overdue, log it for the weekly inventory accuracy report.' AS CONTENT
FROM causes;

CREATE OR REPLACE CORTEX SEARCH SERVICE SEARCH.PLAYBOOK_SEARCH
  ON CONTENT
  ATTRIBUTES CATEGORY, DISRUPTION_CAUSE
  WAREHOUSE = __DEMO_WH__
  TARGET_LAG = '7 days'
AS (SELECT DOC_ID, TITLE, CATEGORY, DISRUPTION_CAUSE, CONTENT FROM SEARCH.PLAYBOOK_DOCS);

-- ---------- Order-to-ready time anomaly detection (train first 75 days, detect last 15) ----------
CREATE OR REPLACE VIEW ML.FULFIL_HOURS_SERIES AS
SELECT ENTITY_ID, EVENT_DATE::TIMESTAMP_NTZ AS TS, AVG_FULFIL_HOURS::FLOAT AS FULFIL_HOURS
FROM RAW.STORE_DAILY;
CREATE OR REPLACE VIEW ML.FULFIL_HOURS_TRAIN AS
SELECT * FROM ML.FULFIL_HOURS_SERIES WHERE TS < (SELECT DATEADD(day, -15, MAX(TS)) FROM ML.FULFIL_HOURS_SERIES);
CREATE OR REPLACE VIEW ML.FULFIL_HOURS_DETECT AS
SELECT * FROM ML.FULFIL_HOURS_SERIES WHERE TS >= (SELECT DATEADD(day, -15, MAX(TS)) FROM ML.FULFIL_HOURS_SERIES);

CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION ML.FULFIL_HOURS_ANOMALY_MODEL(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML.FULFIL_HOURS_TRAIN'),
  SERIES_COLNAME => 'ENTITY_ID', TIMESTAMP_COLNAME => 'TS', TARGET_COLNAME => 'FULFIL_HOURS',
  LABEL_COLNAME => '');

CREATE OR REPLACE TABLE ML.FULFIL_HOURS_ANOMALIES AS
SELECT SERIES::VARCHAR AS ENTITY_ID, TS::DATE AS EVENT_DATE, Y AS FULFIL_HOURS, FORECAST AS EXPECTED,
       LOWER_BOUND, UPPER_BOUND, IS_ANOMALY, PERCENTILE
FROM TABLE(ML.FULFIL_HOURS_ANOMALY_MODEL!DETECT_ANOMALIES(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML.FULFIL_HOURS_DETECT'),
  SERIES_COLNAME => 'ENTITY_ID', TIMESTAMP_COLNAME => 'TS', TARGET_COLNAME => 'FULFIL_HOURS'));

-- ---------- Semantic view ----------
CREATE OR REPLACE SEMANTIC VIEW APP.OMNICHANNEL_ANALYTICS
  TABLES (
    nodes AS CURATED.PERFORMANCE_SUMMARY PRIMARY KEY (ENTITY_ID)
      COMMENT = 'One row per fulfilment node (one channel in one Singapore planning area), 90-day totals',
    risk AS ML.DISRUPTION_RISK_SCORES PRIMARY KEY (ENTITY_ID)
      COMMENT = 'Latest next-7-day fulfilment-disruption probability per node',
    causes AS CURATED.CAUSE_SUMMARY PRIMARY KEY (DISRUPTION_CAUSE)
      COMMENT = 'Disruption node-days, disruption hours and late orders by disruption cause, 90 days',
    daily AS CURATED.TREND_ANALYSIS PRIMARY KEY (METRIC_DATE)
      COMMENT = 'Network-wide totals per day'
  )
  RELATIONSHIPS (risk_node AS risk (ENTITY_ID) REFERENCES nodes)
  FACTS (
    nodes.orders_f AS ORDER_COUNT,
    nodes.fulfilled_f AS FULFILLED_COUNT,
    nodes.late_f AS LATE_COUNT,
    nodes.cancelled_f AS CANCELLED_COUNT,
    nodes.sales_f AS NET_SALES_SGD,
    nodes.disruption_hours_f AS DISRUPTION_HOURS,
    nodes.disruption_days_f AS DISRUPTION_DAYS,
    nodes.sync_due_f AS SYNC_DUE,
    nodes.sync_done_f AS SYNC_DONE,
    nodes.passes_f AS AVG_PICK_PASSES,
    nodes.hours_f AS AVG_FULFIL_HOURS,
    risk.disruption_prob_f AS DISRUPTION_PROB_7D,
    causes.cause_days_f AS DISRUPTION_DAYS,
    causes.cause_hours_f AS DISRUPTION_HOURS,
    causes.cause_late_f AS LATE_COUNT,
    causes.cause_orders_f AS ORDER_COUNT,
    daily.day_orders_f AS ORDER_COUNT,
    daily.day_fulfilled_f AS FULFILLED_COUNT,
    daily.day_late_f AS LATE_COUNT,
    daily.day_sales_f AS NET_SALES_SGD
  )
  DIMENSIONS (
    nodes.node_id AS ENTITY_ID WITH SYNONYMS = ('node', 'fulfilment node', 'store'),
    nodes.node_name AS ENTITY_NAME,
    nodes.planning_area AS REGION WITH SYNONYMS = ('planning area', 'area', 'region', 'town')
      COMMENT = 'Singapore planning area: Jurong East, Tampines, Woodlands, Ang Mo Kio or Punggol',
    nodes.channel AS CATEGORY WITH SYNONYMS = ('channel', 'fulfilment channel', 'fulfilment method')
      COMMENT = 'Same-day delivery, Click and collect, Parcel locker pickup, Ship from store or Marketplace',
    nodes.store_tier AS STORE_TIER COMMENT = 'Store operating complexity tier 1 (simple) to 3 (complex)',
    risk.risk_band AS RISK_BAND COMMENT = 'High >= 0.5, Medium >= 0.25, else Low',
    risk.scored_as_of AS SCORED_AS_OF,
    causes.disruption_cause AS DISRUPTION_CAUSE WITH SYNONYMS = ('cause', 'disruption reason', 'reason'),
    daily.metric_date AS METRIC_DATE
  )
  METRICS (
    nodes.node_count AS COUNT(nodes.node_id) WITH SYNONYMS = ('number of nodes', 'nodes monitored', 'entities', 'stores'),
    nodes.on_time_fulfilment_pct AS 100 * SUM(nodes.fulfilled_f) / NULLIF(SUM(nodes.orders_f), 0)
      WITH SYNONYMS = ('on-time fulfilment rate', 'on-time rate', 'promise kept rate')
      COMMENT = 'Orders fulfilled within the promised time / orders placed',
    nodes.cancellation_rate_pct AS 100 * SUM(nodes.cancelled_f) / NULLIF(SUM(nodes.orders_f), 0)
      WITH SYNONYMS = ('order cancellation rate', 'cancel rate')
      COMMENT = 'Orders cancelled before fulfilment / orders placed',
    nodes.total_orders AS SUM(nodes.orders_f) WITH SYNONYMS = ('orders', 'order volume', 'orders placed'),
    nodes.total_fulfilled AS SUM(nodes.fulfilled_f) WITH SYNONYMS = ('orders fulfilled on time', 'on-time orders'),
    nodes.total_late AS SUM(nodes.late_f) WITH SYNONYMS = ('late orders', 'missed promises', 'late fulfilment'),
    nodes.total_disruption_hours AS SUM(nodes.disruption_hours_f) WITH SYNONYMS = ('disruption hours', 'fulfilment disruption'),
    nodes.total_disruption_days AS SUM(nodes.disruption_days_f),
    nodes.total_sales_sgd AS SUM(nodes.sales_f) WITH SYNONYMS = ('net sales', 'sales', 'sales in SGD'),
    nodes.cycle_count_on_time_pct AS 100 * SUM(nodes.sync_done_f) / NULLIF(SUM(nodes.sync_due_f), 0)
      COMMENT = 'Inventory cycle counts completed on schedule / cycle counts due',
    nodes.mean_pick_passes AS AVG(nodes.passes_f),
    nodes.mean_fulfil_hours AS AVG(nodes.hours_f),
    risk.avg_disruption_prob AS AVG(risk.disruption_prob_f),
    causes.cause_disruption_days AS SUM(causes.cause_days_f),
    causes.cause_disruption_hours AS SUM(causes.cause_hours_f),
    causes.cause_late AS SUM(causes.cause_late_f),
    causes.cause_late_pct AS 100 * SUM(causes.cause_late_f) / NULLIF(SUM(causes.cause_orders_f), 0),
    daily.daily_orders AS SUM(daily.day_orders_f),
    daily.daily_fulfilled AS SUM(daily.day_fulfilled_f),
    daily.daily_late AS SUM(daily.day_late_f),
    daily.daily_sales_sgd AS SUM(daily.day_sales_f)
  )
  COMMENT = 'Synthetic Singapore omnichannel fulfilment operations analytics (demo)';

-- ---------- Cortex Agent ----------
CREATE OR REPLACE AGENT APP.OMNICHANNEL_OPS_AGENT
  COMMENT = 'Fulfilment operations assistant over a synthetic Singapore omnichannel retail network'
  FROM SPECIFICATION
$$
models:
  orchestration: claude-sonnet-4-5
instructions:
  response: "Answer only from tool results. State that data is synthetic. Give node IDs and numbers with units (SGD, %, hours)."
  orchestration: "Use omnichannel_analyst for orders, on-time fulfilment rate, late orders, cancellations, disruption hours, net sales, inventory cycle counts, fulfilment nodes, planning areas, channels, disruption causes and disruption risk. Use playbook_search for fulfilment disruption procedures."
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: omnichannel_analyst
      description: "Orders placed, orders fulfilled on time, on-time fulfilment rate, late orders, order cancellations, fulfilment disruption hours, net sales in SGD, cycle count on-time rate, disruption causes and fulfilment-disruption risk scores by node, planning area and channel"
  - tool_spec:
      type: cortex_search
      name: playbook_search
      description: "Synthetic fulfilment disruption SOPs by channel and disruption cause"
tool_resources:
  omnichannel_analyst:
    semantic_view: __DEMO_DB__.APP.OMNICHANNEL_ANALYTICS
    execution_environment:
      type: warehouse
      warehouse: __DEMO_WH__
  playbook_search:
    name: __DEMO_DB__.SEARCH.PLAYBOOK_SEARCH
    max_results: 3
    id_column: DOC_ID
    title_column: TITLE
$$;

-- ---------- Live late-order alert ----------
CREATE TABLE IF NOT EXISTS APP.ALERT_LOG (
  ALERTED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(), STORE_ID VARCHAR,
  EVENT_TS TIMESTAMP_NTZ, ORDER_VALUE_SGD FLOAT, READY_MINUTES FLOAT, PLAYBOOK_HINT VARCHAR);

CREATE OR REPLACE NOTIFICATION INTEGRATION SG_RETAIL_OMNICHANNEL_EMAIL_INT
  TYPE = EMAIL ENABLED = TRUE ALLOWED_RECIPIENTS = ('__ALERT_EMAIL__');

CREATE OR REPLACE PROCEDURE APP.LOG_LIVE_ALERTS()
RETURNS NUMBER
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  n NUMBER;
BEGIN
  INSERT INTO APP.ALERT_LOG (STORE_ID, EVENT_TS, ORDER_VALUE_SGD, READY_MINUTES, PLAYBOOK_HINT)
    SELECT t.STORE_ID, t.EVENT_TS, t.ORDER_VALUE_SGD, t.READY_MINUTES,
           'Check ' || z.CATEGORY || ' fulfilment disruption SOPs; current risk band ' || COALESCE(s.RISK_BAND, 'n/a')
    FROM RAW.LIVE_ORDERS t
    JOIN RAW.STORES z ON z.ID = t.STORE_ID
    LEFT JOIN ML.DISRUPTION_RISK_SCORES s ON s.ENTITY_ID = t.STORE_ID
    WHERE t.STATUS = 'LATE'
      AND NOT EXISTS (SELECT 1 FROM APP.ALERT_LOG l WHERE l.STORE_ID = t.STORE_ID AND l.EVENT_TS = t.EVENT_TS);
  n := SQLROWCOUNT;
  IF (n > 0) THEN
    CALL SYSTEM$SEND_EMAIL('SG_RETAIL_OMNICHANNEL_EMAIL_INT', '__ALERT_EMAIL__',
      '[Demo] Late order alert',
      'New late orders logged in APP.ALERT_LOG: ' || :n || '. Data is synthetic.');
  END IF;
  RETURN n;
END;
$$;

CREATE OR REPLACE ALERT APP.LIVE_ORDER_ALERT
  WAREHOUSE = __DEMO_WH__
  SCHEDULE = '5 MINUTE'
  IF (EXISTS (
    SELECT 1 FROM RAW.LIVE_ORDERS t
    WHERE t.STATUS = 'LATE'
      AND NOT EXISTS (SELECT 1 FROM APP.ALERT_LOG l WHERE l.STORE_ID = t.STORE_ID AND l.EVENT_TS = t.EVENT_TS)))
  THEN CALL APP.LOG_LIVE_ALERTS();

-- ---------- On-demand refresh DAG (suspended; run with EXECUTE TASK APP.TASK_REFRESH_CURATED) ----------
CREATE OR REPLACE PROCEDURE APP.REFRESH_CURATED()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
  ALTER DYNAMIC TABLE CURATED.PERFORMANCE_SUMMARY REFRESH;
  ALTER DYNAMIC TABLE CURATED.TREND_ANALYSIS REFRESH;
  ALTER DYNAMIC TABLE CURATED.CAUSE_SUMMARY REFRESH;
  ALTER DYNAMIC TABLE CURATED.KPI_SUMMARY REFRESH;
  RETURN 'refreshed';
END;
$$;

CREATE OR REPLACE TASK APP.TASK_REFRESH_CURATED
  WAREHOUSE = __DEMO_WH__
AS
  CALL APP.REFRESH_CURATED();

CREATE OR REPLACE TASK APP.TASK_RESCORE_RISK
  WAREHOUSE = __DEMO_WH__
  AFTER APP.TASK_REFRESH_CURATED
AS
  CREATE OR REPLACE TABLE ML.DISRUPTION_RISK_SCORES COPY GRANTS AS
  WITH latest AS (
    SELECT * FROM ML.DISRUPTION_FEATURES QUALIFY ROW_NUMBER() OVER (PARTITION BY ENTITY_ID ORDER BY EVENT_DATE DESC) = 1
  ), p AS (
    SELECT ENTITY_ID, EVENT_DATE,
           ML.DISRUPTION_RISK_MODEL!PREDICT(INPUT_DATA => OBJECT_CONSTRUCT(
             'CATEGORY', CATEGORY, 'STORE_TIER', STORE_TIER, 'STORE_AGE_YEARS', STORE_AGE_YEARS,
             'AVG_PICK_PASSES', AVG_PICK_PASSES, 'AVG_FULFIL_HOURS', AVG_FULFIL_HOURS,
             'FULFIL_HOURS_7D', FULFIL_HOURS_7D, 'DISRUPTION_HOURS_30D', DISRUPTION_HOURS_30D)) AS PRED
    FROM latest
  )
  SELECT ENTITY_ID, EVENT_DATE AS SCORED_AS_OF, ROUND(PRED:probability:DISRUPTION::FLOAT, 4) AS DISRUPTION_PROB_7D,
         CASE WHEN PRED:probability:DISRUPTION::FLOAT >= 0.5 THEN 'High'
              WHEN PRED:probability:DISRUPTION::FLOAT >= 0.25 THEN 'Medium' ELSE 'Low' END AS RISK_BAND,
         CURRENT_TIMESTAMP() AS SCORED_AT
  FROM p;

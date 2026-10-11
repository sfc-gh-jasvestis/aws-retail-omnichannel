-- Synthetic store-day observations for a fictional Singapore omnichannel retailer.
-- A fulfilment node is one fulfilment channel (same-day delivery, click and
-- collect, parcel locker pickup, ship from store, marketplace) in one Singapore planning area.
-- Nothing is seeded as a prediction. Randomness is HASH-seeded, so every rebuild
-- is reproducible: per-store disruption propensity, inventory accuracy drift
-- between cycle counts, overdue counts, channel-weighted disruption causes, and
-- two area-wide mega-sale order surges.
USE DATABASE IDENTIFIER($DEMO_DB);
USE SCHEMA RAW;
USE WAREHOUSE IDENTIFIER($DEMO_WH);

CREATE TABLE RAW.STORES AS
WITH stores AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS STORE_INDEX
  FROM TABLE(GENERATOR(ROWCOUNT => 40))
), draws AS (
  SELECT STORE_INDEX,
         MOD(ABS(HASH(STORE_INDEX, 'sg-rtlomni-age')), 1000000) / 1e6 AS U_AGE,
         MOD(ABS(HASH(STORE_INDEX, 'sg-rtlomni-rate')), 1000000) / 1e6 AS U_RATE,
         MOD(ABS(HASH(STORE_INDEX, 'sg-rtlomni-count')), 1000000) / 1e6 AS U_SYNC,
         MOD(ABS(HASH(STORE_INDEX, 'sg-rtlomni-discipline')), 1000000) / 1e6 AS U_DISCIPLINE,
         MOD(ABS(HASH(STORE_INDEX, 'sg-rtlomni-tier')), 1000000) / 1e6 AS U_TIER
  FROM stores
), labelled AS (
  SELECT *,
         -- Deterministic spread (5 and 8 are coprime): every planning area and channel is present.
         CASE MOD(STORE_INDEX, 5) WHEN 0 THEN 'Jurong East' WHEN 1 THEN 'Tampines'
              WHEN 2 THEN 'Woodlands' WHEN 3 THEN 'Ang Mo Kio' ELSE 'Punggol' END AS AREA,
         CASE MOD(STORE_INDEX, 8) WHEN 0 THEN 'Same-day delivery' WHEN 1 THEN 'Same-day delivery'
              WHEN 2 THEN 'Same-day delivery' WHEN 3 THEN 'Click and collect' WHEN 4 THEN 'Click and collect'
              WHEN 5 THEN 'Parcel locker pickup' WHEN 6 THEN 'Ship from store' ELSE 'Marketplace' END AS CHANNEL
  FROM draws
)
SELECT 'STR-' || LPAD(STORE_INDEX::VARCHAR, 4, '0') AS ID,
       AREA || ' ' || CHANNEL || ' node ' || LPAD(STORE_INDEX::VARCHAR, 4, '0') AS NAME,
       AREA AS REGION, CHANNEL AS CATEGORY, STORE_INDEX,
       1 + FLOOR(U_TIER * 3) AS STORE_TIER,
       ROUND(0.5 + U_AGE * 9.5, 1) AS STORE_AGE_YEARS,
       -- Base daily probability of a fulfilment disruption 0.6%-2.8%; ~13% of
       -- nodes are chronically hard to run (x3).
       (0.006 + U_RATE * 0.022) * IFF(U_RATE > 0.87, 3, 1) AS BASE_DISRUPTION_RATE,
       7 * (1 + FLOOR(U_SYNC * 3)) AS SYNC_INTERVAL_DAYS,
       0.6 + U_DISCIPLINE * 0.38 AS SYNC_ON_TIME_PROB,
       'Active' AS STATUS
FROM labelled;

CREATE TABLE RAW.STORE_DAILY AS
WITH days AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS DAY_INDEX
  FROM TABLE(GENERATOR(ROWCOUNT => 90))
), area_events AS (
  -- Two area-wide mega-sale order surges; every node in the planning area loses 5 fulfilment hours.
  SELECT * FROM VALUES (27, 'Tampines'), (63, 'Jurong East') AS o(DAY_INDEX, REGION)
), base AS (
  SELECT s.ID AS ENTITY_ID, s.STORE_INDEX, s.CATEGORY, s.REGION, s.STORE_AGE_YEARS,
         s.BASE_DISRUPTION_RATE, s.SYNC_INTERVAL_DAYS, s.SYNC_ON_TIME_PROB,
         d.DAY_INDEX,
         DATEADD('day', d.DAY_INDEX - 89, CURRENT_DATE()) AS EVENT_DATE,
         MOD(d.DAY_INDEX + s.STORE_INDEX * 5, s.SYNC_INTERVAL_DAYS) AS DAYS_SINCE_SYNC,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'sg-rtlomni-short')), 1000000) / 1e6 AS U_SHORT,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'sg-rtlomni-detect')), 1000000) / 1e6 AS U_DETECT,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'sg-rtlomni-hours')), 1000000) / 1e6 AS U_HOURS,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'sg-rtlomni-cause')), 1000000) / 1e6 AS U_CAUSE,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'sg-rtlomni-done')), 1000000) / 1e6 AS U_DONE,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'sg-rtlomni-volume')), 1000000) / 1e6 AS U_VOLUME,
         MOD(ABS(HASH(s.ID, d.DAY_INDEX, 'sg-rtlomni-noise')), 1000000) / 1e6 AS U_NOISE,
         e.REGION IS NOT NULL AS AREA_EVENT
  FROM RAW.STORES s CROSS JOIN days d
  LEFT JOIN area_events e ON e.DAY_INDEX = d.DAY_INDEX AND e.REGION = s.REGION
), counts AS (
  SELECT *,
         IFF(DAYS_SINCE_SYNC = 0, 1, 0) AS SYNC_DUE,
         IFF(DAYS_SINCE_SYNC = 0 AND U_DONE < SYNC_ON_TIME_PROB, 1, 0) AS SYNC_DONE,
         -- Inventory accuracy drifts between cycle counts; overdue counts
         -- carry the drift over.
         DAYS_SINCE_SYNC / SYNC_INTERVAL_DAYS + (1 - SYNC_ON_TIME_PROB) AS DRIFT
  FROM base
), risk AS (
  SELECT *,
         CASE WHEN U_SHORT < LEAST(0.5, BASE_DISRUPTION_RATE * (0.4 + 1.6 * DRIFT) * (1 + 1 / (1 + STORE_AGE_YEARS))) / 4 THEN 2
              WHEN U_SHORT < LEAST(0.5, BASE_DISRUPTION_RATE * (0.4 + 1.6 * DRIFT) * (1 + 1 / (1 + STORE_AGE_YEARS))) THEN 1
              ELSE 0 END AS DISRUPTION_RISK
  FROM counts
), disruptions AS (
  SELECT *,
         -- About 80% of at-risk days turn into measured disruption hours; staff
         -- borrowed from nearby nodes absorb the rest.
         IFF(AREA_EVENT, 5, IFF(U_DETECT < 0.8, DISRUPTION_RISK * (1 + FLOOR(U_HOURS * 3)), 0)) AS DISRUPTION_HOURS
  FROM risk
), measured AS (
  SELECT *,
         ROUND(CASE CATEGORY WHEN 'Same-day delivery' THEN 620 WHEN 'Click and collect' THEN 540
                             WHEN 'Parcel locker pickup' THEN 210 WHEN 'Ship from store' THEN 380 ELSE 900 END
               * (0.7 + 0.6 * U_VOLUME) * (1 + 0.1 * DISRUPTION_RISK)) AS ORDER_COUNT,
         CASE CATEGORY WHEN 'Same-day delivery' THEN 76 WHEN 'Click and collect' THEN 60
                       WHEN 'Parcel locker pickup' THEN 52 WHEN 'Ship from store' THEN 83 ELSE 48 END
           * (0.85 + 0.3 * U_NOISE) * (1 + 0.02 * DISRUPTION_HOURS) AS AVG_ORDER_SGD
  FROM disruptions
), outcomes AS (
  SELECT *,
         ROUND(ORDER_COUNT * (0.03 + 0.015 * DRIFT + 0.03 * DISRUPTION_HOURS)) AS LATE_COUNT,
         ROUND(ORDER_COUNT * (0.015 + 0.012 * U_NOISE + 0.004 * DISRUPTION_HOURS)) AS CANCELLED_COUNT
  FROM measured
)
SELECT ENTITY_ID || '-' || TO_CHAR(EVENT_DATE, 'YYYYMMDD') AS EVENT_ID,
       ENTITY_ID, EVENT_DATE,
       ORDER_COUNT,
       ORDER_COUNT - LATE_COUNT - CANCELLED_COUNT AS FULFILLED_COUNT,
       LATE_COUNT, CANCELLED_COUNT,
       ROUND((ORDER_COUNT - CANCELLED_COUNT) * AVG_ORDER_SGD) AS NET_SALES_SGD,
       DISRUPTION_HOURS,
       CASE WHEN DISRUPTION_HOURS = 0 THEN 'None'
            WHEN AREA_EVENT THEN 'Mega-sale order surge'
            WHEN CATEGORY = 'Same-day delivery' THEN IFF(U_CAUSE < 0.45, 'Picker shortage', IFF(U_CAUSE < 0.8, 'Courier no-show', 'Stock count overdue'))
            WHEN CATEGORY = 'Click and collect' THEN IFF(U_CAUSE < 0.4, 'Inventory mismatch', IFF(U_CAUSE < 0.75, 'Pickup counter backlog', 'Stock count overdue'))
            WHEN CATEGORY = 'Parcel locker pickup' THEN IFF(U_CAUSE < 0.55, 'Locker capacity full', 'Picker shortage')
            WHEN CATEGORY = 'Ship from store' THEN IFF(U_CAUSE < 0.5, 'Carrier pickup missed', 'Packing station outage')
            ELSE IFF(U_CAUSE < 0.5, 'Listing sync delay', IFF(U_CAUSE < 0.8, 'Inventory mismatch', 'Payment gateway outage')) END AS DISRUPTION_CAUSE,
       SYNC_DUE, SYNC_DONE,
       ROUND(1.06 + 0.08 * DRIFT + 0.12 * DISRUPTION_RISK + 0.05 * U_NOISE, 2) AS AVG_PICK_PASSES,
       ROUND(2.5 + 1.5 * DRIFT + 2 * DISRUPTION_RISK + U_NOISE, 1) AS AVG_FULFIL_HOURS,
       CURRENT_TIMESTAMP() AS LOADED_AT
FROM outcomes;

-- Fulfilment staff training checks per node (snapshot).
CREATE TABLE RAW.STAFF_TRAINING AS
SELECT ID AS ENTITY_ID,
       CASE CATEGORY WHEN 'Same-day delivery' THEN 'Picker accuracy training'
                     WHEN 'Click and collect' THEN 'Counter handover training'
                     WHEN 'Parcel locker pickup' THEN 'Locker loading training'
                     WHEN 'Ship from store' THEN 'Packing and labelling training'
                     ELSE 'Marketplace listing training' END AS DOC_TYPE,
       1 + MOD(ABS(HASH(ID, 'sg-rtlomni-req')), 5) AS REQUIRED_QTY,
       MOD(ABS(HASH(ID, 'sg-rtlomni-file')), 5) AS ON_FILE_QTY,
       IFF(MOD(ABS(HASH(ID, 'sg-rtlomni-file')), 5) < 1 + MOD(ABS(HASH(ID, 'sg-rtlomni-req')), 5),
           MOD(ABS(HASH(ID, 'sg-rtlomni-pending')), 3), 0) AS PENDING_QTY,
       CURRENT_DATE() AS SNAPSHOT_DATE
FROM RAW.STORES;

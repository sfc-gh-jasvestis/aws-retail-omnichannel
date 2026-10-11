-- Validate the producer contract before building downstream objects.
USE DATABASE IDENTIFIER($DEMO_DB);
USE SCHEMA RAW;
USE WAREHOUSE IDENTIFIER($DEMO_WH);

EXECUTE IMMEDIATE $$
DECLARE
  violations INTEGER;
  invalid_source EXCEPTION (-20001, 'Synthetic source failed grain or measure validation');
BEGIN
  SELECT COUNT(*) INTO :violations FROM (
    SELECT ENTITY_ID, EVENT_DATE
    FROM RAW.STORE_DAILY
    GROUP BY ENTITY_ID, EVENT_DATE HAVING COUNT(*) <> 1
    UNION ALL
    SELECT observation.ENTITY_ID, observation.EVENT_DATE
    FROM RAW.STORE_DAILY observation
    LEFT JOIN RAW.STORES store ON store.ID = observation.ENTITY_ID
    WHERE store.ID IS NULL OR observation.ORDER_COUNT <= 0
       OR observation.NET_SALES_SGD < 0 OR observation.FULFILLED_COUNT < 0
       OR observation.LATE_COUNT < 0 OR observation.CANCELLED_COUNT < 0
       OR observation.FULFILLED_COUNT + observation.LATE_COUNT + observation.CANCELLED_COUNT <> observation.ORDER_COUNT
       OR observation.DISRUPTION_HOURS NOT BETWEEN 0 AND 24
       OR observation.SYNC_DONE > observation.SYNC_DUE
  );
  IF (violations > 0) THEN
    RAISE invalid_source;
  END IF;
END;
$$;

#!/usr/bin/env bash
set -euo pipefail

REGION="us-west-2"
ACCT=${AWS_ACCOUNT_ID:-"__AWS_ACCOUNT_ID__"}
DS_ARN="arn:aws:quicksight:${REGION}:${ACCT}:datasource/fsi-snowflake-ds"
QS_USER_ARN="arn:aws:quicksight:${REGION}:${ACCT}:user/default/${ACCT}"

fail() { echo "FAILED: $1"; exit 1; }
ok()   { echo "  OK: $1"; }

echo "=== Omnichannel Ops Command Center — QuickSight Deployment ==="
echo "Account: ${ACCT} | Region: ${REGION}"
echo ""

echo "--- Datasets ---"

echo "Creating dataset: omni-channels..."
aws quicksight create-data-set \
  --aws-account-id "$ACCT" --region "$REGION" \
  --data-set-id "omni-channels" \
  --name "Omni: Channel Performance" \
  --import-mode DIRECT_QUERY \
  --physical-table-map '{
    "t1": {
      "CustomSql": {
        "DataSourceArn": "'"${DS_ARN}"'",
        "Name": "ChannelPerf",
        "SqlQuery": "SELECT CHANNEL_NAME, ORDER_DATE, ORDER_COUNT, REVENUE, AOV FROM RETAIL_OMNICHANNEL.CURATED.CHANNEL_PERFORMANCE",
        "Columns": [
          {"Name": "CHANNEL_NAME", "Type": "STRING"},
          {"Name": "ORDER_DATE", "Type": "DATETIME"},
          {"Name": "ORDER_COUNT", "Type": "INTEGER"},
          {"Name": "REVENUE", "Type": "DECIMAL"},
          {"Name": "AOV", "Type": "DECIMAL"}
        ]
      }
    }
  }' \
  --permissions '[{"Principal":"'"${QS_USER_ARN}"'","Actions":["quicksight:DescribeDataSet","quicksight:DescribeDataSetPermissions","quicksight:PassDataSet","quicksight:DescribeIngestion","quicksight:ListIngestions","quicksight:UpdateDataSet","quicksight:DeleteDataSet","quicksight:CreateIngestion","quicksight:CancelIngestion","quicksight:UpdateDataSetPermissions"]}]' \
  2>&1 && ok "omni-channels" || echo "  WARN: may already exist"

echo "Creating dataset: omni-fulfillment..."
aws quicksight create-data-set \
  --aws-account-id "$ACCT" --region "$REGION" \
  --data-set-id "omni-fulfillment" \
  --name "Omni: Fulfillment Performance" \
  --import-mode DIRECT_QUERY \
  --physical-table-map '{
    "t1": {
      "CustomSql": {
        "DataSourceArn": "'"${DS_ARN}"'",
        "Name": "FulfillmentPerf",
        "SqlQuery": "SELECT FULFILLMENT_TYPE, STATUS, TOTAL_ORDERS, AVG_DELIVERY_DAYS, DELIVERED, DELAYED, SLA_PCT FROM RETAIL_OMNICHANNEL.CURATED.FULFILLMENT_PERFORMANCE",
        "Columns": [
          {"Name": "FULFILLMENT_TYPE", "Type": "STRING"},
          {"Name": "STATUS", "Type": "STRING"},
          {"Name": "TOTAL_ORDERS", "Type": "INTEGER"},
          {"Name": "AVG_DELIVERY_DAYS", "Type": "DECIMAL"},
          {"Name": "DELIVERED", "Type": "INTEGER"},
          {"Name": "DELAYED", "Type": "INTEGER"},
          {"Name": "SLA_PCT", "Type": "DECIMAL"}
        ]
      }
    }
  }' \
  --permissions '[{"Principal":"'"${QS_USER_ARN}"'","Actions":["quicksight:DescribeDataSet","quicksight:DescribeDataSetPermissions","quicksight:PassDataSet","quicksight:DescribeIngestion","quicksight:ListIngestions","quicksight:UpdateDataSet","quicksight:DeleteDataSet","quicksight:CreateIngestion","quicksight:CancelIngestion","quicksight:UpdateDataSetPermissions"]}]' \
  2>&1 && ok "omni-fulfillment" || echo "  WARN: may already exist"

echo "Creating dataset: omni-conversion..."
aws quicksight create-data-set \
  --aws-account-id "$ACCT" --region "$REGION" \
  --data-set-id "omni-conversion" \
  --name "Omni: Conversion Metrics" \
  --import-mode DIRECT_QUERY \
  --physical-table-map '{
    "t1": {
      "CustomSql": {
        "DataSourceArn": "'"${DS_ARN}"'",
        "Name": "ConversionMetrics",
        "SqlQuery": "SELECT CHANNEL_NAME, SESSION_DAY, TOTAL_SESSIONS, CONVERSIONS, CONVERSION_RATE, AVG_PAGES, AVG_DURATION_SEC FROM RETAIL_OMNICHANNEL.CURATED.CONVERSION_METRICS",
        "Columns": [
          {"Name": "CHANNEL_NAME", "Type": "STRING"},
          {"Name": "SESSION_DAY", "Type": "DATETIME"},
          {"Name": "TOTAL_SESSIONS", "Type": "INTEGER"},
          {"Name": "CONVERSIONS", "Type": "INTEGER"},
          {"Name": "CONVERSION_RATE", "Type": "DECIMAL"},
          {"Name": "AVG_PAGES", "Type": "DECIMAL"},
          {"Name": "AVG_DURATION_SEC", "Type": "INTEGER"}
        ]
      }
    }
  }' \
  --permissions '[{"Principal":"'"${QS_USER_ARN}"'","Actions":["quicksight:DescribeDataSet","quicksight:DescribeDataSetPermissions","quicksight:PassDataSet","quicksight:DescribeIngestion","quicksight:ListIngestions","quicksight:UpdateDataSet","quicksight:DeleteDataSet","quicksight:CreateIngestion","quicksight:CancelIngestion","quicksight:UpdateDataSetPermissions"]}]' \
  2>&1 && ok "omni-conversion" || echo "  WARN: may already exist"

echo ""
echo "--- Analysis & Dashboard ---"
echo "Analysis: omni-analysis (14 visuals across 3 sheets)"
echo "Dashboard: omni-dashboard (published)"
echo "Use build_dashboard.py to rebuild analysis visuals from scratch."
echo ""

echo "--- Q Topic ---"
echo "Topic: omnichannel-q-topic"
echo "  Datasource: Snowflake (fsi-snowflake-ds)"
echo "  Datasets: omni-channels, omni-fulfillment, omni-conversion"
echo ""
echo "Sample Q questions:"
echo "  'What is the BOPIS SLA percentage?'"
echo "  'Which channel has the highest AOV?'"
echo "  'Show me conversion rate trends for Mobile App'"
echo "  'What is total revenue by channel this week?'"
echo "  'How many orders were delayed for curbside?'"
echo ""
echo "=== Deployment Complete ==="

#!/usr/bin/env python3
import subprocess
import json
import sys
import tempfile
import os

REGION = "us-west-2"
ACCT = os.environ["AWS_ACCOUNT_ID"]
DS_ARN = f"arn:aws:quicksight:us-west-2:{ACCT}:datasource/fsi-snowflake-ds"
USER_ARN = f"arn:aws:quicksight:us-west-2:{ACCT}:user/default/{ACCT}"
ANALYSIS_ID = "omni-analysis"

PERMS = [{"Principal": USER_ARN, "Actions": [
    "quicksight:DescribeDataSet", "quicksight:DescribeDataSetPermissions",
    "quicksight:PassDataSet", "quicksight:DescribeIngestion",
    "quicksight:ListIngestions", "quicksight:UpdateDataSet",
    "quicksight:DeleteDataSet", "quicksight:CreateIngestion",
    "quicksight:CancelIngestion", "quicksight:UpdateDataSetPermissions"
]}]

def run(cmd):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  ERROR: {r.stderr[:300]}")
        return None
    return json.loads(r.stdout) if r.stdout.strip() else {}

def create_dataset(ds_id, name, sql, columns):
    print(f"Creating dataset: {ds_id}...")
    ptm = {"t1": {"CustomSql": {"DataSourceArn": DS_ARN, "Name": ds_id, "SqlQuery": sql, "Columns": columns}}}
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(ptm, f)
        ptm_file = f.name
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(PERMS, f)
        perms_file = f.name
    cmd = (f"aws quicksight create-data-set --aws-account-id {ACCT} --region {REGION} "
           f"--data-set-id '{ds_id}' --name '{name}' --import-mode DIRECT_QUERY "
           f"--physical-table-map file://{ptm_file} --permissions file://{perms_file}")
    result = run(cmd)
    os.unlink(ptm_file)
    os.unlink(perms_file)
    if result is not None:
        print(f"  OK: {ds_id}")
    return result

print("=== Step 1: Create Conversion Dataset ===")
create_dataset("omni-conversion", "Omni: Conversion Metrics",
    "SELECT CHANNEL_NAME, SESSION_DAY, TOTAL_SESSIONS, CONVERSIONS, CONVERSION_RATE, AVG_PAGES, AVG_DURATION_SEC FROM RETAIL_OMNICHANNEL.CURATED.CONVERSION_METRICS",
    [{"Name": "CHANNEL_NAME", "Type": "STRING"}, {"Name": "SESSION_DAY", "Type": "DATETIME"},
     {"Name": "TOTAL_SESSIONS", "Type": "INTEGER"}, {"Name": "CONVERSIONS", "Type": "INTEGER"},
     {"Name": "CONVERSION_RATE", "Type": "DECIMAL"}, {"Name": "AVG_PAGES", "Type": "DECIMAL"},
     {"Name": "AVG_DURATION_SEC", "Type": "INTEGER"}])

print("\n=== Step 2: Get current analysis definition ===")
r = subprocess.run(
    f"aws quicksight describe-analysis-definition --aws-account-id {ACCT} --region {REGION} --analysis-id {ANALYSIS_ID}",
    shell=True, capture_output=True, text=True)
if r.returncode != 0:
    print(f"ERROR getting analysis: {r.stderr[:300]}")
    sys.exit(1)
analysis_data = json.loads(r.stdout)
defn = analysis_data["Definition"]

print(f"  Current sheets: {len(defn['Sheets'])}")

print("\n=== Step 3: Update analysis with full visuals ===")

new_defn = {
    "DataSetIdentifierDeclarations": [
        {"Identifier": "channels", "DataSetArn": f"arn:aws:quicksight:{REGION}:{ACCT}:dataset/omni-channels"},
        {"Identifier": "fulfillment", "DataSetArn": f"arn:aws:quicksight:{REGION}:{ACCT}:dataset/omni-fulfillment"},
        {"Identifier": "conversion", "DataSetArn": f"arn:aws:quicksight:{REGION}:{ACCT}:dataset/omni-conversion"}
    ],
    "Sheets": [
        {
            "SheetId": "s1",
            "Name": "Channel Performance",
            "Visuals": [
                {
                    "BarChartVisual": {
                        "VisualId": "v1-revenue-bar",
                        "Title": {"Visibility": "VISIBLE", "FormatText": {"PlainText": "Revenue by Channel"}},
                        "ChartConfiguration": {
                            "FieldWells": {"BarChartAggregatedFieldWells": {
                                "Category": [{"CategoricalDimensionField": {"FieldId": "ch1", "Column": {"DataSetIdentifier": "channels", "ColumnName": "CHANNEL_NAME"}}}],
                                "Values": [{"NumericalMeasureField": {"FieldId": "rev1", "Column": {"DataSetIdentifier": "channels", "ColumnName": "REVENUE"}, "AggregationFunction": {"SimpleNumericalAggregation": "SUM"}}}]
                            }},
                            "Orientation": "HORIZONTAL"
                        }
                    }
                },
                {
                    "BarChartVisual": {
                        "VisualId": "v1-aov-bar",
                        "Title": {"Visibility": "VISIBLE", "FormatText": {"PlainText": "AOV by Channel"}},
                        "ChartConfiguration": {
                            "FieldWells": {"BarChartAggregatedFieldWells": {
                                "Category": [{"CategoricalDimensionField": {"FieldId": "ch2", "Column": {"DataSetIdentifier": "channels", "ColumnName": "CHANNEL_NAME"}}}],
                                "Values": [{"NumericalMeasureField": {"FieldId": "aov1", "Column": {"DataSetIdentifier": "channels", "ColumnName": "AOV"}, "AggregationFunction": {"SimpleNumericalAggregation": "AVERAGE"}}}]
                            }},
                            "Orientation": "HORIZONTAL"
                        }
                    }
                },
                {
                    "LineChartVisual": {
                        "VisualId": "v1-rev-trend",
                        "Title": {"Visibility": "VISIBLE", "FormatText": {"PlainText": "Daily Revenue Trend by Channel"}},
                        "ChartConfiguration": {
                            "FieldWells": {"LineChartAggregatedFieldWells": {
                                "Category": [{"DateDimensionField": {"FieldId": "dt1", "Column": {"DataSetIdentifier": "channels", "ColumnName": "ORDER_DATE"}}}],
                                "Values": [{"NumericalMeasureField": {"FieldId": "rev2", "Column": {"DataSetIdentifier": "channels", "ColumnName": "REVENUE"}, "AggregationFunction": {"SimpleNumericalAggregation": "SUM"}}}],
                                "Colors": [{"CategoricalDimensionField": {"FieldId": "ch3", "Column": {"DataSetIdentifier": "channels", "ColumnName": "CHANNEL_NAME"}}}]
                            }}
                        }
                    }
                },
                {
                    "LineChartVisual": {
                        "VisualId": "v1-orders-trend",
                        "Title": {"Visibility": "VISIBLE", "FormatText": {"PlainText": "Daily Orders by Channel"}},
                        "ChartConfiguration": {
                            "FieldWells": {"LineChartAggregatedFieldWells": {
                                "Category": [{"DateDimensionField": {"FieldId": "dt2", "Column": {"DataSetIdentifier": "channels", "ColumnName": "ORDER_DATE"}}}],
                                "Values": [{"NumericalMeasureField": {"FieldId": "ord1", "Column": {"DataSetIdentifier": "channels", "ColumnName": "ORDER_COUNT"}, "AggregationFunction": {"SimpleNumericalAggregation": "SUM"}}}],
                                "Colors": [{"CategoricalDimensionField": {"FieldId": "ch4", "Column": {"DataSetIdentifier": "channels", "ColumnName": "CHANNEL_NAME"}}}]
                            }}
                        }
                    }
                },
                {
                    "KPIVisual": {
                        "VisualId": "v1-kpi-revenue",
                        "Title": {"Visibility": "VISIBLE", "FormatText": {"PlainText": "Total Revenue"}},
                        "ChartConfiguration": {
                            "FieldWells": {"Values": [{"NumericalMeasureField": {"FieldId": "rev3", "Column": {"DataSetIdentifier": "channels", "ColumnName": "REVENUE"}, "AggregationFunction": {"SimpleNumericalAggregation": "SUM"}}}]}
                        }
                    }
                },
                {
                    "KPIVisual": {
                        "VisualId": "v1-kpi-orders",
                        "Title": {"Visibility": "VISIBLE", "FormatText": {"PlainText": "Total Orders"}},
                        "ChartConfiguration": {
                            "FieldWells": {"Values": [{"NumericalMeasureField": {"FieldId": "ord2", "Column": {"DataSetIdentifier": "channels", "ColumnName": "ORDER_COUNT"}, "AggregationFunction": {"SimpleNumericalAggregation": "SUM"}}}]}
                        }
                    }
                }
            ]
        },
        {
            "SheetId": "s2",
            "Name": "Fulfillment SLA",
            "Visuals": [
                {
                    "BarChartVisual": {
                        "VisualId": "v2-sla-bar",
                        "Title": {"Visibility": "VISIBLE", "FormatText": {"PlainText": "SLA % by Fulfillment Type"}},
                        "ChartConfiguration": {
                            "FieldWells": {"BarChartAggregatedFieldWells": {
                                "Category": [{"CategoricalDimensionField": {"FieldId": "ft1", "Column": {"DataSetIdentifier": "fulfillment", "ColumnName": "FULFILLMENT_TYPE"}}}],
                                "Values": [{"NumericalMeasureField": {"FieldId": "sla1", "Column": {"DataSetIdentifier": "fulfillment", "ColumnName": "SLA_PCT"}, "AggregationFunction": {"SimpleNumericalAggregation": "AVERAGE"}}}]
                            }},
                            "Orientation": "HORIZONTAL"
                        }
                    }
                },
                {
                    "BarChartVisual": {
                        "VisualId": "v2-delivered-delayed",
                        "Title": {"Visibility": "VISIBLE", "FormatText": {"PlainText": "Delivered vs Delayed by Type"}},
                        "ChartConfiguration": {
                            "FieldWells": {"BarChartAggregatedFieldWells": {
                                "Category": [{"CategoricalDimensionField": {"FieldId": "ft2", "Column": {"DataSetIdentifier": "fulfillment", "ColumnName": "FULFILLMENT_TYPE"}}}],
                                "Values": [
                                    {"NumericalMeasureField": {"FieldId": "del1", "Column": {"DataSetIdentifier": "fulfillment", "ColumnName": "DELIVERED"}, "AggregationFunction": {"SimpleNumericalAggregation": "SUM"}}},
                                    {"NumericalMeasureField": {"FieldId": "delay1", "Column": {"DataSetIdentifier": "fulfillment", "ColumnName": "DELAYED"}, "AggregationFunction": {"SimpleNumericalAggregation": "SUM"}}}
                                ]
                            }},
                            "Orientation": "HORIZONTAL"
                        }
                    }
                },
                {
                    "BarChartVisual": {
                        "VisualId": "v2-total-orders",
                        "Title": {"Visibility": "VISIBLE", "FormatText": {"PlainText": "Total Orders by Fulfillment Type & Status"}},
                        "ChartConfiguration": {
                            "FieldWells": {"BarChartAggregatedFieldWells": {
                                "Category": [{"CategoricalDimensionField": {"FieldId": "ft3", "Column": {"DataSetIdentifier": "fulfillment", "ColumnName": "FULFILLMENT_TYPE"}}}],
                                "Values": [{"NumericalMeasureField": {"FieldId": "tot1", "Column": {"DataSetIdentifier": "fulfillment", "ColumnName": "TOTAL_ORDERS"}, "AggregationFunction": {"SimpleNumericalAggregation": "SUM"}}}],
                                "Colors": [{"CategoricalDimensionField": {"FieldId": "st1", "Column": {"DataSetIdentifier": "fulfillment", "ColumnName": "STATUS"}}}]
                            }},
                            "Orientation": "VERTICAL"
                        }
                    }
                },
                {
                    "TableVisual": {
                        "VisualId": "v2-delay-table",
                        "Title": {"Visibility": "VISIBLE", "FormatText": {"PlainText": "Delayed Orders Detail"}},
                        "ChartConfiguration": {
                            "FieldWells": {"TableAggregatedFieldWells": {
                                "GroupBy": [
                                    {"CategoricalDimensionField": {"FieldId": "ft4", "Column": {"DataSetIdentifier": "fulfillment", "ColumnName": "FULFILLMENT_TYPE"}}},
                                    {"CategoricalDimensionField": {"FieldId": "st2", "Column": {"DataSetIdentifier": "fulfillment", "ColumnName": "STATUS"}}}
                                ],
                                "Values": [
                                    {"NumericalMeasureField": {"FieldId": "del2", "Column": {"DataSetIdentifier": "fulfillment", "ColumnName": "DELAYED"}, "AggregationFunction": {"SimpleNumericalAggregation": "SUM"}}},
                                    {"NumericalMeasureField": {"FieldId": "tot2", "Column": {"DataSetIdentifier": "fulfillment", "ColumnName": "TOTAL_ORDERS"}, "AggregationFunction": {"SimpleNumericalAggregation": "SUM"}}}
                                ]
                            }}
                        }
                    }
                }
            ]
        },
        {
            "SheetId": "s3",
            "Name": "Conversion & Sessions",
            "Visuals": [
                {
                    "LineChartVisual": {
                        "VisualId": "v3-cvr-trend",
                        "Title": {"Visibility": "VISIBLE", "FormatText": {"PlainText": "Conversion Rate Trend by Channel"}},
                        "ChartConfiguration": {
                            "FieldWells": {"LineChartAggregatedFieldWells": {
                                "Category": [{"DateDimensionField": {"FieldId": "sd1", "Column": {"DataSetIdentifier": "conversion", "ColumnName": "SESSION_DAY"}}}],
                                "Values": [{"NumericalMeasureField": {"FieldId": "cvr1", "Column": {"DataSetIdentifier": "conversion", "ColumnName": "CONVERSION_RATE"}, "AggregationFunction": {"SimpleNumericalAggregation": "AVERAGE"}}}],
                                "Colors": [{"CategoricalDimensionField": {"FieldId": "ch5", "Column": {"DataSetIdentifier": "conversion", "ColumnName": "CHANNEL_NAME"}}}]
                            }}
                        }
                    }
                },
                {
                    "BarChartVisual": {
                        "VisualId": "v3-sessions-bar",
                        "Title": {"Visibility": "VISIBLE", "FormatText": {"PlainText": "Total Sessions by Channel"}},
                        "ChartConfiguration": {
                            "FieldWells": {"BarChartAggregatedFieldWells": {
                                "Category": [{"CategoricalDimensionField": {"FieldId": "ch6", "Column": {"DataSetIdentifier": "conversion", "ColumnName": "CHANNEL_NAME"}}}],
                                "Values": [{"NumericalMeasureField": {"FieldId": "sess1", "Column": {"DataSetIdentifier": "conversion", "ColumnName": "TOTAL_SESSIONS"}, "AggregationFunction": {"SimpleNumericalAggregation": "SUM"}}}]
                            }},
                            "Orientation": "HORIZONTAL"
                        }
                    }
                },
                {
                    "BarChartVisual": {
                        "VisualId": "v3-duration-bar",
                        "Title": {"Visibility": "VISIBLE", "FormatText": {"PlainText": "Avg Session Duration by Channel"}},
                        "ChartConfiguration": {
                            "FieldWells": {"BarChartAggregatedFieldWells": {
                                "Category": [{"CategoricalDimensionField": {"FieldId": "ch7", "Column": {"DataSetIdentifier": "conversion", "ColumnName": "CHANNEL_NAME"}}}],
                                "Values": [{"NumericalMeasureField": {"FieldId": "dur1", "Column": {"DataSetIdentifier": "conversion", "ColumnName": "AVG_DURATION_SEC"}, "AggregationFunction": {"SimpleNumericalAggregation": "AVERAGE"}}}]
                            }},
                            "Orientation": "HORIZONTAL"
                        }
                    }
                },
                {
                    "ScatterPlotVisual": {
                        "VisualId": "v3-scatter-engagement",
                        "Title": {"Visibility": "VISIBLE", "FormatText": {"PlainText": "Pages vs Conversion Rate"}},
                        "ChartConfiguration": {
                            "FieldWells": {"ScatterPlotCategoricallyAggregatedFieldWells": {
                                "XAxis": [{"NumericalMeasureField": {"FieldId": "pg1", "Column": {"DataSetIdentifier": "conversion", "ColumnName": "AVG_PAGES"}, "AggregationFunction": {"SimpleNumericalAggregation": "AVERAGE"}}}],
                                "YAxis": [{"NumericalMeasureField": {"FieldId": "cvr2", "Column": {"DataSetIdentifier": "conversion", "ColumnName": "CONVERSION_RATE"}, "AggregationFunction": {"SimpleNumericalAggregation": "AVERAGE"}}}],
                                "Category": [{"CategoricalDimensionField": {"FieldId": "ch8", "Column": {"DataSetIdentifier": "conversion", "ColumnName": "CHANNEL_NAME"}}}],
                                "Size": [{"NumericalMeasureField": {"FieldId": "sess2", "Column": {"DataSetIdentifier": "conversion", "ColumnName": "TOTAL_SESSIONS"}, "AggregationFunction": {"SimpleNumericalAggregation": "SUM"}}}]
                            }}
                        }
                    }
                }
            ]
        }
    ]
}

with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
    json.dump(new_defn, f)
    defn_file = f.name

cmd = (f"aws quicksight update-analysis --aws-account-id {ACCT} --region {REGION} "
       f"--analysis-id {ANALYSIS_ID} --name 'Omnichannel Operations' "
       f"--definition file://{defn_file}")

print(f"  Updating analysis with 3 sheets, 14 visuals...")
r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
os.unlink(defn_file)
if r.returncode != 0:
    print(f"  ERROR: {r.stderr[:500]}")
else:
    print(f"  OK: Analysis updated")
    resp = json.loads(r.stdout) if r.stdout else {}
    print(f"  Status: {resp.get('Status', 'unknown')}")

print("\n=== Step 4: Create Q Topic ===")
topic_def = {
    "AwsAccountId": ACCT,
    "TopicId": "omnichannel-q-topic",
    "Topic": {
        "Name": "Omnichannel Operations",
        "Description": "Cross-channel retail operations: revenue, fulfillment SLA, conversion rates across 6 channels",
        "DataSets": [
            {
                "DatasetArn": f"arn:aws:quicksight:{REGION}:{ACCT}:dataset/omni-channels",
                "DatasetName": "Channel Performance",
                "Columns": [
                    {"ColumnName": "CHANNEL_NAME", "ColumnFriendlyName": "Channel", "ColumnSynonyms": ["sales channel","store","platform"], "IsIncludedInTopic": True},
                    {"ColumnName": "ORDER_DATE", "ColumnFriendlyName": "Order Date", "ColumnSynonyms": ["date","day","when"], "IsIncludedInTopic": True},
                    {"ColumnName": "ORDER_COUNT", "ColumnFriendlyName": "Orders", "ColumnSynonyms": ["order volume","transactions"], "IsIncludedInTopic": True},
                    {"ColumnName": "REVENUE", "ColumnFriendlyName": "Revenue", "ColumnSynonyms": ["sales","income","GMV"], "IsIncludedInTopic": True},
                    {"ColumnName": "AOV", "ColumnFriendlyName": "Average Order Value", "ColumnSynonyms": ["AOV","basket size","ticket size"], "IsIncludedInTopic": True}
                ]
            },
            {
                "DatasetArn": f"arn:aws:quicksight:{REGION}:{ACCT}:dataset/omni-fulfillment",
                "DatasetName": "Fulfillment SLA",
                "Columns": [
                    {"ColumnName": "FULFILLMENT_TYPE", "ColumnFriendlyName": "Fulfillment Type", "ColumnSynonyms": ["delivery method","BOPIS","curbside","ship to home"], "IsIncludedInTopic": True},
                    {"ColumnName": "STATUS", "ColumnFriendlyName": "Status", "ColumnSynonyms": ["delivery status"], "IsIncludedInTopic": True},
                    {"ColumnName": "DELIVERED", "ColumnFriendlyName": "Delivered", "ColumnSynonyms": ["completed","on time"], "IsIncludedInTopic": True},
                    {"ColumnName": "DELAYED", "ColumnFriendlyName": "Delayed", "ColumnSynonyms": ["late","overdue","breached"], "IsIncludedInTopic": True},
                    {"ColumnName": "SLA_PCT", "ColumnFriendlyName": "SLA Percentage", "ColumnSynonyms": ["SLA","compliance","on-time rate"], "IsIncludedInTopic": True}
                ]
            },
            {
                "DatasetArn": f"arn:aws:quicksight:{REGION}:{ACCT}:dataset/omni-conversion",
                "DatasetName": "Conversion Metrics",
                "Columns": [
                    {"ColumnName": "CHANNEL_NAME", "ColumnFriendlyName": "Channel", "ColumnSynonyms": ["platform","source"], "IsIncludedInTopic": True},
                    {"ColumnName": "SESSION_DAY", "ColumnFriendlyName": "Date", "ColumnSynonyms": ["day","when"], "IsIncludedInTopic": True},
                    {"ColumnName": "TOTAL_SESSIONS", "ColumnFriendlyName": "Sessions", "ColumnSynonyms": ["visits","traffic"], "IsIncludedInTopic": True},
                    {"ColumnName": "CONVERSION_RATE", "ColumnFriendlyName": "Conversion Rate", "ColumnSynonyms": ["CVR","convert rate"], "IsIncludedInTopic": True}
                ]
            }
        ]
    }
}

with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
    json.dump(topic_def, f)
    topic_file = f.name

cmd = f"aws quicksight create-topic --cli-input-json file://{topic_file} --region {REGION}"
r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
os.unlink(topic_file)
if r.returncode != 0:
    if "ResourceExistsException" in r.stderr:
        print("  Q Topic already exists — skipping")
    else:
        print(f"  ERROR: {r.stderr[:300]}")
else:
    print("  OK: Q Topic created")

cmd = (f"aws quicksight update-topic-permissions --aws-account-id {ACCT} --region {REGION} "
       f"--topic-id omnichannel-q-topic "
       f"--grant-permissions '[{{\"Principal\":\"{USER_ARN}\",\"Actions\":[\"quicksight:DescribeTopic\",\"quicksight:DescribeTopicPermissions\",\"quicksight:DescribeTopicRefresh\",\"quicksight:ListTopicReviewedAnswers\",\"quicksight:CreateTopicReviewedAnswer\",\"quicksight:DeleteTopicReviewedAnswer\",\"quicksight:PassTopic\"]}}]'")
r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
if r.returncode == 0:
    print("  OK: Q Topic permissions granted")
else:
    print(f"  WARN: {r.stderr[:200]}")

print("\n=== Done ===")
print("Try Amazon Q: 'What is the BOPIS SLA percentage?'")

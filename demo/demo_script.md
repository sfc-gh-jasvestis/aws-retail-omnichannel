# Singapore Omnichannel Fulfilment Operations

**Singapore - Omnichannel Retail**
Use case: Late orders, fulfilment disruptions and picker capacity risk

> Operations monitoring for 40 fulfilment nodes of Sagaseed Retail, a fictional Singapore omnichannel retailer, across Jurong East, Tampines, Woodlands, Ang Mo Kio and Punggol: dynamic tables, a holdout-evaluated fulfilment-disruption classifier, a late-order forecast and grounded AI answers.

## Why Snowflake

- **Dynamic tables** reconcile orders placed, orders fulfilled on time, late orders, cancellations, disruption hours and cycle count timeliness from RAW node data, with checks in `run_core.py`
- **Fulfilment-disruption classification** gives a holdout-evaluated next-7-day probability per node
- **Late-order forecast** projects 14 days of network-wide late orders with prediction intervals, for picker capacity planning
- **Grounded AI**: the Cortex Agent (Analyst over a semantic view, plus Search over SOPs) shows its SQL and SOP citations
- **Live orders**: a native simulator (Snowflake only) or Amazon Data Firehose, S3 and Snowpipe (AWS build), then an alert and email

## What is built

| | |
|---|---|
| Dimension table | `RAW.STORES` (40 rows) |
| Fact table | `RAW.STORE_DAILY` (3,600 node-days, 90 days) |
| Curated layer | `CURATED.KPI_SUMMARY`, `PERFORMANCE_SUMMARY`, `CAUSE_SUMMARY`, `TREND_ANALYSIS` |
| ML | `ML.DISRUPTION_RISK_SCORES`, `ML.DISRUPTION_RISK_HOLDOUT_METRICS`, `ML.LATE_FORECAST`, `ML.FULFIL_HOURS_ANOMALIES` |

Planning areas: Jurong East, Tampines, Woodlands, Ang Mo Kio, Punggol.
Channels: Same-day delivery, Click and collect, Parcel locker pickup, Ship from store, Marketplace.
The retailer and its people are fictional; values are in SGD.

## KPI cards (live from `CURATED.KPI_SUMMARY`; no fallback values)

| Card | Value from the seeded data |
|---|---|
| On-Time Fulfilment Rate | 93.6% |
| Late Orders | 86,020 |
| Fulfilment Disruption Hours | 303 |
| Order Cancellation Rate | 2.1% |
| Disruption Node-Days | 106 |
| Net Sales (SGD M) | 129 |
| Orders Fulfilled On Time | 1,879,058 |
| Cycle Count On-Time Rate | 78.6% |
| Fulfilment Nodes Monitored | 40 |
| Staff Training Coverage | 44.3% |
| Staff Trainings Pending | 27 |

Values are synthetic. A rebuild reproduces them because the data is HASH-seeded; dates are relative to the build day.

## Demo flow

1. Executive Cockpit: KPIs, daily late orders, fulfilment disruption by cause, node table
2. Predictive: holdout metrics, risk bands, 14-day late-order forecast, order-to-ready time anomalies
3. Controls: cycle count on-time rate, staff training coverage and pending trainings, cycle count on-time rate against disruption hours, then generate the action memo
4. Live Orders: run `CALL APP.SIMULATE_ORDERS(20)` (Snowflake only) or `python aws/publish_orders.py --count 20` (AWS build). Then run `EXECUTE ALERT APP.LIVE_ORDER_ALERT` and show the alert log and email.
5. Ask AI: the Cortex Agent answers metric questions through the semantic view and cites SOPs from Cortex Search. The SQL is shown.
6. QuickSight (AWS build): the same Snowflake tables through DIRECT_QUERY
7. Architecture: both builds side by side

## Talking points

- 93.6% of orders are fulfilled within the promised time; the 86,020 late orders are where fulfilment operations time goes.
- The two mega-sale order surges (one in Tampines, one in Jurong East) cause the most disruption hours, 80 of 303, because they hit every node in the planning area at once. Among node-driven causes, packing station outages lead with 41 hours.
- Jurong East has the lowest on-time rate (93.2%) and its ship-from-store node STR-0030 has the most disruption hours (39); it is also the top risk score.
- The risk model is evaluated on a time-based holdout: precision 0.22 and recall 0.15 at 0.5, against a 0.125 base rate. It flags nodes at well above the base rate but misses most disruptions, so present it as triage, not a verdict.
- Mega-sale surge days are excluded from model training, because they are not node-driven.

## Business impact

Use only the sourced references in `README.md` (Business Impact).

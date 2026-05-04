# Demo Script: Omnichannel Ops Command Center
## 2.5-Minute Recorded Walkthrough — Fast-Paced Operations
**Format**: Screen recording with voiceover — **NO intro slide, start ON the app**
**Target**: Customer meeting / booth loop / social share
**Pre-requisites**: Data loaded, Streamlit deployed, QuickSight dashboard published

---

## The Story

A regional e-commerce retailer sells across 6 channels: In-Store, Web, Mobile App, Marketplace, Social Commerce, and Phone. Last night, Mobile App conversion dropped 18%. Three BOPIS locations breached their fulfillment SLA. The Ops Manager needs answers NOW — not tomorrow morning in a slide deck.

This isn't a dashboard. It's a command center. Clickstream JSON hits S3 every 30 seconds. Snowpipe auto-ingests. When SLA breaches are detected, Snowflake fires an SNS alert to the ops team's Slack channel. Every morning, Bedrock writes a one-page operations summary so the VP Digital doesn't have to read 6 channel reports.

Single-scroll layout. No tabs. No pages. Everything visible. Scroll down for the full operational picture.

---

## Two Personas

| Persona | Role | Tool | What they care about |
|---|---|---|---|
| **Ops Manager** | Real-time operations | Streamlit in Snowflake (single-scroll) | Live order feed, channel KPIs, conversion trends, SLA compliance, Bedrock briefing |
| **VP Digital** | Strategic channel decisions | Amazon QuickSight + Amazon Q | Channel revenue mix, AOV trends, fulfillment SLA by type, NLP: "What's BOPIS compliance this week?" |

---

## What's Built

| Layer | Component | Detail |
|---|---|---|
| **Ingest (AWS)** | Amazon S3 + Snowpipe | Clickstream JSON from web/mobile/social (500K sessions auto-ingested) |
| **Events (AWS)** | Amazon SNS | Inbound: Snowpipe trigger. Outbound: SLA breach alerts to ops team |
| **RAW** | 7 tables | CHANNELS (6), CUSTOMERS (5K), ORDERS (100K), ORDER_ITEMS (300K), FULFILLMENTS (100K), WEB_SESSIONS (500K), RETURN_POLICIES (30) |
| **CURATED** | 3 Dynamic Tables | CHANNEL_PERFORMANCE (orders/revenue by channel/day), FULFILLMENT_PERFORMANCE (SLA by type), CONVERSION_METRICS (conversion by channel/day) |
| **AI** | Bedrock via Cortex | Daily operations narrative generator |
| **ML** | FORECAST | 14-day order prediction per channel |
| **Consumption** | Streamlit | Single-scroll ops command center (7 sections) |
| | QuickSight | 2-sheet dashboard (Channel Performance + Fulfillment SLA) + Q Topic |

**Current data**: 100K orders | 500K web sessions | 100K fulfillments | 6 channels | 4 fulfillment types (ship-to-home, BOPIS, curbside, in-store)

---

## Pre-Recording Checklist

- [ ] Verify Dynamic Tables: `SHOW DYNAMIC TABLES IN DATABASE RETAIL_OMNICHANNEL` (all 3 ACTIVE)
- [ ] Open Streamlit: `RETAIL_OMNICHANNEL.APP.OMNICHANNEL_OPS_APP`
- [ ] Verify live order feed shows recent orders at top
- [ ] Verify conversion chart shows Mobile App decline
- [ ] Verify fulfillment SLA section shows at least one type below 85%
- [ ] Test "Generate Ops Summary" button — confirm Bedrock returns narrative
- [ ] Open QuickSight: https://us-west-2.quicksight.aws.amazon.com/
- [ ] Test Amazon Q: "What is the BOPIS SLA percentage?"
- [ ] Audio: quiet room, external mic
- [ ] Resolution: 1920x1080

---

## Script

**CRITICAL**: No intro slide. No architecture walkthrough. Open DIRECTLY on the Streamlit app. The pace is fast — 15 second segments. The viewer should feel like they're watching a live ops floor.

### [0:00–0:15] LIVE ORDER FEED (Show: Top of Streamlit app, already open)

> *"You're looking at a live command center. Top section — last 4 orders streaming in. SGD 287 from Mobile. SGD 145 from In-Store. SGD 412 from Web via BOPIS. Every order, every channel, real-time."*

**Screen**: Point to the 4 metric cards at the top showing latest orders.

---

### [0:15–0:35] CHANNEL KPIS (Show: Scroll slightly to Channel KPI cards)

> *"Six channels. In-Store leads revenue. Web is second. But look at Mobile — revenue is trailing. Scroll down to see why."*

**Screen**: Point to each channel metric card. Emphasize the Mobile decline.

---

### [0:35–1:05] CONVERSION TREND + ORDER VOLUME (Show: Side-by-side Plotly charts)

> *"Left chart — daily conversion rate by channel. Look for the channel with the steepest decline — that's the one ops needs to investigate. If Mobile drops, that's significant: Mobile App customers tend to have higher AOV. Right chart — order volume stacked by channel. Watch for mix shifts — if volume is moving from high-AOV channels to low-AOV, total revenue suffers even if order count holds."*

**Screen**: Point to the conversion line chart, then the stacked area chart.

---

### [1:05–1:35] FULFILLMENT SLA (Show: Scroll to SLA progress bars)

> *"Fulfillment SLA — the operational heartbeat. Check each progress bar. Any type below 85% needs attention. Look at the delayed counts — those are real orders with real customers waiting. In production, a Snowflake ALERT monitors these thresholds and fires an SNS notification to the ops team's Slack channel automatically. No manual checking required."*

**Screen**: Point to progress bars. Emphasize the Curbside bar being short of the target line.

---

### [1:35–2:05] DAILY BRIEFING — Bedrock (Show: Click "Generate Ops Summary")

> *"Every morning, one click. Bedrock reads yesterday's metrics and writes the briefing."*

**Action**: Click "Generate Ops Summary". Wait 3-5 seconds.

> *"Bedrock reads the metrics and writes a concise briefing — order volume, top channel, any SLA issues, and a recommendation. The exact content adapts to yesterday's actual data. Copy, paste into Slack, done."*

---

### [2:05–2:20] CHANNEL FORECAST (Show: Scroll to forecast chart)

> *"14-day order forecast by channel. Snowflake ML — no Python, no SageMaker. Volume spike expected next week across all channels. In-Store and Web lead the surge. The ops team needs to pre-position warehouse staff and ensure curbside capacity is restored before then."*

**Screen**: Point to the multi-line forecast chart.

---

### [2:20–2:30] CLOSE (Stay on: Forecast chart)

> *"Clickstream ingested in under 60 seconds. SLA thresholds monitored with SNS alerts. Bedrock wrote the morning briefing. ML says prepare for next week. That's the difference between a dashboard you check once a day — and a command center that runs your operations."*

---

## Key Demo Questions to Anticipate

1. **"How fast does clickstream data appear in the dashboard?"**
   → S3 landing to queryable in Snowflake: under 60 seconds with Snowpipe auto-ingest. Dynamic Tables add 5 minutes for aggregation. Total latency: ~6 minutes.

2. **"What triggered the Mobile conversion drop?"**
   → In the demo, it's synthetic data showing a pattern consistent with an app crash (session count drops to near-zero between 2-4am, then partially recovers). In production, you'd correlate with mobile APM tools (New Relic, Datadog).

3. **"Can the SNS alert trigger automated remediation?"**
   → Yes. SNS → EventBridge → Lambda or Step Functions. Example: automatically reroute BOPIS orders to alternative stores when SLA breaches at a specific location.

4. **"Why single-scroll instead of tabs?"**
   → Ops managers need the full picture visible at once. Tabs hide information. A command center shows everything — you scroll, not click. Inspired by airport operations centers and trading floors.

5. **"How does this handle peak events like 11.11 or Black Friday?"**
   → ML FORECAST predicts volume spikes 14 days ahead. Dynamic Tables scale automatically with warehouse size. Snowpipe handles burst ingestion. The architecture is elastic — no capacity planning needed.

6. **"Why no Cortex Search in this demo?"**
   → Ops managers don't search documents — they act on data. Search is for the Category Manager (Merchandising demo) and the Compliance Officer (FSI demos). Each demo uses only the capabilities that fit the persona.

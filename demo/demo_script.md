# Demo Script: Omnichannel Ops Command Center
## 3.5-Minute Recorded Walkthrough — Fast-Paced Operations
**Format**: Screen recording with voiceover — **NO intro slide, start ON the app**
**Target**: Customer meeting / booth loop / social share
**Pre-requisites**: Data loaded, Streamlit deployed, QuickSight dashboard published

---

## The Story

A regional e-commerce retailer sells across 6 channels: In-Store, Web, Mobile App, Marketplace, Social Commerce, and Phone. This week, Mobile App revenue COLLAPSED — down 34% while Social Commerce exploded +86%. BOPIS fulfillment is running at 78% compliance, well below the 85% SLA target. Mobile conversion has crashed from 9% to under 4%. The Ops Manager needs answers NOW.

This isn't a dashboard. It's a command center. Clickstream JSON hits S3 every 30 seconds. Snowpipe auto-ingests. When SLA breaches are detected, Snowflake fires an SNS alert to the ops team's Slack channel. Every morning, Claude writes a one-page operations summary so the VP Digital doesn't have to read 6 channel reports.

Single-scroll layout. No tabs. No pages. Everything visible. Scroll down for the full operational picture.

---

## Two Personas

| Persona | Role | Tool | What they care about |
|---|---|---|---|
| **Ops Manager** | Real-time operations | Streamlit in Snowflake (single-scroll) | Live order feed, channel KPIs, WoW growth, conversion trends, SLA compliance, AI briefing |
| **VP Digital** | Strategic channel decisions | Amazon QuickSight + Amazon Q | Channel revenue mix, AOV trends, fulfillment SLA by type, NLP: "What's BOPIS compliance this week?" |

---

## What's Built

| Layer | Component | Detail |
|---|---|---|
| **Ingest (AWS)** | Amazon S3 + Snowpipe | Clickstream JSON from web/mobile/social (500K sessions auto-ingested) |
| **Events (AWS)** | Amazon SNS | Inbound: Snowpipe trigger. Outbound: SLA breach alerts to ops team |
| **RAW** | 6 tables | CHANNELS (6), CUSTOMERS (5K), ORDERS (100K), FULFILLMENTS (100K), WEB_SESSIONS (500K), RETURN_POLICIES (30) |
| **CURATED** | 3 Dynamic Tables | CHANNEL_PERFORMANCE (orders/revenue by channel/day), FULFILLMENT_PERFORMANCE (SLA by type), CONVERSION_METRICS (conversion by channel/day) |
| **AI** | Claude via Cortex | Daily operations narrative generator |
| **ML** | FORECAST | 14-day order prediction per channel |
| **Consumption** | Streamlit | Single-scroll ops command center (10 sections) |
| | QuickSight | 3-sheet dashboard (Channel Performance + Fulfillment SLA + Conversion) + Q Topic |

**Current data**: 100K orders | 500K web sessions | 100K fulfillments | 6 channels | 4 fulfillment types (ship-to-home, BOPIS, curbside, in-store)

---

## Pre-Recording Checklist

- [ ] Verify Dynamic Tables: `SHOW DYNAMIC TABLES IN DATABASE RETAIL_OMNICHANNEL` (all 3 ACTIVE)
- [ ] Open Streamlit: `RETAIL_OMNICHANNEL.APP.OMNICHANNEL_OPS_APP`
- [ ] Verify live order feed shows recent orders at top
- [ ] Verify WoW growth cards show Mobile at -34% (red, worst performer)
- [ ] Verify conversion chart shows Mobile App crashed to ~4% (was 9%)
- [ ] Verify fulfillment SLA section shows BOPIS at 78% (below 85% target)
- [ ] Test "Generate Ops Summary" button — confirm Claude returns narrative
- [ ] Open QuickSight: https://us-west-2.quicksight.aws.amazon.com/
- [ ] Test Amazon Q: "What is the BOPIS SLA percentage?"
- [ ] Audio: quiet room, external mic
- [ ] Resolution: 1920x1080

---

## Script

**CRITICAL**: No intro slide. No architecture walkthrough. Open DIRECTLY on the Streamlit app. The pace is fast — 15 second segments. The viewer should feel like they're watching a live ops floor.

**Narrative Arc**: Detection → Investigation → Impact → Action → Prediction

---

### [0:00–0:15] LIVE ORDER FEED (Show: Top of Streamlit app, already open)

> *"You're looking at a live command center. Top section — last 4 orders streaming in. $156 from Web. $299 from In-Store. $68 from Social Commerce. $216 from Marketplace. Notice the price spread — In-Store orders are 4x Social. That AOV gap is the story. Every order, every channel, real-time."*

**Screen**: Point to the 4 metric cards at the top showing latest orders.

---

### [0:15–0:35] CHANNEL KPIS (Show: Scroll slightly to Channel KPI cards)

> *"Six channels. Thirty-day revenue. In-Store dominates at 1.5 million — nearly 40% of total. Phone has the highest AOV at $394. But look at Mobile App — barely 270K. Under 7% of total revenue. For a retailer investing heavily in mobile UX, that's a crisis. Let's quantify it."*

**Screen**: Point to each channel metric card. Emphasize the Mobile number being lower.

---

### [0:35–0:55] REVENUE MIX (Show: Scroll to donut chart)

> *"Revenue mix tells the story. In-Store is nearly 38% of revenue. Web adds another 22%. Mobile App? Under 7%. That tiny sliver represents a channel that's supposed to be growing. But share alone doesn't tell us if it's getting worse. Let's look at the trend."*

**Screen**: Point to the donut chart slices. Emphasize Mobile's small share.

---

### [0:55–1:20] CONVERSION TREND + ORDER VOLUME (Show: Side-by-side Plotly charts)

> *"Left chart — daily conversion rate. Web is steady at 12%. Social Commerce around 9%. And Mobile App — look at that cliff. It was running 8-9%, then this week it crashed to under 4%. That's a 55% drop in conversion. Something broke. Right chart — daily orders. In-Store towers over everything. Mobile is a thin line at the bottom."*

**Screen**: Point to the conversion line chart, then the stacked area chart.

---

### [1:20–1:45] WEEK-OVER-WEEK GROWTH (Show: Scroll to WoW metric cards)

> *"Here's the smoking gun. Week-over-week revenue growth. Social Commerce — plus 86 percent. In-Store — plus 17. Web — plus 15. And Mobile App? MINUS 34 percent. Negative. While every other channel grows, Mobile is in freefall. This isn't a blip — it's a crisis requiring immediate investigation."*

**Screen**: Point to each WoW card. Pause on Mobile's -34%. The cards are sorted worst-to-best.

---

### [1:45–2:00] AOV TREND (Show: Scroll to grouped bar chart)

> *"Average order value confirms it. Phone leads at $394 — guided selling. In-Store at $315 — high-touch. Web at $211. And Mobile App? $149. Lowest by far. Combined with crashed conversion, that's the double hit: fewer buyers spending less per order. Revenue collapses."*

**Screen**: Point to the grouped bar chart. Mobile bars are visibly shorter.

---

### [2:00–2:25] FULFILLMENT SLA (Show: Scroll to SLA progress bars)

> *"Fulfillment SLA — the operational heartbeat. BOPIS: 78 percent. Below the 85% target. That's over 100 delayed orders — real customers who clicked 'Pick Up Today' and are still waiting. Curbside is borderline at 83%. Ship-to-home holds at 88%. In production, a Snowflake ALERT monitors these thresholds and fires an SNS notification to Slack automatically."*

**Screen**: Point to progress bars. Emphasize BOPIS bar well short of 85% target. Curbside borderline.

---

### [2:25–2:55] DAILY BRIEFING — Claude (Show: Click "Generate Ops Summary")

> *"Every morning, one click. Claude reads yesterday's metrics and writes the briefing."*

**Action**: Click "Generate Ops Summary". Wait 3-5 seconds.

> *"Claude reads the channel performance, identifies the top performer, flags the delayed fulfillments, and writes a one-paragraph summary with a recommendation. Copy, paste into Slack, the VP Digital has her morning brief without reading six reports."*

---

### [2:55–3:15] CHANNEL FORECAST (Show: Scroll to forecast chart)

> *"14-day order forecast by channel. Snowflake ML — no Python, no SageMaker. In-Store leads at 155 orders per day. Web at 132. And Mobile? Just 32. The model has already learned that Mobile is declining. If nothing changes, that gap widens every single day. The ops team needs to fix the mobile experience NOW."*

**Screen**: Point to the multi-line forecast chart.

---

### [3:15–3:30] VP PERSONA — QuickSight (Show: Switch to QuickSight tab)

> *"Different persona, different tool. The VP Digital opens QuickSight. Same data, strategic lens. Three sheets: channel performance with AOV trends, fulfillment SLA drill-down by week, and conversion funnel quality. She types into Amazon Q: 'What is the BOPIS SLA percentage this month?' — and gets an instant answer grounded in live data."*

**Screen**: Show QuickSight dashboard briefly. Type a Q question.

---

### [3:30–3:45] CLOSE (Stay on: QuickSight or cut back to Streamlit)

> *"Clickstream ingested in under 60 seconds. SLA thresholds monitored with SNS alerts. Claude wrote the morning briefing. ML says prepare for next week. WoW growth exposed Mobile's decline before it became a crisis. That's the difference between a dashboard you check once a day — and a command center that runs your operations."*

---

## QuickSight Dashboard Specifications

### Sheet 1: Channel Revenue Performance
| Visual | Type | Data |
|---|---|---|
| Total Revenue (30d) | KPI | SUM(REVENUE) from channel_performance |
| Total Orders (30d) | KPI | SUM(ORDER_COUNT) |
| Overall AOV | KPI | SUM(REVENUE)/SUM(ORDER_COUNT) |
| Revenue by Channel | Horizontal bar | CHANNEL_NAME vs SUM(REVENUE) |
| Daily Revenue Trend | Line chart | ORDER_DATE x-axis, REVENUE y-axis, color=CHANNEL_NAME |
| AOV by Channel | Bar chart | CHANNEL_NAME vs AVG(AOV) |

### Sheet 2: Fulfillment SLA Deep Dive
| Visual | Type | Data |
|---|---|---|
| SLA Gauge - BOPIS | Gauge (target: 85%) | SLA_PCT WHERE FULFILLMENT_TYPE='BOPIS' |
| SLA Gauge - Curbside | Gauge (target: 85%) | SLA_PCT WHERE FULFILLMENT_TYPE='CURBSIDE' |
| SLA Gauge - Ship to Home | Gauge (target: 85%) | SLA_PCT WHERE FULFILLMENT_TYPE='SHIP_TO_HOME' |
| SLA Gauge - In-Store | Gauge (target: 85%) | SLA_PCT WHERE FULFILLMENT_TYPE='IN_STORE' |
| Weekly Delivery vs Delayed | Stacked bar | WEEK x-axis, DELIVERED+DELAYED y-axis, color=STATUS |
| Delayed Orders Table | Table | FULFILLMENT_TYPE, WEEK, DELAYED (sorted desc) |

### Sheet 3: Conversion & Session Quality
| Visual | Type | Data |
|---|---|---|
| Conversion Rate Trend | Line chart | SESSION_DAY x-axis, CONVERSION_RATE y-axis, color=CHANNEL_NAME |
| Sessions by Channel | Bar chart | CHANNEL_NAME vs SUM(TOTAL_SESSIONS) |
| Engagement Scatter | Scatter | AVG_PAGES x-axis, CONVERSION_RATE y-axis, size=TOTAL_SESSIONS |
| Avg Session Duration | Bar chart | CHANNEL_NAME vs AVG(AVG_DURATION_SEC) |

### Amazon Q Topic Sample Questions
1. "What is the BOPIS SLA percentage?"
2. "Which channel has the highest AOV?"
3. "Show me conversion rate trends for Mobile App"
4. "What is total revenue by channel this week?"
5. "How many orders were delayed for curbside?"

---

## Key Demo Questions to Anticipate

1. **"How fast does clickstream data appear in the dashboard?"**
   → S3 landing to queryable in Snowflake: under 60 seconds with Snowpipe auto-ingest. Dynamic Tables add 5 minutes for aggregation. Total latency: ~6 minutes.

2. **"What triggered the Mobile conversion drop?"**
   → The data shows Mobile conversion crashed from 8.7% to 3.8% in one week — a 55% decline. Revenue is down 34% WoW. In production, you'd correlate with mobile APM tools (New Relic, Datadog) to identify root cause — app crash, slow load times, broken checkout flow, or a bad app store update.

3. **"Can the SNS alert trigger automated remediation?"**
   → Yes. SNS → EventBridge → Lambda or Step Functions. Example: automatically reroute BOPIS orders to alternative stores when SLA breaches at a specific location.

4. **"Why single-scroll instead of tabs?"**
   → Ops managers need the full picture visible at once. Tabs hide information. A command center shows everything — you scroll, not click. Inspired by airport operations centers and trading floors.

5. **"How does this handle peak events like 11.11 or Black Friday?"**
   → ML FORECAST predicts volume spikes 14 days ahead. Dynamic Tables scale automatically with warehouse size. Snowpipe handles burst ingestion. The architecture is elastic — no capacity planning needed.

6. **"Why Claude via Cortex instead of direct Bedrock?"**
   → Cortex COMPLETE keeps data within Snowflake's security perimeter. No data leaves to external APIs. The prompt includes only aggregated metrics, not raw PII. Same model quality, better governance.

7. **"What's the difference between the Streamlit and QuickSight views?"**
   → Streamlit = ops-speed, real-time, single-scroll for the person running operations. QuickSight = strategic, drill-down, self-service for the exec who wants to explore trends at their own pace. Same data, different consumption patterns.

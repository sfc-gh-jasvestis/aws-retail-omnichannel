# Demo Script: Omnichannel Ops Command Center
## 2.5-Minute Recorded Walkthrough — Fast-Paced Ops
**Format**: Screen recording with voiceover — NO intro slide, start ON the app
**App**: Single-scroll dashboard, no tabs

---

## The Story

An e-commerce operation across 6 channels. Clickstream JSON hits S3 every 30 seconds. Snowpipe auto-ingests. When fulfillment SLA breaches happen, SNS alerts the ops team. Every morning, Bedrock writes the daily briefing. This isn't a dashboard — it's a command center.

---

## Persona

| Persona | Tool | What they see |
|---|---|---|
| **Ops Manager** | Streamlit (single-scroll) | Live order feed, channel KPIs, conversion trends, SLA progress bars, Bedrock briefing |
| **VP Digital** | QuickSight + Amazon Q | Channel revenue, AOV, fulfillment SLA, NLP: "What's BOPIS compliance this week?" |

---

## Script

**IMPORTANT**: No intro slide. No architecture diagram. Start cold ON the app. Fast pace — 15-second segments.

### [0:00–0:15] LIVE FEED

**Show**: App is already open. Point to top section.

> "You're looking at live orders. Last 4 transactions streaming in. Mobile, Web, In-Store, Marketplace."

### [0:15–0:30] CHANNEL KPIS

**Show**: Scroll slightly to Channel KPI section

> "Six channels. In-Store leads revenue. Mobile conversion dropped 18% overnight — that's the one to watch."

### [0:30–1:00] CONVERSION + ORDERS CHARTS

**Show**: Point to side-by-side charts

> "Conversion rate by channel — Mobile fell off a cliff Tuesday. And on the right, daily orders stacked by channel. Total volume is up but it's all shifting to Web."

### [1:00–1:30] FULFILLMENT SLA

**Show**: Scroll to SLA progress bars

> "Fulfillment SLA. Ship-to-home: 82%. BOPIS: 91%. Curbside: 76% — that's below target. 340 delayed orders. The SNS alert already went to the ops channel 40 minutes ago."

### [1:30–2:00] DAILY BRIEFING — Bedrock

**Show**: Click "Generate Ops Summary" button

> "Every morning, one click. Bedrock writes yesterday's briefing."

**Wait for result**

> "4,200 orders. Mobile down 18%. 3 fulfillment SLA breaches. Recommendation: investigate mobile app crash logs, reroute curbside overflow. Done — share this with the team in Slack."

### [2:00–2:15] FORECAST

**Show**: Scroll to forecast chart

> "14-day order forecast by channel. Snowflake ML — no Python, no SageMaker. Volume spike expected next week."

### [2:15–2:30] CLOSE

> "That SLA alert fired 40 minutes ago. The ops team already rerouted. Bedrock wrote the briefing. Forecast says prepare for next week. That's the difference between a dashboard and a command center."

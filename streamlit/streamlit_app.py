import streamlit as st
import pandas as pd
import json
import plotly.express as px
from snowflake.snowpark.context import get_active_session

session = get_active_session()

st.set_page_config(page_title="Omnichannel Ops", layout="wide", page_icon="⚡")

st.markdown("""
<style>
.stMetric {border-left: 4px solid #667eea; padding-left: 12px;}
div[data-testid="stMetric"] label {font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em;}
</style>
""", unsafe_allow_html=True)

st.title("Omnichannel Operations Command Center")
st.caption("Real-time. Event-driven. Snowpipe + SNS + Bedrock. No tabs — scroll down for full ops view.")

recent_orders = session.sql("""
    SELECT ORDER_ID, CHANNEL_ID, TOTAL_AMOUNT, FULFILLMENT_TYPE, ORDER_DATE
    FROM RETAIL_OMNICHANNEL.RAW.ORDERS
    ORDER BY ORDER_DATE DESC, ORDER_ID DESC
    LIMIT 8
""").to_pandas()

st.markdown("### Live Order Feed")
cols = st.columns(4)
for i, (_, row) in enumerate(recent_orders.head(4).iterrows()):
    with cols[i]:
        ch_name = {"CH-01": "Store", "CH-02": "Web", "CH-03": "Mobile", "CH-04": "Mktplace", "CH-05": "Social", "CH-06": "Phone"}.get(row["CHANNEL_ID"], row["CHANNEL_ID"])
        st.metric(f"{row['ORDER_ID']}", f"${float(row['TOTAL_AMOUNT']):,.0f}", delta=f"{ch_name} | {row['FULFILLMENT_TYPE']}")

st.divider()

st.markdown("### Channel KPIs (Last 30 Days)")
channel_kpi = session.sql("""
    SELECT CHANNEL_NAME, SUM(ORDER_COUNT) AS ORDERS, ROUND(SUM(REVENUE), 0) AS REVENUE, ROUND(AVG(AOV), 2) AS AOV
    FROM RETAIL_OMNICHANNEL.CURATED.CHANNEL_PERFORMANCE
    WHERE ORDER_DATE >= DATEADD('day', -30, CURRENT_DATE())
    GROUP BY CHANNEL_NAME ORDER BY REVENUE DESC
""").to_pandas()

if not channel_kpi.empty:
    cols = st.columns(len(channel_kpi))
    for i, (_, row) in enumerate(channel_kpi.iterrows()):
        with cols[i]:
            st.metric(row["CHANNEL_NAME"], f"${float(row['REVENUE']):,.0f}", delta=f"{int(row['ORDERS'])} orders")

st.divider()

st.markdown("### Revenue Mix by Channel (Last 30 Days)")
if not channel_kpi.empty:
    channel_kpi["REVENUE"] = pd.to_numeric(channel_kpi["REVENUE"], errors="coerce")
    fig_pie = px.pie(channel_kpi, values="REVENUE", names="CHANNEL_NAME",
                     hole=0.4, title="Channel Revenue Share")
    fig_pie.update_traces(textposition='inside', textinfo='percent+label')
    fig_pie.update_layout(height=350, margin=dict(t=35, b=10), showlegend=False)
    st.plotly_chart(fig_pie, use_container_width=True)

st.divider()

col_l, col_r = st.columns(2)
with col_l:
    st.markdown("### Conversion Trend")
    conv_df = session.sql("""
        SELECT SESSION_DAY, CHANNEL_NAME, CONVERSION_RATE
        FROM RETAIL_OMNICHANNEL.CURATED.CONVERSION_METRICS
        WHERE SESSION_DAY >= DATEADD('day', -30, CURRENT_DATE())
        ORDER BY SESSION_DAY
    """).to_pandas()
    if not conv_df.empty:
        conv_df["CONVERSION_RATE"] = pd.to_numeric(conv_df["CONVERSION_RATE"], errors="coerce")
        fig = px.line(conv_df, x="SESSION_DAY", y="CONVERSION_RATE", color="CHANNEL_NAME", title="Daily Conversion Rate by Channel")
        fig.update_layout(height=350, margin=dict(t=35, b=10))
        st.plotly_chart(fig, use_container_width=True)

with col_r:
    st.markdown("### Orders by Channel (Area)")
    orders_df = session.sql("""
        SELECT ORDER_DATE, CHANNEL_NAME, ORDER_COUNT
        FROM RETAIL_OMNICHANNEL.CURATED.CHANNEL_PERFORMANCE
        WHERE ORDER_DATE >= DATEADD('day', -30, CURRENT_DATE())
        ORDER BY ORDER_DATE
    """).to_pandas()
    if not orders_df.empty:
        orders_df["ORDER_COUNT"] = pd.to_numeric(orders_df["ORDER_COUNT"], errors="coerce")
        fig2 = px.line(orders_df, x="ORDER_DATE", y="ORDER_COUNT", color="CHANNEL_NAME", title="Daily Orders by Channel")
        fig2.update_layout(height=350, margin=dict(t=35, b=10), yaxis_title="Orders")
        st.plotly_chart(fig2, use_container_width=True)

st.divider()

st.markdown("### Week-over-Week Channel Growth")
wow_df = session.sql("""
    SELECT CHANNEL_NAME,
        SUM(CASE WHEN ORDER_DATE BETWEEN DATEADD('day', -14, CURRENT_DATE()) AND DATEADD('day', -8, CURRENT_DATE()) THEN ORDER_COUNT END) AS PREV_WEEK_ORDERS,
        SUM(CASE WHEN ORDER_DATE >= DATEADD('day', -7, CURRENT_DATE()) THEN ORDER_COUNT END) AS THIS_WEEK_ORDERS,
        SUM(CASE WHEN ORDER_DATE BETWEEN DATEADD('day', -14, CURRENT_DATE()) AND DATEADD('day', -8, CURRENT_DATE()) THEN REVENUE END) AS PREV_WEEK_REV,
        SUM(CASE WHEN ORDER_DATE >= DATEADD('day', -7, CURRENT_DATE()) THEN REVENUE END) AS THIS_WEEK_REV
    FROM RETAIL_OMNICHANNEL.CURATED.CHANNEL_PERFORMANCE
    WHERE ORDER_DATE >= DATEADD('day', -14, CURRENT_DATE())
    GROUP BY CHANNEL_NAME ORDER BY CHANNEL_NAME
""").to_pandas()

if not wow_df.empty:
    for c in ["PREV_WEEK_ORDERS","THIS_WEEK_ORDERS","PREV_WEEK_REV","THIS_WEEK_REV"]:
        wow_df[c] = pd.to_numeric(wow_df[c], errors="coerce")
    wow_df["REV_CHANGE_PCT"] = ((wow_df["THIS_WEEK_REV"] - wow_df["PREV_WEEK_REV"]) / wow_df["PREV_WEEK_REV"] * 100).round(1)
    wow_df = wow_df.sort_values("REV_CHANGE_PCT", ascending=True)
    cols = st.columns(len(wow_df))
    for i, (_, row) in enumerate(wow_df.iterrows()):
        with cols[i]:
            pct = float(row["REV_CHANGE_PCT"]) if pd.notna(row["REV_CHANGE_PCT"]) else 0
            st.metric(row["CHANNEL_NAME"], f"{pct:+.1f}%", delta=f"{int(row['THIS_WEEK_ORDERS'])} orders this week")

st.divider()

st.markdown("### AOV Trend (Last 7 Days)")
aov_df = session.sql("""
    SELECT CHANNEL_NAME, ORDER_DATE, AOV
    FROM RETAIL_OMNICHANNEL.CURATED.CHANNEL_PERFORMANCE
    WHERE ORDER_DATE >= DATEADD('day', -7, CURRENT_DATE())
    ORDER BY ORDER_DATE, CHANNEL_NAME
""").to_pandas()

if not aov_df.empty:
    aov_df["AOV"] = pd.to_numeric(aov_df["AOV"], errors="coerce")
    fig_aov = px.bar(aov_df, x="ORDER_DATE", y="AOV", color="CHANNEL_NAME",
                     barmode="group", title="Daily AOV by Channel (7 Days)")
    fig_aov.update_layout(height=350, margin=dict(t=35, b=10))
    st.plotly_chart(fig_aov, use_container_width=True)

st.divider()

st.markdown("### Fulfillment SLA Compliance")
ful_df = session.sql("""
    SELECT FULFILLMENT_TYPE, SUM(TOTAL_ORDERS) AS TOTAL, SUM(DELIVERED) AS DELIVERED, SUM(DELAYED) AS DELAYED,
           ROUND(SUM(DELIVERED) * 100.0 / NULLIF(SUM(TOTAL_ORDERS), 0), 1) AS SLA_PCT
    FROM RETAIL_OMNICHANNEL.CURATED.FULFILLMENT_PERFORMANCE
    GROUP BY FULFILLMENT_TYPE ORDER BY FULFILLMENT_TYPE
""").to_pandas()

if not ful_df.empty:
    cols = st.columns(len(ful_df))
    for i, (_, row) in enumerate(ful_df.iterrows()):
        with cols[i]:
            sla = float(row["SLA_PCT"]) if row["SLA_PCT"] else 0
            st.metric(row["FULFILLMENT_TYPE"], f"{sla:.1f}%", delta=f"{int(row['DELAYED'])} delayed" if row["DELAYED"] else "On track")
            st.progress(min(sla / 100.0, 1.0))

st.divider()

st.markdown("### Daily Ops Briefing")
st.caption("Click Generate to have Bedrock write yesterday's operations summary")
if st.button("Generate Ops Summary", type="primary"):
    with st.spinner("Generating operations narrative..."):
        summary_data = session.sql("""
            SELECT
                (SELECT SUM(ORDER_COUNT) FROM RETAIL_OMNICHANNEL.CURATED.CHANNEL_PERFORMANCE WHERE ORDER_DATE = CURRENT_DATE() - 1) AS YESTERDAY_ORDERS,
                (SELECT ROUND(SUM(REVENUE), 0) FROM RETAIL_OMNICHANNEL.CURATED.CHANNEL_PERFORMANCE WHERE ORDER_DATE = CURRENT_DATE() - 1) AS YESTERDAY_REVENUE,
                (SELECT CHANNEL_NAME FROM RETAIL_OMNICHANNEL.CURATED.CHANNEL_PERFORMANCE WHERE ORDER_DATE = CURRENT_DATE() - 1 ORDER BY ORDER_COUNT DESC LIMIT 1) AS TOP_CHANNEL,
                (SELECT SUM(DELAYED) FROM RETAIL_OMNICHANNEL.CURATED.FULFILLMENT_PERFORMANCE) AS TOTAL_DELAYED
        """).to_pandas().iloc[0]

        prompt = f"""You are a retail operations analyst. Write a concise daily ops briefing (5 sentences max) for yesterday based on these metrics:
- Total orders: {summary_data.get('YESTERDAY_ORDERS', 'N/A')}
- Total revenue: ${summary_data.get('YESTERDAY_REVENUE', 'N/A')}
- Top channel: {summary_data.get('TOP_CHANNEL', 'N/A')}
- Delayed fulfillments: {summary_data.get('TOTAL_DELAYED', 'N/A')}
Include one recommendation."""

        safe_prompt = prompt.replace("'", "''")
        result = session.sql(f"SELECT SNOWFLAKE.CORTEX.COMPLETE('claude-sonnet-4-5', '{safe_prompt}')").collect()[0][0]
        briefing = str(result).strip().strip('"').replace("\\n", "\n").replace('$', '\\$')
        st.info(briefing)

st.divider()

st.markdown("### Channel Order Forecast (14 Days)")
forecast_df = session.sql("""
    SELECT SERIES AS CHANNEL, TS AS FORECAST_DATE, ROUND(FORECAST, 0) AS PREDICTED_ORDERS
    FROM RETAIL_OMNICHANNEL.ML.CHANNEL_FORECAST_RESULTS ORDER BY SERIES, TS
""").to_pandas()
if not forecast_df.empty:
    forecast_df["PREDICTED_ORDERS"] = pd.to_numeric(forecast_df["PREDICTED_ORDERS"], errors="coerce")
    fig3 = px.line(forecast_df, x="FORECAST_DATE", y="PREDICTED_ORDERS", color="CHANNEL",
                  title="14-Day Order Forecast by Channel")
    fig3.update_layout(height=350, margin=dict(t=35, b=10))
    st.plotly_chart(fig3, use_container_width=True)

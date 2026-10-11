'use client';

import { useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { KPICard } from '@/components/KPICard';
import { Chart } from '@/components/Chart';
import { DataTable } from '@/components/DataTable';
import { AskAI } from '@/components/AskAI';
import { ActionMemo } from '@/components/ActionMemo';

interface FulfilmentData {
  platform: 'snowflake' | 'aws';
  kpiCards: { title: string; value: string }[];
  timeseries: { period: string; late: number | null; disruptionHours: number | null }[];
  categories: { category: string; days: number | null; hours: number | null }[];
  entities: Record<string, string | number | null>[];
  countRisk: { name: string; cycleCount: number; disruptionHours: number }[];
  sourceWatermark: string | null;
  rawWatermark: string | null;
  requestedAt: string;
  stale: boolean;
  pipelineBehind: boolean;
  risk: Record<string, string | number | null>[];
  holdout: { n: number | null; baseRate: number | null; precision: number | null; recall: number | null } | null;
  forecast: { period: string; value: number | null; lower: number | null; upper: number | null }[];
  live: Record<string, string | number | null>[];
  liveSummary: { n: number | null; late: number | null; lastLoaded: string | null; medianLagSeconds: number | null };
  anomalies: Record<string, string | number | null>[];
  alerts: Record<string, string | number | null>[];
}

const pct = (value: number | null) => (value === null ? 'n/a' : `${(value * 100).toFixed(0)}%`);

export default function HomePage() {
  const [data, setData] = useState<FulfilmentData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    setError(null);
    setData(null);
    fetch('/api/data', { cache: 'no-store', signal: controller.signal })
      .then(async (response) => {
        if (!response.ok) throw new Error('Data request failed');
        const payload = await response.json();
        if (!Array.isArray(payload.kpiCards) || !Array.isArray(payload.entities)) throw new Error('Invalid contract');
        return payload;
      })
      .then(setData)
      .catch(() => {
        if (!controller.signal.aborted) setError('Snowflake data is unavailable. No fallback values are displayed.');
      })
      .finally(() => { if (!controller.signal.aborted) setLoading(false); });
    return () => controller.abort();
  }, [attempt]);

  const isAws = (data?.platform ?? 'aws') === 'aws';
  const awsDiagram = { key: 'aws', title: 'AWS + Snowflake', src: '/architecture-aws.html' };
  const sfDiagram = { key: 'snowflake', title: 'Snowflake Only', src: '/architecture-snowflake.html' };
  const diagrams = isAws ? [awsDiagram, sfDiagram] : [sfDiagram, awsDiagram];
  const kpiVal = (title: string) => data?.kpiCards.find((card) => card.title === title)?.value ?? 'Unavailable';
  const executive = (
    <div className="space-y-6">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {['On-Time Fulfilment Rate', 'Late Orders', 'Fulfilment Disruption Hours', 'Net Sales (SGD M)'].map((title) => (
          <KPICard key={title} title={title} value={kpiVal(title)} status="neutral" />
        ))}
      </div>
      <p className="text-sm text-slate-600">On-time fulfilment rate = orders fulfilled within the promised time / orders placed. A late order was fulfilled after its promised ready or delivery time; orders cancelled before fulfilment are counted separately. A disruption hour is an hour at a node when orders could not be picked, packed or handed over as planned. Net sales are the SGD value of orders that were not cancelled.</p>
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Chart data={data?.timeseries ?? []} type="line" xKey="period"
          yKeys={[{ key: 'late', name: 'Late orders' }]} title="Daily Late Orders" />
        <Chart data={data?.categories ?? []} type="bar" xKey="category"
          yKeys={[{ key: 'hours', name: 'Disruption hours' }, { key: 'days', name: 'Disruption node-days' }]} title="Fulfilment Disruption by Cause" />
      </div>
      <DataTable columns={[
        { key: 'id', header: 'Node' }, { key: 'region', header: 'Planning area' }, { key: 'category', header: 'Channel' },
        { key: 'tier', header: 'Store tier' }, { key: 'orders', header: 'Orders' }, { key: 'fulfilled', header: 'On time' },
        { key: 'late', header: 'Late' }, { key: 'disruptionHours', header: 'Disruption hours' }, { key: 'onTime', header: 'On time (%)' },
        { key: 'sales', header: 'Net sales (SGD M)' },
      ]} data={data?.entities ?? []} title="Fulfilment node observations (one channel in one planning area)" />
    </div>
  );
  const predictive = (
    <div className="space-y-4">
      <h2 className="font-semibold">7-day fulfilment-disruption risk and late-order forecast</h2>
      <p className="text-sm text-slate-600">
        Snowflake ML classification predicts the probability that a node has a fulfilment disruption in the next 7 days,
        from average pick passes per order, order-to-ready time, recent disruption hours, store tier, store age and channel.
      </p>
      {data?.holdout ? (
        <p role="status" className="text-sm text-slate-700">
          Out-of-time holdout ({data.holdout.n} node-days): precision {pct(data.holdout.precision)} and recall{' '}
          {pct(data.holdout.recall)} at a 0.5 threshold, versus a {pct(data.holdout.baseRate)} base rate.
        </p>
      ) : (
        <p role="status">Model outputs are not deployed. Run snowflake/05_ml.sql.</p>
      )}
      <DataTable columns={[
        { key: 'id', header: 'Node' }, { key: 'band', header: 'Risk band' },
        { key: 'probability', header: 'P(fulfilment disruption in 7 days)' }, { key: 'scoredAsOf', header: 'Scored as of' },
      ]} data={data?.risk ?? []} title="Fulfilment-disruption risk by node" />
      <Chart data={data?.forecast ?? []} type="line" xKey="period"
        yKeys={[{ key: 'value', name: 'Forecast' }, { key: 'lower', name: 'Lower' }, { key: 'upper', name: 'Upper' }]}
        title="Network-wide late-order forecast, next 14 days (orders per day)" />
      <DataTable columns={[
        { key: 'id', header: 'Node' }, { key: 'date', header: 'Date' }, { key: 'hours', header: 'Order-to-ready (h)' },
        { key: 'expected', header: 'Expected' }, { key: 'upper', header: 'Upper bound' },
      ]} data={data?.anomalies ?? []} title="Order-to-ready time anomalies, last 15 days (Snowflake ML anomaly detection, trained on the prior 75 days)" />
    </div>
  );
  const liveTab = (
    <div className="space-y-4">
      <h2 className="font-semibold">{isAws ? 'Live orders: Amazon Data Firehose to S3 to Snowpipe' : 'Live orders: Snowflake-native simulator'}</h2>
      <p className="text-sm text-slate-600">
        {isAws
          ? 'Simulated order fulfilment events are sent to the Firehose stream sg-retail-omnichannel-orders (aws/publish_orders.py). Firehose writes batches to S3, and Snowpipe auto-ingest loads them into RAW.LIVE_ORDERS.'
          : 'CALL APP.SIMULATE_ORDERS(n) inserts simulated order fulfilment events directly into RAW.LIVE_ORDERS (or resume APP.TASK_SIMULATE_ORDERS for a feed every minute). This simulates an order fulfilment feed; it is not Snowpipe Streaming.'}
        {' '}The alert APP.LIVE_ORDER_ALERT logs LATE orders and emails the on-call fulfilment lead.
      </p>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <KPICard title="Order events loaded" value={String(data?.liveSummary?.n ?? 'n/a')} />
        <KPICard title="LATE orders" value={String(data?.liveSummary?.late ?? 'n/a')} />
        <KPICard title={isAws ? 'Median send to table lag (s)' : 'Median generated to table lag (s)'} value={String(data?.liveSummary?.medianLagSeconds ?? 'n/a')} />
        <KPICard title="Last load" value={data?.liveSummary?.lastLoaded ?? 'none'} />
      </div>
      <DataTable columns={[
        { key: 'id', header: 'Node' }, { key: 'eventTs', header: 'Event (UTC)' }, { key: 'orderValue', header: 'Order value (SGD)' },
        { key: 'readyMinutes', header: 'Order to ready (min)' }, { key: 'status', header: 'Status' }, { key: 'loadedAt', header: 'Loaded' },
      ]} data={data?.live ?? []} title="Latest 25 orders" />
      <DataTable columns={[
        { key: 'id', header: 'Node' }, { key: 'eventTs', header: 'Event (UTC)' }, { key: 'orderValue', header: 'Order value (SGD)' },
        { key: 'readyMinutes', header: 'Order to ready (min)' }, { key: 'hint', header: 'Action hint' },
      ]} data={data?.alerts ?? []} title="Alert log" />
    </div>
  );
  const planning = (
    <div className="space-y-6">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <KPICard title="Cycle Count On-Time Rate" value={kpiVal('Cycle Count On-Time Rate')} />
        <KPICard title="Staff Training Coverage" value={kpiVal('Staff Training Coverage')} />
        <KPICard title="Staff Trainings Pending" value={kpiVal('Staff Trainings Pending')} />
      </div>
      <Chart data={data?.countRisk ?? []} type="scatter" xKey="cycleCount" xName="Cycle count on-time rate"
        yKeys={[{ key: 'disruptionHours', name: 'Disruption hours' }]} yDomain={[0, 'auto']}
        title="Cycle count on-time rate (%) vs fulfilment disruption hours by node" />
      <p className="text-sm text-slate-600">Synthetic associations are not evidence that on-time cycle counts prevented fulfilment disruptions.</p>
      <ActionMemo persona={{ name: 'Shanti Rajan', role: 'VP Omnichannel Fulfilment (fictional persona)' }} context={{}}
        onGenerate={async () => {
          const r = await fetch('/api/ask', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ mode: 'memo' }) });
          if (!r.ok) throw new Error('memo failed');
          const j = await r.json();
          return { subject: 'Draft omnichannel fulfilment actions (synthetic data, human review required)', body: j.answer, urgency: 'review', actions: [] };
        }} />
      <p role="status" className="text-sm text-slate-600">{isAws ? 'Draft generated by Amazon Bedrock (Claude) through a Snowflake external-access function' : 'Draft generated by Snowflake Cortex AI_COMPLETE (Claude Sonnet 4.5)'}, from the KPI, node, disruption-cause and risk tables only. No notification is sent.</p>
    </div>
  );
  const ai = (
    <div className="space-y-4">
      <p role="status">Answers come from the Cortex Agent APP.OMNICHANNEL_OPS_AGENT. It uses Cortex Analyst over the semantic view APP.OMNICHANNEL_ANALYTICS for metrics, and Cortex Search over synthetic fulfilment disruption SOPs for procedures. The generated SQL is shown with each answer.</p>
      <div className="h-[500px]">
        <AskAI title="Ask the fulfilment operations agent" mode="advisor" sampleQuestions={['Which 3 fulfilment nodes have the most disruption hours?', 'Which nodes are high risk this week and what SOP applies?', 'What is the on-time fulfilment rate by planning area?']}
          onSubmit={async (question) => {
            const r = await fetch('/api/agent', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ question }) });
            if (!r.ok) throw new Error('agent failed');
            const j = await r.json();
            const cites = j.sops?.length ? `\n\nSOPs: ${j.sops.join(', ')}` : '';
            return { answer: `${j.answer}${cites}`, sql: j.sql ?? undefined };
          }} />
      </div>
    </div>
  );
  const architecture = (
    <div className="space-y-4">
      {diagrams.map((d, i) => (
        <div key={d.key} className="space-y-2">
          <h2 className="font-semibold">Architecture: {d.title}{i === 0 ? ' (this deployment)' : ''}</h2>
          <iframe src={d.src} title={`${d.title} architecture diagram`} className="h-[620px] w-full rounded border border-slate-200" />
          <p className="text-sm text-slate-600">Hover a component for details. <a className="underline" href={d.src} target="_blank" rel="noreferrer">Open full screen</a></p>
        </div>
      ))}
      <h2 className="font-semibold">Implementation status</h2>
      <p>Core source: synthetic fulfilment nodes (one channel in one of 5 Singapore planning areas), daily node observations and staff training checks. Curated dynamic tables compute numerator/denominator metrics and are suspended after on-demand initialization.</p>
      <p>Application: Next.js server queries the explicit curated contract. Request time and source observation watermark are separate.</p>
      <p>ML: SNOWFLAKE.ML.CLASSIFICATION fulfilment-disruption risk model evaluated on a time-based holdout, plus a 14-day late-order FORECAST with prediction intervals.</p>
      <p>ML: ANOMALY_DETECTION flags order-to-ready time outliers per node over the last 15 days.</p>
      <p>AI: Cortex Agent (Cortex Analyst over a semantic view, plus Cortex Search over SOPs) answers questions. The action memo uses {isAws ? 'Amazon Bedrock Claude through an external-access UDF' : 'Cortex AI_COMPLETE (Claude Sonnet 4.5)'}.</p>
      {isAws ? (
        <>
          <p>AWS ingestion: Amazon Data Firehose to S3 to Snowpipe auto-ingest (SQS) into RAW.LIVE_ORDERS, with a Snowflake alert and email on LATE orders.</p>
          <p>QuickSight: Snowflake DIRECT_QUERY dashboard (daily late orders, disruption hours by node, fulfilment-disruption risk) through a PAT-only service user, with a Q topic.</p>
        </>
      ) : (
        <>
          <p>Ingestion: APP.SIMULATE_ORDERS inserts simulated order fulfilment events into RAW.LIVE_ORDERS, with a Snowflake alert and email on LATE orders. No AWS account is used.</p>
          <p>BI: this SPCS app is the dashboard; natural-language questions go to the Cortex Agent.</p>
        </>
      )}
      <p>Orchestration: the task graph APP.TASK_REFRESH_CURATED, then TASK_RESCORE_RISK, runs on demand. Alerts and tasks stay suspended between demos.</p>
    </div>
  );
  const tabs = [
    { id: 'executive-cockpit', label: 'Executive Cockpit', icon: '', content: executive },
    { id: 'predictive', label: 'Predictive', icon: '', content: predictive },
    { id: 'planning', label: 'Controls', icon: '', content: planning },
    { id: 'live', label: 'Live Orders', icon: '', content: liveTab },
    { id: 'ask-ai', label: 'Ask AI', icon: '', content: ai },
    { id: 'architecture', label: 'Architecture & Data', icon: '', content: architecture },
  ].map((tab) => ({ ...tab, content: tab.id === 'architecture' ? tab.content : (
    <div className="space-y-4">
      <p className="text-sm text-slate-600">Synthetic demo data for Sagaseed Retail, a fictional Singapore omnichannel retailer, across 5 Singapore planning areas. On-demand snapshots are not live customer operations.</p>
      {loading ? <p role="status">Loading Snowflake data...</p> : error ? (
        <div role="alert" className="rounded border border-red-200 p-4">
          <p>{error}</p>
          <button className="mt-3 rounded border px-3 py-2" onClick={() => setAttempt((value) => value + 1)}>Retry data connection</button>
        </div>
      ) : !data?.entities.length ? <p role="status">No node observations are available in this snapshot.</p> : (
        <>
          <p className="text-sm">Observation watermark: {data.sourceWatermark ?? 'Unavailable'}. Request time: {data.requestedAt}.</p>
          {(data.stale || data.pipelineBehind) && <p role="status" className="text-amber-700">Stale or lagging snapshot. Refresh the on-demand pipeline before presenting current results.</p>}
          {tab.content}
        </>
      )}
    </div>
  ) }));
  return <AppLayout title="Singapore Omnichannel Fulfilment Operations" tabs={tabs} />;
}

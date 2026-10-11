"""Publish simulated order fulfilment events to Amazon Data Firehose (stream <prefix>-orders).

Firehose batches the records into S3 (orders/); Snowpipe loads them into RAW.LIVE_ORDERS.
Node IDs come from RAW.STORES (STR-0000..STR-0039). Values are seeded random.
"""
import argparse
import json
import random
import time
from datetime import datetime, timezone


def make_event(rng):
    late = rng.random() < 0.1
    return {'store_id': f'STR-{rng.randint(0, 39):04d}',
            'event_ts': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3],
            'order_value_sgd': round(72 * rng.lognormvariate(0, 0.5), 2),
            'ready_minutes': round((210 if late else 70) * rng.lognormvariate(0, 0.35)),
            'status': 'LATE' if late else 'FULFILLED',
            'sent_ms': int(time.time() * 1000)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--region', default='us-west-2')
    ap.add_argument('--prefix', default='sg-retail-omnichannel')
    ap.add_argument('--count', type=int, default=40)
    ap.add_argument('--seed', type=int)
    args = ap.parse_args()
    import boto3
    firehose = boto3.client('firehose', region_name=args.region)
    stream = f'{args.prefix}-orders'
    rng = random.Random(args.seed)
    records = [{'Data': (json.dumps(make_event(rng)) + '\n').encode()} for _ in range(args.count)]
    for start in range(0, len(records), 500):
        out = firehose.put_record_batch(DeliveryStreamName=stream, Records=records[start:start + 500])
        if out['FailedPutCount']:
            raise RuntimeError(f"{out['FailedPutCount']} records were rejected by Firehose")
    print(f'published {args.count} order fulfilment events to Firehose stream {stream}; Firehose buffers up to 60 s before writing to S3')


if __name__ == '__main__':
    main()

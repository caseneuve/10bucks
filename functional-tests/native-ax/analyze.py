#!/usr/bin/env python3
"""Analyze raw POC evidence; measurementPass is not trusted as acceptance."""
import json
import math
from pathlib import Path
import sys


def number(v):
    assert isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)
    return v


def percentile(values, fraction):
    values = sorted(values)
    return values[max(0, math.ceil(len(values) * fraction) - 1)]


def analyze(r):
    assert not r.get('error') and r['running'] is False
    assert r['launchSubmitted'] is True and r['launchResolved'] is True and r['launchExit'] == 0
    cleanup = r['cleanup']
    assert cleanup['ok'] is True and cleanup['launchForced'] is False
    for field in ('workersDrained', 'appExited', 'launchNormal', 'bindingDeleted',
                  'timersStopped', 'cleanupTimerStopped'):
        assert cleanup[field] is True, field
    assert r['drops'] == 0 and r['drained'] is True
    rows = r['rows']
    valid = []
    previous = -math.inf
    for row in rows:
        assert row['token'] == 1
        at, cost, delivered = map(number, (row['sampled_at'], row['query_seconds'], row['delivered_at']))
        assert at > previous and cost >= 0 and delivered >= at + cost
        previous = at
        assert row['status'] in ('valid', 'invalid', 'unknown')
        if row['status'] == 'valid':
            assert row['error'] == 0
            valid.append(row)
    assert len(valid) >= 30
    statistics = {}
    for kind in ('set', 'poll'):
        values = [number(v) for v in r['costs'][kind]]
        assert len(values) >= 30 and min(values) >= 0
        median, p95, maximum = percentile(values, .5), percentile(values, .95), max(values)
        assert median <= 1 and p95 <= 1 and maximum <= 5, kind
        statistics[kind] = {'medianMs': median, 'p95Ms': p95, 'maxMs': maximum}
    posts, downs, ups = ([number(v) for v in r[k]] for k in ('posts', 'downs', 'ups'))
    assert len(posts) == len(downs) == len(ups) == 100
    for times in (posts, downs, ups):
        assert all(a < b for a, b in zip(times, times[1:]))
    latencies = []
    for i, (posted, down, up) in enumerate(zip(posts, downs, ups)):
        assert posted <= down <= up
        if i + 1 < 100: assert up <= downs[i + 1]
        latencies.extend(((down - posted) * 1000, (up - posted) * 1000))
    assert percentile(latencies, .95) <= 50 and max(latencies) <= 100
    close = number(r['closeAt'])
    detect = r['detect']
    assert detect in rows and detect['token'] == 1 and detect['status'] == 'invalid'
    assert detect['error'] == -25202  # public kAXErrorInvalidUIElement
    acquired, cost, delivered = map(number, (detect['sampled_at'], detect['query_seconds'], detect['delivered_at']))
    assert close <= acquired <= acquired + cost <= delivered <= close + .25
    assert 0 <= number(r['stopCost']) <= 5
    cancellations = r['cancellations']
    assert len(cancellations) == 2 and [v['kind'] for v in cancellations] == ['replace', 'stop']
    assert cancellations[0]['completed'] is True
    for row in cancellations:
        assert row['inflight'] is True and 0 <= number(row['costMs']) <= 5
    return {'pass': True, 'validNativeSamples': len(valid), 'mainCosts': statistics,
            'hotkeyP95Ms': percentile(latencies, .95), 'hotkeyMaxMs': max(latencies),
            'closeDeliveryMs': (delivered - close) * 1000,
            'controlledDelay': 'cancellation only; excluded from native query latency'}


if __name__ == '__main__':
    try:
        print(json.dumps(analyze(json.loads(Path(sys.argv[1]).read_text())), indent=2))
    except (AssertionError, KeyError, TypeError, ValueError, OSError, IndexError) as error:
        print(json.dumps({'pass': False, 'error': type(error).__name__}))
        sys.exit(1)

"""Native chooser benchmark oracle. isVisible is not pixel completion."""
import math

DEFINITION = 'native hs.chooser:isVisible true; not visible pixels'


def percentile(values, fraction=.95):
    return sorted(values)[math.ceil(len(values) * fraction) - 1]


def validate_row(row):
    for key in ('posted', 'receipt', 'commandReturned', 'showReturned', 'visible', 'servicePosted', 'serviceReceipt'):
        value = row.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise ValueError('missing/nonfinite native timestamp: ' + key)
    if not row['posted'] <= row['receipt'] <= row['showReturned'] <= row['commandReturned'] <= row['visible'] <= row['servicePosted'] <= row['serviceReceipt']:
        raise ValueError('native timestamps out of order')
    if row.get('nativeVisible') is not True:
        raise ValueError('missing native visibility confirmation')
    if row['serviceReceipt'] - row['servicePosted'] > .100000001:
        raise ValueError('ordinary key service maximum exceeds 100ms')
    for endpoint in ('before', 'after'):
        for group, names in (('queries', ('globalAX', 'perWindowIcon')),
                             ('resources', ('handles', 'applications', 'observers', 'readiness', 'windows', 'bindings', 'timers'))):
            counts = row.get(endpoint, {}).get(group, {})
            for name in names:
                value = counts.get(name)
                if type(value) is not int or value < 0:
                    raise ValueError('missing/nonnegative integer counter: ' + endpoint + '.' + name)
    for name in ('globalAX', 'perWindowIcon'):
        if row['after']['queries'][name] != row['before']['queries'][name]:
            raise ValueError('opening query budget exceeded: ' + name)


def summarize(rows):
    for row in rows:
        validate_row(row)
    if not rows:
        raise ValueError('missing population')
    result = {}
    for name, start, end, gate in (('invocationToVisible', 'posted', 'visible', 100),
                                    ('ordinaryKeyService', 'servicePosted', 'serviceReceipt', 50)):
        values = [1000 * (r[end] - r[start]) for r in rows]
        result[name] = dict(count=len(values), median=percentile(values, .5),
                            p95=percentile(values), maximum=max(values))
        if result[name]['p95'] > gate + 1e-6:
            raise ValueError(name + ' p95 gate exceeded')
    result['receiptToCommandReturn'] = {
        'count': len(rows),
        'p95': percentile([1000*(r['commandReturned']-r['receipt']) for r in rows]),
        'maximum': max(1000*(r['commandReturned']-r['receipt']) for r in rows)}
    return result


def validate_batch(raw, mode):
    if raw.get('definition') != DEFINITION or raw.get('mode') != mode or raw.get('status') != 'complete':
        raise ValueError('wrong definition/mode or incomplete run')
    if len(raw.get('samples', [])) != (10 if mode == 'warm' else 1) or len(raw.get('warmup', [])) != (1 if mode == 'warm' else 0):
        raise ValueError('wrong sample/warmup quota')
    for row in raw['warmup']:
        validate_row(row)
    if not raw.get('cleanup', {}).get('ok'):
        raise ValueError('cleanup failed')
    return summarize(raw['samples'])


def validate_population(batches):
    if [b.get('mode') for b in batches].count('warm') != 3 or [b.get('mode') for b in batches].count('cold') != 5:
        raise ValueError('requires three warm and five fresh cold runs')
    identities = [b.get('run') for b in batches]
    if None in identities or len(set(identities)) != 8:
        raise ValueError('run identities must be unique')
    for b in batches:
        validate_batch(b, b['mode'])
    return {mode: summarize([r for b in batches if b['mode'] == mode for r in b['samples']])
            for mode in ('warm', 'cold')}

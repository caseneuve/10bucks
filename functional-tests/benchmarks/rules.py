"""Rules benchmark data validation; no functional sampling dependency."""

def validate_path(row):
    from scenarios.columns_close_recovery import AcceptanceFailure
    end = row.get('frame') if row['action'] == 'manage' else row.get('commit')
    if (not all(isinstance(row.get(k), (int, float)) for k in ('ready', 'filter', 'commit'))
            or end is None or not row['ready'] <= row['filter'] <= row['commit'] <= end
            or not 0 <= row['callback']-row['posted'] <= .1
            or (row['action'] == 'exclude' and row['effects'] != {'frame': 0, 'focus': 0})):
        raise AcceptanceFailure('invalid rule-path data or ordinary service maximum exceeded')


def validate_population(samples):
    from scenarios.columns_close_recovery import AcceptanceFailure
    from benchmarks.desktop_switching import nearest_rank
    for row in samples: validate_path(row)
    for action, endpoint in (('manage', 'frame'), ('exclude', 'commit')):
        costs = [1000*(r[endpoint]-r['ready']) for r in samples if r['action'] == action]
        if not costs or nearest_rank(costs, .95) > 100:
            raise AcceptanceFailure(action + ' readiness p95 exceeds 100ms or population missing')
    service = [1000*(r['callback']-r['posted']) for r in samples]
    if nearest_rank(service, .95) > 50:
        raise AcceptanceFailure('ordinary service p95 exceeds 50ms')


def validate_batch(result, mode):
    from scenarios.columns_close_recovery import AcceptanceFailure
    from collections import Counter
    n = 10 if mode == 'warm' else 1
    if (result.get('mode') != mode or result.get('status') != 'complete'
            or Counter(r.get('action') for r in result.get('samples', [])) != {'manage':n,'exclude':n}
            or Counter(r.get('action') for r in result.get('warmup', [])) !=
               ({'manage':1,'exclude':1} if mode == 'warm' else {})):
        raise AcceptanceFailure('wrong mode/counts or incomplete benchmark')
    for row in result['warmup']: validate_path(row)
    validate_population(result['samples'])


def run(driver, *, mode):
    import time
    deadline=time.monotonic()+50
    driver.preflight()
    driver.fixture_action('measure', mode)
    result=driver.benchmark_result()
    if result.get('status') != 'complete': raise RuntimeError('incomplete rules benchmark')
    try:
        validate_batch(result, mode)
    except Exception:
        result['status']='failed';driver.benchmark_record(result)
        raise
    result['status']='measured';driver.benchmark_record(result)
    if time.monotonic()>deadline: raise RuntimeError('benchmark procedure deadline')

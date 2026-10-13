"""Existing desktop benchmark owner; behavior criteria remain in scenarios."""
from scenarios.desktop_switching import *
from copy import deepcopy
import math

def nearest_rank(values, percentile):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * percentile) - 1)]


def summarize_batches(batches):
    """Pure artifact analysis; reject incomplete/censored sets rather than dropping rows."""
    result = {}
    for mode, minimum in (('warm', 30), ('cold', 5)):
        rows = []
        for batch in batches:
            if batch.get('mode') != mode:
                continue
            samples = batch.get('samples', [])
            if (batch.get('status') != 'measured' or batch.get('lost') != 0
                    or batch.get('expected') != len(samples)):
                raise AcceptanceFailure('incomplete/censored benchmark batch')
            rows.extend(samples)
        if len(rows) < minimum:
            raise AcceptanceFailure(f'{mode} needs at least {minimum} complete samples')
        stats = {}
        for name, start, end in (
                ('postedToCallbackMs', 'posted', 'callback'),
                ('postedToRequestMs', 'posted', 'request'),
                ('requestToPressMs', 'request', 'press'),
                ('requestToNativeConfirmationMs', 'request', 'confirmation'),
                ('benignServiceMs', 'benignPosted', 'benignCallback')):
            values = [1000 * (r[end] - r[start]) for r in rows]
            if any(not math.isfinite(v) or v < 0 for v in values):
                raise AcceptanceFailure('invalid benchmark timestamps')
            stats[name] = {'median': nearest_rank(values, .5),
                           'p95': nearest_rank(values, .95), 'max': max(values)}
        passed = (stats['postedToRequestMs']['p95'] <= 50
                  and stats['benignServiceMs']['p95'] <= 50
                  and stats['benignServiceMs']['max'] <= 100)
        result[mode] = {'count': len(rows), 'stats': stats, 'budgetPassed': passed}
    return result


def benchmark(driver, *, mode='warm', clock=time.monotonic, sleep=time.sleep):
    """Bounded batches; caller aggregates THREE warm + FIVE cold invocations.

    Cold means the first real switch after a newly started runtime, not VM boot.
    No fixture needed. Calibrated HyperY is a separate non-product binding.
    """
    driver.preflight()
    gate = sampling_gate(driver, scenario_id=SCENARIO_ID, clock=clock, sleep=sleep)
    last = gate('benchmark initial D1', lambda o: topology(o, 'D1') and workspace(o, 'D1'))
    before = last.commands_received.get('benignService', 0)
    calibration_start = len(last.diagnostics.get('keyEvents', []))
    driver.hotkey('benignService')
    last = gate('ordinary HyperY calibration', lambda o: o.commands_received.get('benignService', 0) == before + 1)
    calibration = last.diagnostics.get('keyEvents', [])[calibration_start:]
    posted = [r['at'] for r in calibration if r['kind'] == 'posted' and r['name'] == 'benignService']
    callbacks = [r['at'] for r in calibration if r['kind'] == 'callback' and r['name'] == 'benignService']
    if len(posted) != 1 or len(callbacks) != 1 or not 0 <= callbacks[0] - posted[0] <= .1:
        raise AcceptanceFailure('ordinary HyperY calibration failed')
    initial_instrumentation = deepcopy(last.diagnostics.get('instrumentation', {}))
    if mode == 'warm':
        for command, target in (('focusDesktop2', 'D2'), ('focusDesktop1', 'D1')):
            before = last.commands_received.get(command, 0)
            driver.hotkey(command)
            last = gate('warmup ' + target, lambda o:
                        topology(o, target) and workspace(o, target)
                        and o.commands_received.get(command, 0) == before + 1)
    samples = []
    expected_count = 10 if mode == 'warm' else 1
    driver.benchmark_record({'mode': mode, 'expected': expected_count, 'samples': [],
                             'status': 'sampling', 'calibration': calibration})
    for index in range(expected_count):
        command = 'focusDesktop2' if index % 2 == 0 else 'focusDesktop1'
        target = 'D2' if index % 2 == 0 else 'D1'
        events_start = len(last.diagnostics.get('keyEvents', []))
        trace_start = len(last.diagnostics.get('workspaceTrace', []))
        counts = dict(last.commands_received)
        driver.benchmark_record({'mode': mode, 'expected': expected_count, 'samples': samples,
                                 'status': 'sampling', 'pending': {'index': index + 1, 'command': command}})
        driver.hotkey_burst((command, 'benignService'))
        last = gate(f'{mode} sample {index + 1}', lambda o:
                    topology(o, target) and workspace(o, target)
                    and o.commands_received.get(command, 0) == counts.get(command, 0) + 1
                    and o.commands_received.get('benignService', 0) == counts.get('benignService', 0) + 1)
        events = last.diagnostics['keyEvents'][events_start:]
        trace = last.diagnostics['workspaceTrace'][trace_start:]
        def at(kind, name):
            rows = [r['at'] for r in events if r['kind'] == kind and r['name'] == name]
            if len(rows) != 1: raise AcceptanceFailure('lost/duplicate benchmark receipt')
            return rows[0]
        def effect(kind):
            rows = [r['at'] for r in trace if r['kind'] == kind]
            if len(rows) != 1: raise AcceptanceFailure('lost/duplicate benchmark effect')
            return rows[0]
        posted, callback = at('posted', command), at('callback', command)
        request, press, confirmation = (effect(k) for k in ('switchRegularSpace', 'RegularSwitchPressed', 'confirmed'))
        samples.append({'posted': posted, 'callback': callback, 'request': request,
                        'press': press, 'confirmation': confirmation,
                        'benignPosted': at('posted', 'benignService'),
                        'benignCallback': at('callback', 'benignService')})
    result = {'mode': mode, 'samples': samples, 'expected': len(samples), 'lost': 0,
              'calibration': calibration, 'status': 'measured',
              'scope': 'guest posted-event service; cold runtime, not cold OS/physical input',
              'initialInstrumentation': initial_instrumentation,
              'instrumentation': last.diagnostics.get('instrumentation', {})}
    driver.benchmark_record(result)  # preserve failures before fixed budget assertions
    request_cost = [1000 * (r['request'] - r['posted']) for r in samples]
    service = [1000 * (r['benignCallback'] - r['benignPosted']) for r in samples]
    if any(v < 0 for v in request_cost + service):
        raise AcceptanceFailure('invalid benchmark clock ordering')
    if nearest_rank(request_cost, .95) > 50 or nearest_rank(service, .95) > 50 or max(service) > 100:
        raise AcceptanceFailure('desktop/benign key-service budgets exceeded; samples preserved')

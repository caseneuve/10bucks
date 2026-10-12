"""Authoritative existing-desktop FT. Native identity is never inferred from intent."""
from collections import Counter
from copy import deepcopy
import math
import time

from scenarios.columns_close_recovery import Frame, AcceptanceFailure, sampling_gate, same_frame

SCENARIO_ID = 'desktop-switching'
INVARIANTS = ('SPACE-001', 'SPACE-002', 'SPACE-004', 'SPACE-005', 'LAY-001',
              'LAY-003', 'COL-008', 'WIN-002', 'STATE-002')
TOPOLOGY = {'order': ['D1', 'D2', 'D3'], 'regular': ['D1', 'D2', 'D3'],
            'types': ['user', 'user', 'user'], 'count': 3}
# Real chords in ONE controller turn, without per-command confirmation.
SWITCHES = (
    (('focusDesktop2',), 'D2', ('D2',)),
    (('focusDesktop1',), 'D1', ('D1',)),
    (('focusPreviousDesktopPosition',), 'D3', ('D3',)),
    (('focusNextDesktop',), 'D1', ('D1',)),
    (('focusDesktop9',), 'D1', ()),
    (('focusPreviousDesktop', 'focusPreviousDesktop'), 'D3', ('D3',)),
    (('focusPreviousDesktop',), 'D1', ('D1',)),
    (('focusNextDesktop', 'focusNextDesktop'), 'D3', ('D2', 'D3')),
    (('focusDesktop1',), 'D1', ('D1',)),
    (('focusNextDesktop', 'focusPreviousDesktopPosition'), 'D1', ('D2', 'D1')),
    (('focusNextDesktop', 'focusNextDesktop', 'focusDesktop1'), 'D1', ('D2', 'D1')),
)


def retained(row):
    result = deepcopy(row)
    result.pop('active', None)
    return result


def topology(o, active):
    native = o.diagnostics.get('nativeDesktop', {})
    return native.get('active') == active and all(native.get(k) == v for k, v in TOPOLOGY.items())


def workspace(o, active):
    w = o.diagnostics.get('workspace', {})
    return (w.get('active') == active and w.get('history', {}).get('current') == active
            and not w.get('desired') and not w.get('inFlight'))


def trace_check(o, baseline, commands, destinations, events_baseline=0, source=None):
    """Native effect serialization is SECONDARY to independent final native IDs."""
    rows = o.diagnostics.get('workspaceTrace', [])[baseline:]
    requests = [r for r in rows if r['kind'] == 'switchRegularSpace']
    pressed = [r for r in rows if r['kind'] == 'RegularSwitchPressed']
    confirmed = [r for r in rows if r['kind'] == 'confirmed']
    if any(r['kind'] in ('RegularSwitchFailed', 'RegularSwitchTimedOut', 'RegularSwitchCancelled') for r in rows):
        return False
    if any(tuple(r['destination'] for r in items) != destinations
           for items in (requests, pressed, confirmed)):
        return False
    for index, (request, press, confirmation) in enumerate(zip(requests, pressed, confirmed)):
        expected_source = destinations[index - 1] if index else source
        if expected_source is not None and request['source'] != expected_source:
            return False
        if not (request['generation'] == press['generation'] == confirmation['generation']
                and request['source'] == press['source'] == confirmation['source']
                and request['at'] <= press['at'] <= confirmation['at']):
            return False
        if index and request['at'] < confirmed[index - 1]['at']:
            return False
    # Verify the burst actually arrived before first AXPress, not just posted fast.
    if len(commands) > 1 and pressed:
        events = o.diagnostics.get('keyEvents', [])[events_baseline:]
        callbacks = [r for r in events if r['kind'] == 'callback' and r['name'] in commands]
        posts = [r for r in events if r['kind'] == 'posted' and r['name'] in commands]
        if (Counter(r['name'] for r in callbacks) != Counter(commands)
                or Counter(r['name'] for r in posts) != Counter(commands)
                or any(r['at'] >= pressed[0]['at'] for r in callbacks + posts)):
            return False
    return True


def run(driver, *, clock=time.monotonic, sleep=time.sleep):
    area = driver.preflight()
    assert all(math.isfinite(v) for v in (area.x, area.y, area.w, area.h)) and area.w > 0 and area.h > 0
    gate = sampling_gate(driver, scenario_id=SCENARIO_ID, clock=clock, sleep=sleep)
    last = gate('three existing regular desktops, empty D1', lambda o:
                topology(o, 'D1') and workspace(o, 'D1') and not o.managed and not o.frames)

    def local_match(o, order, focus, layout, ratio):
        d = o.diagnostics
        columns = d.get('layouts', {}).get('columns', {})
        expected = {a: area for a in order}
        if layout == 'columns' and len(order) > 1:
            left = Frame(area.x, area.y, area.w * ratio, area.h)
            right = Frame(area.x + area.w * ratio, area.y, area.w * (1 - ratio), area.h)
            expected = {a: left if a == 'A' else right for a in order}
        return (topology(o, 'D1') and workspace(o, 'D1') and o.focused == focus
                and o.managed == frozenset(order) and not o.closed
                and set(o.frames) == set(order)
                and all(same_frame(o.frames.get(a), f) for a, f in expected.items())
                and d.get('layout') == layout and d.get('order') == list(order)
                and columns.get('groups') == ([['A'], list(order[1:])] if len(order) > 1 else [['A']])
                and columns.get('ratio') == ratio)

    for alias, order in (('A', 'A'), ('B', 'AB'), ('C', 'ABC')):
        driver.create(alias)
        last = gate('create ' + alias + ' only on D1', lambda o, order=order, alias=alias:
                    local_match(o, order, alias, 'columns', .5))

    def local_command(command, focus, layout, ratio):
        nonlocal last
        before = last.commands_received.get(command, 0)
        driver.hotkey(command)
        last = gate(command, lambda o:
                    o.commands_received.get(command, 0) == before + 1
                    and local_match(o, 'ABC', focus, layout, ratio))

    local_command('resizeRight', 'C', 'columns', .55)
    local_command('cycleLayout', 'C', 'stack', .55)
    local_command('focusPrevious', 'B', 'stack', .55)
    local_command('focusNext', 'C', 'stack', .55)
    local_command('cycleLayout', 'C', 'columns', .55)
    saved = retained(last.diagnostics['retained']['D1'])
    if (saved['layouts']['columns'].get('selected') != ['A', 'C']
            or saved['layouts']['columns'].get('active') != 2
            or saved['layouts']['stack'].get('members') != list('ABC')
            or saved['layouts']['stack'].get('selected') != 'C'):
        raise AcceptanceFailure('setup must retain exact columns selections and stack order/selection')
    known_scopes = {'D1': saved}
    for commands, target, destinations in SWITCHES:
        counts = dict(last.commands_received)
        start = len(last.diagnostics.get('workspaceTrace', []))
        events_start = len(last.diagnostics.get('keyEvents', []))
        previous = last.diagnostics['workspace']['history']['current']
        history = last.diagnostics['workspace']['history'].get('previous')
        if len(commands) > 1:
            driver.hotkey_burst(commands)
        else:
            driver.hotkey(commands[0])
        increments = Counter(commands)
        def matches(o):
            scopes = o.diagnostics.get('retained', {})
            h = o.diagnostics.get('workspace', {}).get('history', {})
            # Two-leg relative operations confirm intermediate history too.
            expected_previous = ('D2' if len(destinations) == 2 else
                                 previous if target != previous else history)
            return (topology(o, target) and workspace(o, target)
                    and h.get('previous') == expected_previous
                    and all(o.commands_received.get(k, 0) == counts.get(k, 0) + n for k, n in increments.items())
                    and all(retained(scopes.get(k, {})) == v for k, v in known_scopes.items())
                    and all('unknown' not in row.get('order', []) for row in scopes.values())
                    and not o.closed
                    and (target != 'D1' or local_match(o, 'ABC', 'C', 'columns', .55))
                    and trace_check(o, start, commands, destinations, events_start, previous))
        last = gate(' + '.join(commands) + ' native ' + target, matches)
        for alias, row in last.diagnostics['retained'].items():
            known_scopes.setdefault(alias, retained(row))


def fullscreen(driver, *, clock=time.monotonic, sleep=time.sleep):
    """Separate bounded native fixture subcase; never corrective focus/reflow.

    F1 joins the newly observed native owner of exact fixture A, not a desired
    target. Three regular IDs stay D1/D2/D3 even with F1 in the full AX order.
    Exit checks FS-002 slot/availability/geometry, not deferred focus restoration;
    actual focus remains recorded unchanged by the driver at every checkpoint.
    """
    area = driver.preflight()
    assert all(math.isfinite(v) for v in (area.x, area.y, area.w, area.h)) and area.w > 0 and area.h > 0
    gate = sampling_gate(driver, scenario_id=SCENARIO_ID + '-fullscreen', clock=clock, sleep=sleep)
    last = gate('fullscreen subcase empty D1', lambda o:
                topology(o, 'D1') and workspace(o, 'D1') and not o.managed and not o.frames)
    driver.create('A')
    last = gate('native D1 A full-width focused', lambda o:
                topology(o, 'D1') and workspace(o, 'D1') and o.focused == 'A'
                and o.managed == frozenset('A') and not o.closed
                and same_frame(o.frames.get('A'), area)
                and o.diagnostics.get('fixtureNative', {}).get('A') == {'fullscreen': False, 'spaces': ['D1']})
    saved = retained(last.diagnostics['retained']['D1'])
    if saved.get('order') != ['A'] or saved.get('layout') != 'columns':
        raise AcceptanceFailure('fullscreen setup must retain D1 A columns slot')

    def slot(o, unavailable):
        row = retained(o.diagnostics.get('retained', {}).get('D1', {}))
        expected = dict(saved, nativeFullscreen=['A'] if unavailable else [], unavailable=['A'] if unavailable else [])
        return row == expected

    def mixed(o, active):
        n = o.diagnostics.get('nativeDesktop', {})
        order, types = n.get('order', []), n.get('types', [])
        return (n.get('active') == active and n.get('count') == 4
                and n.get('regular') == ['D1', 'D2', 'D3'] and len(order) == len(types) == 4
                and len(set(order)) == 4 and set(order) == {'D1', 'D2', 'D3', 'F1'}
                and [a for a in order if a != 'F1'] == ['D1', 'D2', 'D3']
                and all(kind == ('fullscreen' if alias == 'F1' else 'user') for alias, kind in zip(order, types)))

    def native_full(o):
        return o.diagnostics.get('fixtureNative', {}).get('A') == {'fullscreen': True, 'spaces': ['F1']}

    driver.fixture_fullscreen(True)
    last = gate('native F1 A; three regular/four full Spaces; saved D1 slot unavailable', lambda o:
                mixed(o, 'F1') and native_full(o) and o.focused == 'A' and not o.closed
                and slot(o, True) and not o.diagnostics.get('workspace', {}).get('active')
                and o.diagnostics.get('workspace', {}).get('history', {}).get('current') == 'D1')
    full_order = deepcopy(last.diagnostics['nativeDesktop']['order'])
    for command, target, source in (('focusDesktop2', 'D2', 'F1'), ('focusDesktop1', 'D1', 'D2')):
        count = last.commands_received.get(command, 0)
        start = len(last.diagnostics.get('workspaceTrace', []))
        driver.hotkey(command)
        last = gate(command + ' skips F1, native ' + target, lambda o:
                    mixed(o, target) and o.diagnostics['nativeDesktop']['order'] == full_order
                    and native_full(o) and workspace(o, target) and slot(o, True) and not o.closed
                    and o.commands_received.get(command, 0) == count + 1
                    and trace_check(o, start, (command,), (target,), source=source))
    driver.fixture_fullscreen(False)
    gate('exit F1 native D1 A full-width; retained slot available; focus observed only', lambda o:
         topology(o, 'D1') and workspace(o, 'D1') and slot(o, False)
         and o.diagnostics.get('fixtureNative', {}).get('A') == {'fullscreen': False, 'spaces': ['D1']}
         and o.managed == frozenset('A') and not o.closed
         and same_frame(o.frames.get('A'), area))


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

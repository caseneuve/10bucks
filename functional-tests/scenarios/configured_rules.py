"""RULE-001/003/004 native oracle. No corrective focus or production projector."""
import time
from scenarios.columns_close_recovery import Frame, same_frame, sampling_gate

SCENARIO_ID = 'configured-rules'
INVARIANTS = ('RULE-001', 'RULE-003', 'RULE-004', 'FOCUS-001', 'BAR-001')


def checkpoint(area, live, managed, focus, *, closed=(), excluded=(), titles=None, receipt=None,
               layout='columns', ratio=0.5, desktop='D1', retained=None, rejected=None):
    # Columns: first managed A left, second C right. Sole A fills work area.
    frames = {a: area for a in managed}
    if len(managed) == 2 and layout == 'columns':
        frames = {managed[0]: Frame(area.x, area.y, area.w * ratio, area.h),
                  managed[1]: Frame(area.x + area.w * ratio, area.y, area.w * (1-ratio), area.h)}

    def matches(o):
        d = o.diagnostics.get('configuredRules', {})
        baseline, effects = d.get('baseline', {}), d.get('effects', {})
        native = o.diagnostics.get('nativeDesktop', {})
        scope = o.diagnostics.get('retained', {}).get('D1', {})
        if not (set(o.frames) == set(live) and o.managed == frozenset(managed if desktop=='D1' else ())
                and o.focused == focus and o.closed == frozenset(closed)
                and native.get('active') == desktop and native.get('regular') == ['D1','D2','D3']
                and scope.get('order') == list(managed) and scope.get('layout') == layout
                and scope.get('active') == (desktop == 'D1')
                and (retained is None or {k:v for k,v in scope.items() if k!='active'} ==
                     {k:v for k,v in retained.items() if k!='active'})):
            return False
        layouts = scope.get('layouts', {})
        if len(managed) == 2:
            columns = layouts.get('columns', {})
            if (columns.get('groups') != [[managed[0]], [managed[1]]]
                    or columns.get('selected') != list(managed)
                    or columns.get('ratio') != ratio):
                return False
            if layout == 'stack' and layouts.get('stack', {}).get('members') != list(managed):
                return False
        if d.get('excludedSafetyTargets') != [] or d.get('lifetimeMismatch') is not False:
            return False
        expected_actions = {**{a: 'manage' for a in managed},
                            **{a: 'exclude' for a in excluded if a not in closed}}
        actions = d.get('actions')
        if actions == [] and not expected_actions: actions = {}  # Lua's empty JSON table
        if not d.get('instrumented') or actions != expected_actions:
            return False
        if any(d.get('evaluations', {}).get(a) != 1 or d.get('commits', {}).get(a) != 1
               for a in set(live) | set(closed)):
            return False
        if not all(same_frame(o.frames.get(a), f) for a, f in frames.items()):
            return False
        for a in excluded:
            if a not in baseline or effects.get(a) != {'frame': 0, 'focus': 0}:
                return False
            if a in live and not same_frame(o.frames.get(a), Frame(**baseline[a])):
                return False
        history = d.get('history')
        if not isinstance(history, list) or not set(history).issubset(set(managed)):
            return False
        if titles and any(d.get('titles', {}).get(a) != t for a, t in titles.items()):
            return False
        if rejected:
            result=d.get('commandResults', {}).get(rejected[0], {})
            if result != {'count':rejected[1], 'accepted':False, 'rejected':True}:
                return False
        if focus is not None and focus in live and (
                not all(d.get('presentationJoin', {}).get(field) is True for field in
                        ('id','pid','appResource','presentationResource','nativeHandle','hostId','hostPid'))
                or d.get('presentationJoin', {}).get('nativeAlias') != focus
                or d.get('actualAlias') != focus
                or d.get('actualTitleToken') == 'unknown'
                or d.get('actualTitleToken') != d.get('titleTokens', {}).get(focus)
                or d.get('actualTitle') not in ('managed','excluded')
                or d.get('titles', {}).get(focus) not in ('managed','excluded')
                or d.get('actualTitle') != d['titles'][focus]):
            return False
        return receipt is None or o.commands_received.get(receipt[0], 0) == receipt[1]
    return matches


def run(driver, *, clock=time.monotonic, sleep=time.sleep):
    area = driver.preflight()
    eventually = sampling_gate(driver, scenario_id=SCENARIO_ID, clock=clock, sleep=sleep)
    live, managed, closed, excluded = [], [], [], []
    layout, ratio = 'columns', 0.5
    def check(name, focus, **kw):
        return eventually(name, checkpoint(area, live, managed, focus,
                          closed=closed, excluded=excluded, layout=layout, ratio=ratio, **kw))
    for alias in 'ABCD':
        driver.create(alias)
        live.append(alias)
        (excluded if alias in 'BD' else managed).append(alias)
        check('create ' + alias, alias)
    # Planned stimulus, never a repair: retained managed selection C, actual B.
    driver.fixture_action('focus', 'B')
    before = check('excluded actual focus', 'B')
    saved_rejection=before.diagnostics['retained']['D1']
    reject_count=before.commands_received.get('moveFocusedToOtherGroup',0)+1
    driver.hotkey('moveFocusedToOtherGroup')
    before=check('excluded managed-target rejection', 'B', retained=saved_rejection,
                 receipt=('moveFocusedToOtherGroup',reject_count),
                 rejected=('moveFocusedToOtherGroup',reject_count))
    count = before.commands_received.get('focusLeftGroup', 0)
    driver.hotkey('focusLeftGroup')
    check('first left invocation from excluded focus', 'A', receipt=('focusLeftGroup', count + 1))
    def command(name, focus):
        # Each stimulus follows a passed checkpoint; never repairs a failed gate.
        driver.fixture_action('focus', 'B')
        before = check(name + ' excluded stimulus', 'B')
        count = before.commands_received.get(name, 0)
        driver.hotkey(name)
        return check(name + ' first invocation', focus, receipt=(name, count + 1))
    command('focusRightGroup', 'C')
    command('focusNext', 'C')
    command('focusPrevious', 'C')
    driver.fixture_action('focus', 'B'); before = check('stack stimulus', 'B')
    driver.hotkey('cycleLayout'); layout = 'stack'
    check('stack retained C', 'B', receipt=('cycleLayout', before.commands_received.get('cycleLayout', 0)+1))
    command('focusPrevious', 'A')
    command('focusNext', 'C')
    driver.fixture_action('focus', 'B'); before = check('columns stimulus', 'B')
    driver.hotkey('cycleLayout'); layout = 'columns'
    check('columns retained', 'B', receipt=('cycleLayout', before.commands_received.get('cycleLayout', 0)+1))
    before = check('divider baseline', 'B'); driver.hotkey('resizeRight'); ratio = .55
    check('divider from exclusion', 'B', receipt=('resizeRight', before.commands_received.get('resizeRight',0)+1))
    before = check('reflow baseline', 'B'); driver.hotkey('reflow')
    before = check('reflow from exclusion', 'B', receipt=('reflow', before.commands_received.get('reflow',0)+1))
    saved = before.diagnostics['retained']['D1']
    departure_focus = before.focused
    driver.hotkey('focusDesktop2')
    check('existing D2', None, desktop='D2', retained=saved,
          receipt=('focusDesktop2', before.commands_received.get('focusDesktop2',0)+1))
    before = driver.observe(); driver.hotkey('focusDesktop1')
    check('return retained D1', departure_focus, retained=saved,
          receipt=('focusDesktop1', before.commands_received.get('focusDesktop1',0)+1))
    driver.fixture_action('focus', 'B'); check('rename excluded focus stimulus', 'B')
    driver.fixture_action('renameToManaged', 'B')
    check('excluded lifetime does not rematch', 'B', titles={'B': 'managed'})
    driver.fixture_action('focus', 'A'); check('rename managed focus stimulus', 'A')
    driver.fixture_action('renameToExcluded', 'A')
    check('managed lifetime does not rematch', 'A', titles={'A': 'excluded'})
    driver.close('B'); live.remove('B'); closed.append('B')
    check('actual excluded destruction', 'A')
    # E is a new resource with B's initial exact excluded title.
    driver.close('C'); live.remove('C'); managed.remove('C'); closed.append('C')
    check('managed destruction', 'A')
    driver.fixture_action('createExcluded', 'E'); live.append('E'); excluded.append('E')
    check('new same-title lifetime evaluates exclusion', 'E', titles={'E': 'excluded'})

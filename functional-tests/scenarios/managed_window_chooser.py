"""CHOOSE-001..004 actual native UI oracle; restoration is roadmap step 5.

Uses the ordinary 5s/250ms/150ms sampler. No quotas, benchmark controller,
cache assertions, corrective focus, or programmatic chooser selection.
"""
import time
import math
from scenarios.columns_close_recovery import sampling_gate, same_frame

SCENARIO_ID = 'managed-window-chooser'
INVARIANTS = ('CHOOSE-001', 'CHOOSE-002', 'CHOOSE-003', 'CHOOSE-004',
              'WIN-001', 'WIN-004', 'WIN-005', 'FOCUS-003', 'FOCUS-005', 'FOCUS-006')
UNSET = object()


def checkpoint(rows, *, visible=True, titles=None, query='', focus=UNSET,
               frames=None, completion=None, receipt=None, desktop=None,
               native=None, closed=(), pending=None, final_geometry=None):
    """Expected visible order/text and exact returned target, independent AX outcome."""
    titles = titles or {}
    def matches(o):
        d = o.diagnostics.get('chooser', {})
        snapshot = d.get('nativeSnapshot', {})
        if (d.get('visible') is not visible or o.closed != frozenset(closed)
                or snapshot.get('runMatch') is not True or snapshot.get('pidMatch') is not True
                or type(snapshot.get('sequence')) is not int or snapshot['sequence'] <= 0
                or type(snapshot.get('sampled_at')) not in (int, float)
                or not math.isfinite(snapshot['sampled_at'])
                or type(snapshot.get('age')) not in (int, float)
                or not 0 <= snapshot['age'] <= .15):
            return False
        if visible:
            expected = [{'alias': a, 'text': titles.get(a, '10bucks fixture ' + a),
                         'subText': '10bucks Fixture'} for a in rows]
            if d.get('rows') != expected or d.get('query') != query:
                return False
        for setup in d.get('setupSettlements', []):
            if setup.get('field') == 'fullscreen' and (
                    setup.get('nativeOwnerMatch') is not True
                    or type(setup.get('nativeOwnerStableSeconds')) not in (int, float)
                    or not .25 <= setup['nativeOwnerStableSeconds'] <= 3):
                return False
            if (type(setup.get('wanted')) is not bool or setup.get('observed') is not setup['wanted']
                    or type(setup.get('sequence')) is not int or type(setup.get('afterSequence')) is not int
                    or setup['sequence'] <= setup['afterSequence']
                    or type(setup.get('started')) not in (int, float)
                    or type(setup.get('finished')) not in (int, float)
                    or not 0 <= setup['finished'] - setup['started'] <= 3):
                return False
        if focus is not UNSET and o.focused != focus:
            return False
        if frames is not None and (set(o.frames) != set(frames) or
                any(not same_frame(o.frames.get(a), f) for a, f in frames.items())):
            return False
        if pending is not None and d.get('pending') is not pending:
            return False
        if final_geometry is not None:
            retained = o.diagnostics.get('retained', {})
            if (set(o.frames) != set('ABCD')
                    or retained.get('D2', {}).get('order') != ['D']
                    or retained.get('D2', {}).get('active') is not False
                    or o.diagnostics.get('nativeDesktop', {}).get('active') != 'D1'
                    or any(d.get('native', {}).get(a, {}).get('identityMatch') is not True for a in 'ABCD')
                    or any(not same_frame(o.frames.get(a), f) for a, f in final_geometry.items())):
                return False
        if completion is not None and d.get('completions') != completion:
            return False
        if receipt is not None and o.commands_received.get(receipt[0], 0) != receipt[1]:
            return False
        if desktop is not None and o.diagnostics.get('nativeDesktop', {}).get('active') != desktop:
            return False
        for alias, fields in (native or {}).items():
            observed = d.get('native', {}).get(alias, {})
            if any(observed.get(k) != v for k, v in fields.items()):
                return False
        return True
    return matches


def run(driver, *, clock=time.monotonic, sleep=time.sleep):
    area = driver.preflight()
    gate = sampling_gate(driver, scenario_id=SCENARIO_ID, clock=clock, sleep=sleep)
    titles, completions, closed = {}, [], []
    rows = ['A', 'C']  # B deliberately excluded by generic fixture rule

    def check(name, **kw):
        return gate(name, checkpoint(rows, titles=titles, completion=completions,
                                     closed=closed, **kw))

    def open_chooser(name, **kw):
        before = check(name + ' baseline', visible=False, **kw)
        count = before.commands_received.get('chooseWindow', 0) + 1
        driver.hotkey('chooseWindow')
        return check(name, receipt=('chooseWindow', count), **{k:v for k,v in kw.items() if k!='focus'})

    def select(operation, target, *, accepted=True, reason=None, **kw):
        driver.hotkey(operation)
        result = {'alias': target, 'accepted': accepted}
        if reason is not None:
            result['reason'] = reason
        completions.append(result)
        return check(operation + ' exact ' + target, visible=False,
                     pending=False if accepted else None, **kw)

    for a in 'ABC':
        driver.create(a)
        gate('native create ' + a, lambda o, a=a: o.focused == a and a in o.frames)
    # Independent work-area geometry, not a production projector.
    from scenarios.columns_close_recovery import Frame
    paired = {'A': Frame(area.x, area.y, area.w/2, area.h),
              'C': Frame(area.x+area.w/2, area.y, area.w/2, area.h)}
    gate('initial native columns', lambda o: o.managed == frozenset('AC') and
         all(same_frame(o.frames.get(a), f) for a, f in paired.items()))
    open_chooser('admission order and exclusion')
    driver.hotkey('chooserCancel')
    before = check('cancel preserves native focus', visible=False, focus='C')
    frames = before.frames
    open_chooser('fuzzy title')
    driver.chooser_query('1bfx')  # subsequence, not a contiguous native substring
    check('fuzzy title visible rows', query='1bfx')
    select('chooserCmd2', 'C', focus='C', frames=frames)  # same target confirmation
    driver.fixture_action('renameForRanking', 'A'); titles['A'] = 'i---n---b'
    driver.fixture_action('renameForRanking', 'C'); titles['C'] = 'Inbox'
    open_chooser('empty query retains admission order before ranking')
    driver.chooser_query('inb')
    rows[:] = ['C', 'A']
    check('contiguous title ranks ahead of earlier scattered admission', query='inb')
    # Cmd2 must use visible rank, not admission ordinal: rank2 is exact A.
    select('chooserCmd2', 'A', focus='A', frames=frames)
    rows[:] = ['A', 'C']
    open_chooser('empty query restores admission order after ranked selection')
    driver.hotkey('chooserCancel'); check('ranked query cancellation', visible=False, focus='A')
    driver.fixture_action('focus', 'A')
    check('native focus does not reorder', visible=False, focus='A')
    open_chooser('title update armed')
    driver.fixture_action('renameToManaged', 'A'); titles['A'] = '10bucks managed A'
    check('live visible title update')
    driver.fixture_action('renameToManaged', 'C'); titles['C'] = '10bucks managed C'
    check('second live title update')
    driver.chooser_query('fxtr')  # app Fixture only; neither managed title matches
    check('fuzzy application includes both renamed rows', query='fxtr')
    driver.hotkey('chooserCancel'); check('title cancellation', visible=False, focus='A')
    before = check('layout receipt baseline', visible=False)
    driver.hotkey('cycleLayout')
    check('stack native geometry', visible=False,
          receipt=('cycleLayout', before.commands_received.get('cycleLayout', 0)+1),
          frames={**frames, 'A': area, 'C': area})
    open_chooser('layout does not reorder')
    driver.hotkey('chooserCancel'); check('layout cancellation', visible=False)

    # Retained scopes: create D on existing D2, then select A from the real UI.
    before = check('D2 receipt baseline', visible=False)
    driver.hotkey('focusDesktop2')
    check('native D2', visible=False, desktop='D2', receipt=('focusDesktop2', before.commands_received.get('focusDesktop2',0)+1))
    driver.create('D'); rows.append('D')
    check('D2 native admission', visible=False, focus='D', desktop='D2', frames={**frames,'A':area,'C':area,'D':area})
    open_chooser('global retained admission order')
    select('chooserEnter', 'A', focus='A', desktop='D1')

    # Availability setup is explicit stimulus, not a focus repair. Baseline
    # actual focus is captured only after each lifecycle change has stabilized.
    for disable, enable, field in (('minimize','unminimize','minimized'),
                                   ('hide','unhide','hidden'),
                                   ('enterFullscreen','exitFullscreen','fullscreen')):
        if field == 'minimized':
            driver.fixture_action('focus', 'C')
            check('planned background minimize source stimulus', visible=False, focus='C', desktop='D1')
        if field == 'fullscreen':
            driver.fixture_action('focus', 'A')
            check('planned fullscreen source stimulus', visible=False, focus='A', desktop='D1')
        driver.fixture_action(disable, 'A')
        before = check(disable + ' native state', visible=False, native={'A': {field: True}})
        open_chooser(disable + ' remains listed')
        # A stays visible row1 but step4 MUST NOT restore it.
        select('chooserEnter', 'A', accepted=False, reason='chooser-restoration-deferred',
               focus=before.focused, frames=before.frames, native={'A': {field: True}})
        driver.fixture_action(enable, 'A')
        check(enable + ' native state', visible=False, native={'A': {field: False}})
        open_chooser(enable + ' order retained')
        driver.hotkey('chooserCancel'); check(enable + ' cancellation', visible=False)

    check('restored active native geometry and exact retained D2 boundary', visible=False,
          final_geometry={'A': area, 'C': area, 'B': frames['B']})
    driver.close('C'); rows.remove('C'); closed.append('C')
    check('authoritative native close', visible=False)
    open_chooser('close removes only C')
    # Leave the native UI open deliberately: ordinary runner finally cleanup
    # must hide/delete it and release default restoration bookkeeping.

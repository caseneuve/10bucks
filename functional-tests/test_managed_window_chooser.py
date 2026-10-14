import copy
import importlib.util
from pathlib import Path
import unittest
from dataclasses import replace
from scenarios.managed_window_chooser import checkpoint
from scenarios.columns_close_recovery import Frame, Observation


class ChooserOracle(unittest.TestCase):
    def observation(self):
        return Observation(1, 1., 1., {'A': Frame(0, 0, 100, 100)}, 'A',
            frozenset(), frozenset('A'), {'chooseWindow': 1}, {'chooser': {
                'visible': True, 'query': '', 'nativeSnapshot': {'runMatch': True, 'pidMatch': True, 'age': .05, 'sequence': 1, 'sampled_at': 1.}, 'rows': [
                    {'alias': 'A', 'text': '10bucks fixture A', 'subText': '10bucks Fixture'},
                    {'alias': 'C', 'text': '10bucks fixture C', 'subText': '10bucks Fixture'}],
                'completions': [{'alias': 'A', 'accepted': True}],
                'native': {'A': {'minimized': True}}}, 'nativeDesktop': {'active': 'D1'}})

    def test_negative_outcomes(self):
        predicate = checkpoint('AC', focus='A', frames={'A': Frame(0,0,100,100)},
            completion=[{'alias': 'A', 'accepted': True}], receipt=('chooseWindow',1),
            desktop='D1', native={'A': {'minimized': True}})
        self.assertTrue(predicate(self.observation()))
        for fault in ('order','excluded','identity','title','app','query','completion','focus',
                      'frame','availability','receipt','desktop','closed','visible'):
            o = copy.deepcopy(self.observation()); d = o.diagnostics['chooser']
            if fault == 'order': d['rows'].reverse()
            if fault == 'excluded': d['rows'].append(dict(d['rows'][0], alias='B'))
            if fault == 'identity': d['rows'][0]['alias'] = 'unknown'
            if fault == 'title': d['rows'][0]['text'] = 'stale'
            if fault == 'app': d['rows'][0]['subText'] = 'wrong'
            if fault == 'query': d['query'] = 'stale'
            if fault == 'completion': d['completions'][0]['alias'] = 'C'
            if fault == 'focus': o = replace(o, focused='C')
            if fault == 'frame': o.frames['A'] = Frame(0,0,50,100)
            if fault == 'availability': d['native']['A']['minimized'] = False
            if fault == 'receipt': o.commands_received['chooseWindow'] = 0
            if fault == 'desktop': o.diagnostics['nativeDesktop']['active'] = 'D2'
            if fault == 'closed': o = replace(o, closed=frozenset('C'))
            if fault == 'visible': d['visible'] = False
            self.assertFalse(predicate(o), fault)

    def test_unavailable_rejection(self):
        o = self.observation(); o.diagnostics['chooser']['visible'] = False
        result = {'alias': 'A', 'accepted': False, 'reason': 'chooser-restoration-deferred'}
        o.diagnostics['chooser']['completions'] = [result]
        predicate = checkpoint([], visible=False, completion=[dict(result)], focus='A',
                               native={'A': {'minimized': True}})
        self.assertTrue(predicate(o))
        result['accepted'] = True
        self.assertFalse(predicate(o))

    def test_accepted_same_target_requires_confirmation(self):
        o = self.observation()
        d = o.diagnostics['chooser']; d['visible'] = False; d['pending'] = False
        predicate = checkpoint([], visible=False, focus='A', pending=False,
                               completion=[{'alias': 'A', 'accepted': True}])
        self.assertTrue(predicate(o))
        d['pending'] = True
        self.assertFalse(predicate(o))
        del d['pending']
        self.assertFalse(predicate(o))

    def test_native_snapshot_freshness_and_identity(self):
        predicate = checkpoint('AC')
        for field, value in (('age', .151), ('age', -1), ('age', None),
                             ('runMatch', False), ('pidMatch', False), ('sequence', True),
                             ('sequence', 1.5), ('sequence', 0), ('sampled_at', float('nan')),
                             ('sampled_at', float('inf')), ('age', True)):
            o = self.observation(); o.diagnostics['chooser']['nativeSnapshot'][field] = value
            self.assertFalse(predicate(o), field)
        o = self.observation(); del o.diagnostics['chooser']['nativeSnapshot']
        self.assertFalse(predicate(o))

    def test_setup_settlement_is_bounded_and_new(self):
        predicate = checkpoint('AC')
        valid = {'sequence': 2, 'afterSequence': 1, 'started': 1., 'finished': 1.5,
                 'wanted': True, 'observed': True}
        o = self.observation(); o.diagnostics['chooser']['setupSettlements'] = [dict(valid)]
        self.assertTrue(predicate(o))
        for field, value in (('sequence', 1), ('sequence', None), ('finished', 4.001),
                             ('finished', .9), ('started', float('nan')), ('observed', False), ('wanted', None)):
            o = self.observation()
            o.diagnostics['chooser']['setupSettlements'] = [dict(valid, **{field: value})]
            self.assertFalse(predicate(o), field)

    def test_fullscreen_setup_requires_stable_native_owner(self):
        predicate = checkpoint('AC')
        valid = {'field': 'fullscreen', 'sequence': 2, 'afterSequence': 1,
                 'started': 1., 'finished': 2., 'wanted': True, 'observed': True,
                 'nativeOwnerMatch': True, 'nativeOwnerStableSeconds': .25}
        o = self.observation(); o.diagnostics['chooser']['setupSettlements'] = [valid]
        self.assertTrue(predicate(o))
        for field, value in (('nativeOwnerMatch', False), ('nativeOwnerMatch', None),
                             ('nativeOwnerStableSeconds', .249), ('nativeOwnerStableSeconds', None)):
            o = self.observation(); o.diagnostics['chooser']['setupSettlements'] = [dict(valid, **{field:value})]
            self.assertFalse(predicate(o), field)

    def test_final_active_geometry_keeps_exact_live_scope(self):
        area = Frame(0,0,100,100)
        o = replace(self.observation(), frames={'A':area,'B':area,'C':area,'D':Frame(10,10,60,50)})
        o.diagnostics['chooser']['visible'] = False
        o.diagnostics['chooser']['native'] = {a:{'identityMatch':True} for a in 'ABCD'}
        o.diagnostics['retained'] = {'D2':{'order':['D'],'active':False}}
        predicate = checkpoint([], visible=False, final_geometry={a:area for a in 'ABC'})
        self.assertTrue(predicate(o))
        for fault in ('missing_live','wrong_scope','wrong_active_frame','wrong_identity'):
            bad = copy.deepcopy(o)
            if fault == 'missing_live': del bad.frames['D']
            if fault == 'wrong_scope': bad.diagnostics['retained']['D2']['order'] = []
            if fault == 'wrong_active_frame': bad.frames['A'] = Frame(0,0,50,100)
            if fault == 'wrong_identity': bad.diagnostics['chooser']['native']['D']['identityMatch'] = False
            self.assertFalse(predicate(bad), fault)
        # Ordinary geometry checkpoints still reject extra/missing frame aliases.
        self.assertFalse(checkpoint([], visible=False, frames={'A':area})(o))

    def test_ranked_visible_order_and_exact_selection(self):
        o = self.observation()
        d = o.diagnostics['chooser']; d['query'] = 'inb'
        d['rows'] = [{'alias':'C','text':'Inbox','subText':'10bucks Fixture'},
                     {'alias':'A','text':'i---n---b','subText':'10bucks Fixture'}]
        predicate = checkpoint('CA', query='inb', titles={'A':'i---n---b','C':'Inbox'})
        self.assertTrue(predicate(o))
        d['rows'].reverse()
        self.assertFalse(predicate(o))
        d['visible'] = False; d['pending'] = False
        selected = checkpoint([], visible=False, focus='A', pending=False,
                              completion=[{'alias':'A','accepted':True}])
        self.assertTrue(selected(o))
        d['completions'] = [{'alias':'C','accepted':True}]
        self.assertFalse(selected(o))
        d['visible'] = True; d['query'] = ''
        self.assertTrue(checkpoint('AC', titles={'A':'i---n---b','C':'Inbox'})(o))
        d['rows'].reverse()
        self.assertFalse(checkpoint('AC', titles={'A':'i---n---b','C':'Inbox'})(o))

    def test_cleanup_evidence(self):
        spec = importlib.util.spec_from_file_location('ft_runner', Path(__file__).with_name('run.py'))
        runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
        fields = ('chooserNativeGone','chooserReleased','chooserDefaultFocusReleased','chooserWrapperRestored')
        result = {'dropped':0, 'trace':[{}], 'cleanup':dict(ok=True, **dict.fromkeys(fields, True))}
        self.assertTrue(runner.evidence_complete(result, managed_window_chooser=True))
        for field in fields:
            for uncertain in (False, None):
                bad = copy.deepcopy(result); bad['cleanup'][field] = uncertain
                self.assertFalse(runner.evidence_complete(bad, managed_window_chooser=True), field)

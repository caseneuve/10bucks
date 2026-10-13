import unittest
from scenarios.configured_rules import checkpoint
from scenarios.columns_close_recovery import Frame, Observation


class ConfiguredRulesOracle(unittest.TestCase):
    def observation(self):
        return Observation(1, 1., 1., {'A': Frame(0, 32, 500, 600),
            'B': Frame(100, 100, 640, 508), 'C': Frame(500, 32, 500, 600)},
            'B', frozenset(), frozenset('AC'), {'focusLeftGroup': 1},
            {'order': ['A', 'C'], 'nativeDesktop': {'active':'D1','regular':['D1','D2','D3']},
             'retained': {'D1': {'order':['A','C'],'layout':'columns', 'active':True, 'layouts': {
                 'columns': {'groups':[['A'],['C']], 'selected':['A','C'], 'ratio':.5}}}}, 'configuredRules': {
                'presentationJoin': {'nativeAlias':'B','id':True,'pid':True,'appResource':True,
                    'presentationResource':True,'nativeHandle':True,'hostId':True,'hostPid':True,
                    'windowResource':False},
                'actualAlias':'B', 'actualTitleToken':'fixture-B',
                'titleTokens': {'A':'fixture-A','B':'fixture-B','C':'fixture-C'}, 'instrumented': True, 'excludedSafetyTargets': [], 'lifetimeMismatch':False, 'actions': {'A':'manage','B':'exclude','C':'manage'},
                'evaluations': {'A':1,'B':1,'C':1}, 'commits': {'A':1,'B':1,'C':1},
                'baseline': {'B': dict(x=100, y=100, w=640, h=508)},
                'effects': {'B': {'frame': 0, 'focus': 0}},
                'history': ['C', 'A'], 'titles': {'B': 'excluded', 'A':'managed','C':'managed'}, 'actualTitle': 'excluded'}})

    def test_retained_inactive_and_return(self):
        from dataclasses import replace
        o = self.observation()
        saved = dict(o.diagnostics['retained']['D1'])
        o.diagnostics['nativeDesktop']['active'] = 'D2'
        o.diagnostics['retained']['D1']['active'] = False
        o = replace(o, focused=None, managed=frozenset())
        self.assertTrue(checkpoint(Frame(0,32,1000,600),'ABC','AC',None,
                                  excluded='B',desktop='D2',retained=saved)(o))
        o.diagnostics['nativeDesktop']['active'] = 'D1'
        o.diagnostics['retained']['D1']['active'] = True
        o = replace(o, focused='B', managed=frozenset('AC'))
        returned=checkpoint(Frame(0,32,1000,600),'ABC','AC','B',excluded='B',retained=saved)
        self.assertTrue(returned(o))
        # Correct managed selection C does not authorize repairing actual B focus.
        o = replace(o, focused='C')
        o.diagnostics['configuredRules']['actualTitle']='managed'
        o.diagnostics['configuredRules']['actualAlias']='C'
        o.diagnostics['configuredRules']['presentationJoin']['nativeAlias']='C'
        o.diagnostics['configuredRules']['actualTitleToken']='fixture-C'
        self.assertFalse(returned(o))

    def test_exact_presentation_authority(self):
        matches=checkpoint(Frame(0,32,1000,600),'ABC','AC','B',excluded='B')
        # Promotion may change policy window lease, not presentation identity.
        self.assertTrue(matches(self.observation()))
        for field in ('id','pid','appResource','presentationResource','nativeHandle','hostId','hostPid'):
            o=self.observation()
            o.diagnostics['configuredRules']['presentationJoin'][field]=False
            self.assertFalse(matches(o),field)
        o=self.observation()
        o.diagnostics['configuredRules']['presentationJoin']['nativeAlias']='E'
        self.assertFalse(matches(o))

    def test_managed_target_rejection(self):
        o=self.observation()
        name='moveFocusedToOtherGroup'
        o.commands_received[name]=1
        result={'count':1,'accepted':False,'rejected':True}
        o.diagnostics['configuredRules']['commandResults']={name:result}
        matches=checkpoint(Frame(0,32,1000,600),'ABC','AC','B',excluded='B',
                           receipt=(name,1),rejected=(name,1))
        self.assertTrue(matches(o))
        result['rejected']=False
        self.assertFalse(matches(o))
        result['rejected']=True; result['count']=0
        self.assertFalse(matches(o))

    def test_evidence_and_cleanup(self):
        import importlib.util
        from pathlib import Path
        spec = importlib.util.spec_from_file_location('ft_runner', Path(__file__).with_name('run.py'))
        runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
        valid = {'dropped':0,'trace':[{}], 'cleanup':{'ok':True,'ruleResourcesCleared':True,'ruleWrappersRestored':True}}
        self.assertTrue(runner.evidence_complete(valid,configured_rules=True))
        for field in ('ok', 'ruleResourcesCleared', 'ruleWrappersRestored'):
            self.assertFalse(runner.evidence_complete(
                dict(valid, cleanup=dict(valid['cleanup'], **{field: False})), configured_rules=True), field)
        for result in (None, {}, dict(valid,dropped=1), dict(valid,dropped=False),
                       dict(valid,trace=[]), dict(valid,error='guest_controller_error'), {'dropped':0,'cleanup':{}},
                       {'dropped':0,'cleanup':{'ruleResourcesCleared':False,'ruleWrappersRestored':True}}):
            self.assertFalse(runner.evidence_complete(result,configured_rules=True))

    def test_empty_closed_actions(self):
        from dataclasses import replace
        o = self.observation()
        o = replace(o, frames={}, focused=None, closed=frozenset('ABC'), managed=frozenset())
        scope = o.diagnostics['retained']['D1']
        scope['order'] = []
        d = o.diagnostics['configuredRules']; d['actions'] = []; d['history'] = []
        matches = checkpoint(Frame(0,32,1000,600), [], [], None, closed='ABC', excluded='B')
        self.assertTrue(matches(o))
        d['actions'] = {'A':'manage'}
        self.assertFalse(matches(o))
        d['actions'] = []
        self.assertFalse(checkpoint(Frame(0,32,1000,600), [], ['A'], None, closed='BC')(o))

    def test_negatives(self):
        matches = checkpoint(Frame(0, 32, 1000, 600), 'ABC', 'AC', 'B',
                             excluded='B', receipt=('focusLeftGroup', 1))
        self.assertTrue(matches(self.observation()))
        for fault in ('frame', 'effect', 'history', 'focus', 'receipt', 'title', 'action', 'evaluation', 'commit', 'missing_commit', 'order', 'instrumentation', 'safety', 'lifetime', 'missing_titles', 'unknown_title', 'active', 'stale_closed_action', 'wrong_same_category_source', 'wrong_same_category_title'):
            o = self.observation()
            if fault == 'wrong_same_category_source': o.diagnostics['configuredRules']['actualAlias'] = 'E'
            if fault == 'wrong_same_category_title': o.diagnostics['configuredRules']['actualTitleToken'] = 'fixture-D'
            if fault == 'unknown_title': o.diagnostics['configuredRules']['actualTitle'] = 'unknown'
            if fault == 'active': o.diagnostics['retained']['D1']['active'] = False
            if fault == 'stale_closed_action': o.diagnostics['configuredRules']['actions']['E'] = 'exclude'
            if fault == 'safety': o.diagnostics['configuredRules']['excludedSafetyTargets'] = ['B']
            if fault == 'lifetime': o.diagnostics['configuredRules']['lifetimeMismatch'] = True
            if fault == 'missing_titles':
                o.diagnostics['configuredRules'].pop('actualTitle')
                o.diagnostics['configuredRules']['titles'].pop('B')
            if fault == 'action': o.diagnostics['configuredRules']['actions']['B'] = 'manage'
            if fault == 'evaluation': o.diagnostics['configuredRules']['evaluations']['B'] = 2
            if fault == 'commit': o.diagnostics['configuredRules']['commits']['B'] = 2
            if fault == 'missing_commit': o.diagnostics['configuredRules']['commits'].pop('B')
            if fault == 'order': o.diagnostics['retained']['D1']['order'] = ['C','A']
            if fault == 'instrumentation': o.diagnostics['configuredRules']['instrumented'] = False
            if fault == 'frame': o.frames['B'] = Frame(0, 32, 500, 600)
            if fault == 'effect': o.diagnostics['configuredRules']['effects']['B']['focus'] = 1
            if fault == 'history': o.diagnostics['configuredRules']['history'].append('B')
            if fault == 'focus':
                from dataclasses import replace
                o = replace(o, focused='C')
            if fault == 'receipt': o.commands_received['focusLeftGroup'] = 0
            if fault == 'title': o.diagnostics['configuredRules']['actualTitle'] = 'managed'
            self.assertFalse(matches(o), fault)

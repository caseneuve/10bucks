import copy
import unittest
from dataclasses import replace
from scenarios.columns_close_recovery import Frame, Observation
from scenarios.managed_window_chooser_cold_start import checkpoint


class ColdStartOracle(unittest.TestCase):
    def observation(self):
        area = Frame(0,0,100,100)
        return Observation(1,1.,1.,{'A':area,'B':area},'A',frozenset(),frozenset('A'),
            {'chooseWindow':1}, {'coldStart': {'setupBeforeStart':True,'startupSettled':True,
                'discoveryStatus':{'pending':False,'complete':False,'unresolvedCount':20},
                'setupOwners':{'A':'D1','B':'D2'},'startupFocusRequests':0,
                'postStartSpaces':['D1'],'exactResources':{'A':True,'B':True},'workArea':area},
                'chooser': {'visible':True,'query':'', 'nativeSnapshot': {
                    'runMatch':True,'pidMatch':True,'sequence':1,'sampled_at':1.,'age':0.}, 'rows':[
                    {'alias':a,'text':'10bucks fixture '+a,'subText':'10bucks Fixture'} for a in 'BA'],
                    'completions':[],'pending':False}, 'nativeDesktop':{'active':'D1'}})

    def test_first_open_negative_evidence(self):
        predicate = checkpoint(visible=True,receipt=('chooseWindow',1))
        self.assertTrue(predicate(self.observation()))
        for fault in ('missingB','duplicate','resource','visit','focus','owner','incomplete','lateSetup','receipt'):
            o = self.observation(); d=o.diagnostics['coldStart']; c=o.diagnostics['chooser']
            if fault=='missingB': c['rows']=c['rows'][1:]
            if fault=='duplicate': c['rows'][0]=dict(c['rows'][1])
            if fault=='resource': d['exactResources']['B']=False
            if fault=='visit': d['postStartSpaces']=['D1','D2','D1']
            if fault=='focus': d['startupFocusRequests']=1
            if fault=='owner': d['setupOwners']['B']='D1'
            if fault=='incomplete': d['startupSettled']=False
            if fault=='lateSetup': d['setupBeforeStart']=False
            if fault=='receipt': o.commands_received['chooseWindow']=0
            self.assertFalse(predicate(o),fault)

    def test_terminal_best_effort_does_not_claim_inventory_complete(self):
        predicate=checkpoint(visible=True)
        o=self.observation()
        self.assertTrue(predicate(o))  # unresolved system hints do not hide confirmed A/B
        self.assertFalse(o.diagnostics['coldStart']['discoveryStatus']['complete'])
        for field,value in (('pending',True),('pending',None),('complete',None),
                            ('unresolvedCount',-1),('unresolvedCount',True),('unresolvedCount',float('inf'))):
            bad=copy.deepcopy(o); bad.diagnostics['coldStart']['discoveryStatus'][field]=value
            self.assertFalse(predicate(bad),field)
        o.diagnostics['chooser']['rows']=o.diagnostics['chooser']['rows'][1:]
        self.assertFalse(predicate(o))  # missing ordinary B still fails

    def test_initial_focus_and_snapshot_evidence(self):
        o=self.observation(); o.diagnostics['chooser']['visible']=False
        predicate=checkpoint(visible=False)
        self.assertTrue(predicate(o))
        self.assertFalse(predicate(replace(o,focused='B')))
        wrong=copy.deepcopy(o); wrong.diagnostics['nativeDesktop']['active']='D2'
        self.assertFalse(predicate(wrong))
        for field,value in (('runMatch',False),('pidMatch',False),('sequence',True),
                ('sequence',0),('sequence',1.5),('sampled_at',float('nan')),
                ('sampled_at',float('inf')),('sampled_at',1.01),('sampled_at',.8),
                ('age',.151),('age',-1),('age',True)):
            bad=copy.deepcopy(o); bad.diagnostics['chooser']['nativeSnapshot'][field]=value
            self.assertFalse(predicate(bad),field)
        self.assertFalse(predicate(replace(o,observed_at=.9)))
        self.assertFalse(predicate(replace(o,observed_at=float('nan'))))

    def test_selected_exact_crossscope_outcome(self):
        o=self.observation(); d=o.diagnostics
        d['chooser']['visible']=False; d['chooser']['completions']=[{'alias':'B','accepted':True}]
        d['coldStart']['postStartSpaces']=['D1','D2']; d['nativeDesktop']['active']='D2'
        o=replace(o,focused='B')
        predicate=checkpoint(visible=False,selected=True)
        self.assertTrue(predicate(o))
        # Selection is a normal post-start focus request, not startup intent.
        d['instrumentation']={'counts':{'focusRequests':1}}
        self.assertTrue(predicate(o))
        bad=copy.deepcopy(o); bad.diagnostics['coldStart']['startupFocusRequests']=1
        self.assertFalse(predicate(bad))
        for fault in ('focus','pending','target','frame','space'):
            bad=copy.deepcopy(o)
            if fault=='focus': bad=replace(bad,focused='A')
            if fault=='pending': bad.diagnostics['chooser']['pending']=True
            if fault=='target': bad.diagnostics['chooser']['completions'][0]['alias']='A'
            if fault=='frame': bad.frames['B']=Frame(0,0,50,100)
            if fault=='space': bad.diagnostics['nativeDesktop']['active']='D1'
            self.assertFalse(predicate(bad),fault)

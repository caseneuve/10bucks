import unittest
from copy import deepcopy
from types import SimpleNamespace
from scenarios import desktop_creation as scenario

class CreationOracle(unittest.TestCase):
    def test_native_identity_order_type_count_and_pending_negatives(self):
        o=SimpleNamespace(diagnostics={'nativeDesktop':{'active':'D4','order':['D1','D2','D3','D4'],
            'regular':['D1','D2','D3','D4'],'types':['user']*4,'count':4},'workspace':{'active':'D4'}})
        self.assertTrue(scenario.native_matches(o,'D4',4));self.assertTrue(scenario.settled_matches(o,'D4'))
        for key,value in [('active','D1'),('order',['D2','D1','D3','D4']),('regular',['D1','D2','D4']),
                          ('types',['user','user','fullscreen','user']),('count',5)]:
            bad=deepcopy(o);bad.diagnostics['nativeDesktop'][key]=value
            self.assertFalse(scenario.native_matches(bad,'D4',4))
        for key,value in [('active','D1'),('desired','D2'),('inFlight',{'generation':1})]:
            bad=deepcopy(o);bad.diagnostics['workspace'][key]=value
            self.assertFalse(scenario.settled_matches(bad,'D4'))

    def test_duplicate_mutation_wrong_confirmation_rejections_and_late_service(self):
        rows=[{'kind':'RegularCreatePressed','at':2},{'kind':'confirmed','destination':'D4','at':3}]
        events=[{'kind':'result','name':'createDesktop','accepted':True},
                {'kind':'result','name':'createDesktop','accepted':False,'reason':'desktop-creation-pending'}]
        for name in ('focusDesktop2','focusNextDesktop','focusPreviousDesktopPosition','focusPreviousDesktop'):
            events.append({'kind':'result','name':name,'accepted':False,'reason':'desktop-creation-pending'})
        for name in ('focusPrevious','focusNext'):
            events.append({'kind':'result','name':name,'accepted':True})
        events.append({'kind':'callback','at':1})
        self.assertTrue(scenario.creation_trace_matches(rows,events))
        self.assertFalse(scenario.creation_trace_matches(rows+[rows[0]],events))
        self.assertFalse(scenario.creation_trace_matches([rows[0],dict(rows[1],destination='D2')],events))
        self.assertFalse(scenario.creation_trace_matches(rows,events[:-1]+[{'kind':'callback','at':2.1}]))
        self.assertFalse(scenario.creation_trace_matches(rows,events[:1]+events[2:]))
        bad=deepcopy(events);bad[2]['accepted']=True
        self.assertFalse(scenario.creation_trace_matches(rows,bad))

if __name__=='__main__':unittest.main()

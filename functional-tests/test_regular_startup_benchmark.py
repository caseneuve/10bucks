import copy
import unittest
from benchmarks.regular_startup import analyze


class StartupServiceOracle(unittest.TestCase):
    def test_overlap_gates_and_terminal_before_cancel(self):
        posted=[1+i*.05 for i in range(100)]
        raw=dict(receipts=[v+.01 for v in posted], status='started', cleanup={'ok':True},
                 startRequested=1.1,startReturned=1.2,preparation=[],inventory=[],metadata=[],
                 jobs=[dict(requested=1.1,returned=1.2,terminal=dict(at=1.8,startedAt=1.15,elapsedMs=500),cancelledAt=1.81,drainedAfterStop=True)])
        self.assertTrue(analyze(raw,posted)['acceptance'])
        slow=copy.deepcopy(raw);slow['receipts']=[v+.11 for v in posted]
        self.assertFalse(analyze(slow,posted)['acceptance'])
        for change in ({'terminal':None},{'cancelledAt':1.7},{'drainedAfterStop':False},
                       {'terminal':dict(at=.8,startedAt=.1,elapsedMs=500),'cancelledAt':.81}):
            invalid=copy.deepcopy(raw);invalid['jobs'][0].update(change)
            with self.assertRaises(ValueError): analyze(invalid,posted)
        with self.assertRaises(ValueError): analyze(raw,posted[:-1])
        for value in (float('nan'), True, -1):
            invalid=copy.deepcopy(raw);invalid['jobs'][0]['terminal']['elapsedMs']=value
            with self.assertRaises(ValueError): analyze(invalid,posted)
        for change in ({'startRequested':float('nan')}, {'startReturned':True}, {'startReturned':1.0}):
            invalid=copy.deepcopy(raw);invalid.update(change)
            with self.assertRaises(ValueError): analyze(invalid,posted)
        for group in ('preparation','inventory','metadata'):
            for span in ({'at':2,'finished':1},{'at':True,'finished':2},{'at':1,'finished':float('nan')}):
                invalid=copy.deepcopy(raw);invalid[group]=[span]
                with self.assertRaises(ValueError): analyze(invalid,posted)
        invalid=copy.deepcopy(raw);invalid['jobs'].append(dict(raw['jobs'][0],drainedAfterStop=1))
        with self.assertRaises(ValueError): analyze(invalid,posted)

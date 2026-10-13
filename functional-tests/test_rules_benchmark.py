import unittest

class RulesBenchmarkOracle(unittest.TestCase):
    def test_benchmark_path_budgets(self):
        from benchmarks.rules import validate_path
        from scenarios.columns_close_recovery import AcceptanceFailure
        row = dict(action='manage', ready=1., filter=1.01, commit=1.02, frame=1.03,
                   posted=2., callback=2.04, effects={'frame':1,'focus':1})
        validate_path(row)
        for change in ({'ready':None}, {'frame':None}, {'filter':.9}, {'callback':2.101}):
            with self.assertRaises(AcceptanceFailure): validate_path(dict(row, **change))
        row.update(action='exclude', effects={'frame':0,'focus':0}); row.pop('frame')
        validate_path(row)
        with self.assertRaises(AcceptanceFailure):
            validate_path(dict(row, effects={'frame':1,'focus':0}))

    def test_batch_counts_and_mode(self):
        from benchmarks.rules import validate_batch
        from scenarios.columns_close_recovery import AcceptanceFailure
        row=dict(action='manage',ready=1.,filter=1.01,commit=1.02,frame=1.03,
                 posted=2.,callback=2.04,effects={'frame':1,'focus':1})
        excluded=dict(row,action='exclude',effects={'frame':0,'focus':0})
        valid=dict(mode='cold',status='complete',samples=[row,excluded],warmup=[])
        validate_batch(valid,'cold')
        for change in ({'mode':'warm'},{'samples':[row]},{'samples':[row,row,excluded]},
                       {'warmup':[row]},{'status':'incomplete'}):
            with self.assertRaises(AcceptanceFailure): validate_batch(dict(valid,**change),'cold')

    def test_population_keeps_individual_exceedances(self):
        from benchmarks.rules import validate_path, validate_population
        from scenarios.columns_close_recovery import AcceptanceFailure
        managed = dict(action='manage', ready=1., filter=1.01, commit=1.02, frame=1.03,
                       posted=2., callback=2.04, effects={'frame':1,'focus':1})
        slow = dict(managed, frame=1.157242)
        validate_path(slow)  # valid data, including slow warmup; no per-row request gate
        excluded = dict(managed, action='exclude', effects={'frame':0,'focus':0})
        validate_population([managed]*29 + [slow] + [excluded]*30)
        with self.assertRaises(AcceptanceFailure): validate_population([slow]*5 + [excluded]*5)
        with self.assertRaises(AcceptanceFailure):
            validate_population([managed]*30 + [dict(excluded, commit=1.2)]*30)
        with self.assertRaises(AcceptanceFailure):
            validate_population([dict(managed, callback=2.06)]*30 + [excluded]*30)

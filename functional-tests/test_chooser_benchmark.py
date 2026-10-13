import copy
import unittest
from benchmarks.chooser import DEFINITION, validate_batch, validate_population, validate_row


def row():
    return dict(posted=1., receipt=1.01, showReturned=1.02, commandReturned=1.021, visible=1.025,
                servicePosted=1.03, serviceReceipt=1.04, nativeVisible=True,
                before=dict(queries=dict(globalAX=2, perWindowIcon=0), resources=dict(handles=4, applications=1, observers=4, readiness=0, windows=4, bindings=25, timers=1)),
                after=dict(queries=dict(globalAX=2, perWindowIcon=0), resources=dict(handles=4, applications=1, observers=4, readiness=0, windows=4, bindings=25, timers=1)))


def batch(mode='cold', run='one'):
    return dict(run=run, mode=mode, definition=DEFINITION, status='complete',
                samples=[row() for _ in range(10 if mode == 'warm' else 1)],
                warmup=[row()] if mode == 'warm' else [], cleanup=dict(ok=True))


class ChooserBenchmarkOracle(unittest.TestCase):
    def test_native_timestamps_and_query_budget(self):
        validate_row(row())
        for key, value in [('receipt', None), ('visible', float('nan')),
                           ('showReturned', .9), ('nativeVisible', False),
                           ('serviceReceipt', 1.131)]:
            r = row(); r[key] = value
            with self.assertRaises(ValueError): validate_row(r)
        for key in ('globalAX', 'perWindowIcon'):
            r = row(); r['after']['queries'][key] += 1
            with self.assertRaises(ValueError): validate_row(r)

    def test_required_nonnegative_integer_counters(self):
        for group in ('queries', 'resources'):
            r=row();r['before'][group]={}
            with self.assertRaises(ValueError): validate_row(r)
            for key in row()['before'][group]:
                for invalid in (-1, None, True, 1.5, float('inf')):
                    r=row();r['before'][group][key]=invalid
                    with self.assertRaises(ValueError): validate_row(r)

    def test_batch_definition_cleanup_and_quotas(self):
        validate_batch(batch(), 'cold')
        for key, value in [('definition', 'pixels'), ('status', 'failed'), ('samples', []),
                           ('warmup', [row()]), ('cleanup', {'ok':False})]:
            b = batch(); b[key] = value
            with self.assertRaises(ValueError): validate_batch(b, 'cold')
        with self.assertRaises(ValueError): validate_batch(batch(), 'warm')

    def test_fixed_p95_gates_and_labeled_warmup(self):
        b = batch('warm'); b['warmup'][0]['receipt']=1.15
        b['warmup'][0]['showReturned']=1.19; b['warmup'][0]['commandReturned']=1.195; b['warmup'][0]['visible']=1.2
        b['warmup'][0]['servicePosted']=1.21; b['warmup'][0]['serviceReceipt']=1.22
        validate_batch(b, 'warm')  # retained but not pooled
        b['samples'][0].update(visible=1.2, servicePosted=1.21, serviceReceipt=1.22)
        with self.assertRaises(ValueError): validate_batch(b, 'warm')
        b=batch('warm')
        for r in b['samples']: r['serviceReceipt']=1.09
        with self.assertRaises(ValueError): validate_batch(b, 'warm')

    def test_three_warm_five_fresh_cold(self):
        batches=[batch('warm' if i<3 else 'cold', str(i)) for i in range(8)]
        result=validate_population(batches)
        self.assertEqual(result['warm']['invocationToVisible']['count'],30)
        self.assertEqual(result['cold']['invocationToVisible']['count'],5)
        with self.assertRaises(ValueError): validate_population(batches[:-1])
        duplicate=copy.deepcopy(batches);duplicate[-1]['run']=duplicate[0]['run']
        with self.assertRaises(ValueError): validate_population(duplicate)

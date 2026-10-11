"""Modeled bar gate regressions; no native/pixel evidence."""
import copy
import unittest

from bar_capture import BarGate


def sample(sid=1, at=1.0, showing=True):
    return {'sample_id': sid, 'sampled_at': at, 'observed_at': at + 0.01,
            'bar': {'requested': True, 'showing': showing, 'handoff': not showing,
                    'pointerTracking': not showing,
                    'frame': {'x': 10, 'y': 20, 'w': 100, 'h': 32},
                    'pointer': {'x': 30, 'y': 100 if showing else 25}}}


class BarChecks(unittest.TestCase):
    def test_stable_outside_and_inside(self):
        for showing in (True, False):
            gate = BarGate(sample(showing=showing), showing, 1)
            for i in range(1, 8):
                ready = gate.accept(sample(i + 1, 1 + i * .05, showing), 1 + i * .05)
                self.assertEqual(ready, i >= 6)
            gate.after_capture(sample(9, 1.4, showing), 1.4)

    def test_invalid_samples_rejected(self):
        for field, value in (('sample_id', 1), ('sample_id', 0),
                             ('sampled_at', 1), ('sampled_at', .9),
                             ('sampled_at', float('nan')),
                             ('observed_at', float('inf')),
                             ('observed_at', 1.0), ('observed_at', 1.3)):
            with self.subTest(field=field, value=value):
                gate = BarGate(sample(), True, 1)
                bad = sample(2, 1.05)
                bad[field] = value
                with self.assertRaises(RuntimeError):
                    gate.accept(bad, 1.05)

    def test_host_acquisition_and_delivery_gaps_rejected(self):
        for value, host in ((sample(2, 1.05), 1.2),
                            (sample(2, 1.2), 1.05),
                            (dict(sample(2, 1.05), observed_at=1.18), 1.05)):
            with self.subTest(value=value, host=host):
                with self.assertRaises(RuntimeError):
                    BarGate(sample(), True, 1).accept(value, host)

    def test_pre_action_sample_cannot_pass(self):
        baseline = sample(100, 10)
        with self.assertRaises(RuntimeError):
            BarGate(baseline, True, 10).accept(sample(99, 9.95), 10.05)

    def test_pointer_must_match_actual_frame(self):
        for showing in (True, False):
            gate = BarGate(sample(showing=showing), showing, 1)
            for i in range(1, 10):
                bad = sample(i + 1, 1 + i * .05, showing)
                bad['bar']['pointer']['y'] = 25 if showing else 100
                self.assertFalse(gate.accept(bad, 1 + i * .05))

    def test_postcapture_change_or_replay_fails(self):
        for defect in ('pointer', 'showing', 'replay', 'gap'):
            with self.subTest(defect=defect):
                gate = BarGate(sample(), True, 1)
                value = sample(2, 1.05)
                if defect == 'pointer': value['bar']['pointer']['y'] = 25
                if defect == 'showing': value['bar']['showing'] = False
                if defect == 'replay': value = copy.deepcopy(gate.last)
                if defect == 'gap': value = sample(2, 1.3)
                with self.assertRaises(RuntimeError):
                    gate.after_capture(value, 1.05)


if __name__ == '__main__':
    unittest.main()

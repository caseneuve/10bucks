"""Validator lifetimes: provisional discovery is not an admitted close fact."""
import copy
import unittest
from scenarios.close_recovery_investigation import ordering_valid


class OrderingTests(unittest.TestCase):
    def result(self):
        rows = [
            {'at': 1, 'id': 'C', 'kind': 'ActualFocusChanged', 'joinedLifetime': False},
            {'at': 2, 'id': 'D', 'kind': 'ActualFocusChanged'},
            {'at': 4, 'id': 'E', 'kind': 'ActualFocusChanged', 'joinedLifetime': False},
            {'at': 5, 'id': 'C', 'kind': 'ActualFocusChanged'},
            {'at': 6, 'id': 'E', 'kind': 'WindowDestroyed'},
            {'at': 7, 'id': 'D', 'kind': 'WindowDestroyed'},
        ]
        for i, row in enumerate(rows, 1):
            row.update(sequence=i, boundary='windows.normalized', exactResource=True)
            row.setdefault('joinedLifetime', True)
        return {'closeOrdering': rows, 'closeOrderingDropped': 0}

    def test_provisional_creation_remains_unjoined(self):
        result = self.result()
        before = copy.deepcopy(result)
        self.assertTrue(ordering_valid(result, 'normal', 4.5))
        self.assertEqual(result, before)

    def test_unjoined_decisive_c_rejected(self):
        result = self.result()
        result['closeOrdering'][3]['joinedLifetime'] = False
        self.assertFalse(ordering_valid(result, 'normal', 4.5))

    def test_unjoined_close_e_or_d_rejected(self):
        for index in (4, 5):
            result = self.result()
            result['closeOrdering'][index]['joinedLifetime'] = False
            self.assertFalse(ordering_valid(result, 'normal', 4.5))

    def test_missing_or_late_boundary_rejected(self):
        self.assertFalse(ordering_valid(self.result(), 'normal', None))
        self.assertFalse(ordering_valid(self.result(), 'normal', 8))

    def test_drops_and_regressing_clocks_rejected(self):
        result = self.result()
        result['closeOrderingDropped'] = 1
        self.assertFalse(ordering_valid(result, 'normal', 4.5))
        result = self.result()
        result['closeOrdering'][3]['at'] = 1
        self.assertFalse(ordering_valid(result, 'normal', 4.5))

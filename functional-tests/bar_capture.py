"""Pure freshness/pointer gate for native bar capture (not pixel acceptance)."""
import math

GAP = 0.15
STABLE = 0.25


def finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def matches(value, showing):
    bar = value['bar']
    frame, pointer = bar['frame'], bar['pointer']
    if not all(finite(frame[k]) for k in ('x', 'y', 'w', 'h')) or not all(
            finite(pointer[k]) for k in ('x', 'y')) or frame['w'] <= 0 or frame['h'] <= 0:
        raise RuntimeError('bar invalid native geometry')
    inside = (frame['x'] <= pointer['x'] < frame['x'] + frame['w']
              and frame['y'] <= pointer['y'] < frame['y'] + frame['h'])
    return (bar['requested'] is True and bar['showing'] is showing
            and bar['handoff'] is (not showing)
            and bar['pointerTracking'] is (not showing) and inside is (not showing))


class BarGate:
    def __init__(self, baseline, showing, now):
        self.showing = showing
        self.last = baseline
        self.last_host = now
        self.since = None
        self.validate(baseline)

    @staticmethod
    def validate(value):
        sid, acquired, delivered = (value[k] for k in ('sample_id', 'sampled_at', 'observed_at'))
        if (not isinstance(sid, int) or isinstance(sid, bool) or sid < 0
                or not finite(acquired) or not finite(delivered)
                or not 0 <= delivered - acquired <= GAP):
            raise RuntimeError('bar invalid or stale native sample')

    def accept(self, value, now):
        self.validate(value)
        old = self.last
        if (not finite(now) or not 0 <= now - self.last_host <= GAP
                or value['sample_id'] <= old['sample_id']
                or not 0 < value['sampled_at'] - old['sampled_at'] <= GAP
                or not 0 <= value['observed_at'] - old['observed_at'] <= GAP):
            raise RuntimeError('bar replayed, nonmonotonic or gapped sample')
        self.last, self.last_host = value, now
        if matches(value, self.showing):
            if self.since is None:
                self.since = value['sampled_at']
            return value['sampled_at'] - self.since >= STABLE
        self.since = None
        return False

    def after_capture(self, value, now):
        # Runner continues sampling throughout capture: no freshness gap waiver.
        self.accept(value, now)
        if not matches(value, self.showing):
            raise RuntimeError('bar changed after capture')

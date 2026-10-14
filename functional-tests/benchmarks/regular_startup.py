"""Offline startup service oracle; coordinator owns freeze and independent sender.

Fixed procedure (one run, not a 30-startup quota): freeze candidate including native
binaries, this observer/analyzer, existing desktop-key-sender.c and its executed
binary with SHA256 manifest. Empty owned guest. Verify no candidate/observer busy;
clear lib.* modules. Load observer; arm({sourceRoot=..., outputFile=..., run=...}).
Start existing independent C sender (100 unmodified Y events over five seconds)
with posted timestamps file. After initial calibration receipt, call start().
After sender normal exit and all 100 receipts, call finish(); allow <=5s drain.
Never cancel before recording terminal worker poll. Every command <=120 seconds.
Analyze raw JSON and sender timestamps with this file; host summary is separate.

Gates: actual worker overlap required; paired key service p95<=50ms/max<=100ms.
Report cold-image preparation separately (also inclusive service); do not remove
slow samples. Metadata/inventory spans are main-thread costs, not worker elapsed.
No functional/native-window acceptance claim or physical-host performance claim.
"""
import argparse
import json
import math
from pathlib import Path


def analyze(raw, posted):
    def clock(value):
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise ValueError('invalid numeric clock')
        return value
    def span(row, start='at', end='finished'):
        if clock(row[start]) > clock(row[end]):
            raise ValueError('reversed clock span')
    span(raw, 'startRequested', 'startReturned')
    for group in ('preparation', 'inventory', 'metadata'):
        for item in raw[group]: span(item)
    received = raw['receipts']
    if len(posted) != 100 or len(received) != 100:
        raise ValueError('100 posted and received events required')
    for values in (posted, received):
        if any(not math.isfinite(clock(v)) for v in values) or any(a >= b for a,b in zip(values,values[1:])):
            raise ValueError('invalid/nonmonotonic timestamps')
    delays = [1000*(b-a) for a,b in zip(posted,received)]
    if min(delays) < 0:
        raise ValueError('receipt precedes post')
    jobs = raw.get('jobs', [])
    overlaps = []
    for job in jobs:
        terminal = job.get('terminal')
        if not terminal or job.get('drainedAfterStop') is not True:
            raise ValueError('missing terminal job before cancellation/drain')
        span(job, 'requested', 'returned')
        start = clock(terminal['startedAt']); elapsed = clock(terminal['elapsedMs'])
        end = start + elapsed/1000
        if not job['requested'] <= start <= end <= clock(terminal['at']) <= clock(job['cancelledAt']):
            raise ValueError('invalid worker terminal/cancellation order')
        overlaps.extend(i for i,(a,b) in enumerate(zip(posted,received)) if start <= a < end and b >= start)
    if not overlaps:
        raise ValueError('no real native worker overlap; inconclusive service run')
    if raw.get('status') != 'started' or not raw.get('cleanup', {}).get('ok'):
        raise ValueError('startup or cleanup failed')
    def stats(values):
        ordered=sorted(values)
        return dict(count=len(values), median=ordered[math.ceil(len(values)*.5)-1],
                    p95=ordered[math.ceil(len(values)*.95)-1], maximum=max(values))
    result=dict(service=stats(delays), workerOverlapService=stats([delays[i] for i in sorted(set(overlaps))]),
                coldImagePreparation=raw['preparation'], inventory=raw['inventory'],
                metadata=raw['metadata'], jobs=jobs,
                startRequestToReturnMs=1000*(raw['startReturned']-raw['startRequested']))
    result['acceptance']=result['service']['p95']<=50 and result['service']['maximum']<=100
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('raw', type=Path);p.add_argument('posted', type=Path);p.add_argument('summary', type=Path)
    args=p.parse_args()
    result=analyze(json.loads(args.raw.read_text()), [float(s) for s in args.posted.read_text().splitlines()])
    with args.summary.open('x') as f: json.dump(result,f,indent=2);f.write('\n')
    if not result['acceptance']: raise SystemExit('startup service gate failed; inspect before rerun')


if __name__=='__main__': main()

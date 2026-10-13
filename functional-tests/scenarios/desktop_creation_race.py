"""Owned external-create interference, not manager deletion acceptance."""
import time
from scenarios.columns_close_recovery import sampling_gate
SCENARIO_ID='desktop-creation-race'
INVARIANTS=('SPACE-003','SPACE-009','CMD-006','STATE-002')
def run(driver, *, clock=time.monotonic,sleep=time.sleep):
    driver.preflight();gate=sampling_gate(driver,scenario_id=SCENARIO_ID,clock=clock,sleep=sleep)
    last=gate('three native baseline',lambda o:o.diagnostics.get('nativeDesktop',{}).get('regular')==['D1','D2','D3']
              and o.diagnostics.get('nativeDesktop',{}).get('active')=='D1')
    start=len(last.diagnostics.get('workspaceTrace',[]))
    driver.action('createDesktopRace')
    gate('external race produces two actual regular identities',lambda o:
         o.diagnostics.get('nativeDesktop',{}).get('regular')==['D1','D2','D3','D4','D5']
         and o.diagnostics.get('workspace',{}).get('inFlight',{}).get('invalidated') is True)
    def settled(o):
        n=o.diagnostics.get('nativeDesktop',{});w=o.diagnostics.get('workspace',{});rows=o.diagnostics.get('workspaceTrace',[])[start:]
        return (n.get('regular')==['D1','D2','D3','D4','D5'] and n.get('active') in ('D1','D4')
                and not w.get('inFlight') and not w.get('desired')
                and sum(r['kind']=='RegularCreatePressed'for r in rows)==1
                and not any(r['kind']=='createRegularSpace'for r in rows[1:])
                and (any(r['kind']=='RegularSwitchTimedOut'for r in rows)
                     or any(r['kind']=='RegularSwitchFailed'for r in rows)))
    gate('two native additions revoke owned creation without duplicate mutation',settled)

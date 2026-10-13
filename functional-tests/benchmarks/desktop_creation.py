"""Existing desktop benchmark owner; behavior criteria remain in scenarios."""
from scenarios.desktop_creation import *

def benchmark(driver, *, mode, clock=time.monotonic, sleep=time.sleep):
    from benchmarks.desktop_switching import nearest_rank
    driver.preflight();gate=sampling_gate(driver,scenario_id=SCENARIO_ID+'-benchmark',clock=clock,sleep=sleep)
    last=gate('native D1 baseline',lambda o:o.diagnostics.get('nativeDesktop',{}).get('regular')==['D1','D2','D3']
              and o.diagnostics.get('nativeDesktop',{}).get('active')=='D1')
    samples=[];before=last.diagnostics.get('instrumentation')
    total=11 if mode=='warm' else 1
    for i in range(total):
        events_start=len(last.diagnostics.get('keyEvents',[]));trace_start=len(last.diagnostics.get('workspaceTrace',[]))
        count=last.commands_received.get('createDesktop',0)
        driver.hotkey_burst(('createDesktop','benignService'))
        target='D'+str(4+i)
        last=gate('one new active '+target,lambda o:o.diagnostics.get('nativeDesktop',{}).get('active')==target
                  and len(o.diagnostics.get('nativeDesktop',{}).get('regular',[]))==4
                  and not o.diagnostics.get('workspace',{}).get('inFlight')
                  and o.commands_received.get('createDesktop',0)==count+1)
        events=last.diagnostics['keyEvents'][events_start:];trace=last.diagnostics['workspaceTrace'][trace_start:]
        def one(rows,kind,name=None):
            found=[r for r in rows if r['kind']==kind and (name is None or r.get('name')==name)]
            assert len(found)==1,(kind,name,len(found));return found[0]['at']
        post=one(events,'posted','createDesktop');request=one(trace,'createRegularSpace')
        benign=one(events,'callback','benignService')-one(events,'posted','benignService')
        sample={'requestMs':(request-post)*1000,'benignMs':benign*1000,
                'completionMs':(one(trace,'confirmed')-post)*1000}
        if mode=='cold' or i: samples.append(sample)
        driver.hotkey('focusDesktop1')
        last=gate('return baseline before owned test cleanup',lambda o:o.diagnostics.get('nativeDesktop',{}).get('active')=='D1'
                  and not o.diagnostics.get('workspace',{}).get('inFlight'))
        # Test setup only, never a manager deletion command.
        driver.action('removeCreatedDesktop')
        last=gate('owned empty created desktop removed',lambda o:o.diagnostics.get('nativeDesktop',{}).get('regular')==['D1','D2','D3'])
    record={'mode':mode,'samples':samples,'instrumentationBefore':before,'instrumentationAfter':last.diagnostics.get('instrumentation')}
    driver.benchmark_record(record)
    assert nearest_rank([s['requestMs']for s in samples],.95)<=50
    assert nearest_rank([s['benignMs']for s in samples],.95)<=50 and max(s['benignMs']for s in samples)<=100

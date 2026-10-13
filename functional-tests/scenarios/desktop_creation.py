"""Native creation acceptance; independent identity/order and retained layouts."""
import time
from collections import Counter
from scenarios.columns_close_recovery import Frame, sampling_gate, same_frame
from scenarios.desktop_switching import retained
SCENARIO_ID='desktop-creation'
INVARIANTS=('SPACE-001','SPACE-002','SPACE-003','SPACE-005','CMD-006','STATE-002','LAY-003','WIN-002')

def native_matches(o,target,count):
    n=o.diagnostics.get('nativeDesktop',{})
    names=['D'+str(i) for i in range(1,count+1)]
    return (n.get('active')==target and n.get('regular')==names and n.get('order')==names
            and n.get('types')==['user']*count and n.get('count')==count)

def settled_matches(o,target):
    w=o.diagnostics.get('workspace',{})
    return w.get('active')==target and not w.get('inFlight') and not w.get('desired')

def creation_trace_matches(rows,events):
    if sum(r['kind']=='RegularCreatePressed'for r in rows)!=1:return False
    if [r.get('destination')for r in rows if r['kind']=='confirmed']!=['D4']:return False
    if any(r['kind']in ('RegularSwitchFailed','RegularSwitchTimedOut')for r in rows):return False
    results=[r for r in events if r['kind']=='result']
    creates=[r for r in results if r['name']=='createDesktop']
    if [r['accepted']for r in creates]!=[True,False] or creates[1].get('reason')!='desktop-creation-pending':return False
    for name in ('focusDesktop2','focusNextDesktop','focusPreviousDesktopPosition','focusPreviousDesktop'):
        values=[r for r in results if r['name']==name]
        if len(values)!=1 or values[0]['accepted'] or values[0].get('reason')!='desktop-creation-pending':return False
    for name in ('focusPrevious','focusNext'):
        values=[r for r in results if r['name']==name]
        if len(values)!=1 or not values[0]['accepted']:return False
    press=next(r['at']for r in rows if r['kind']=='RegularCreatePressed')
    return all(r['at']<press for r in events if r['kind']=='callback')

def run(driver, *, clock=time.monotonic, sleep=time.sleep):
    area=driver.preflight()
    gate=sampling_gate(driver,scenario_id=SCENARIO_ID,clock=clock,sleep=sleep)
    native=native_matches
    settled=settled_matches
    last=gate('three regular baseline',lambda o:native(o,'D1',3) and settled(o,'D1') and not o.managed)
    for alias in 'ABC':
        driver.create(alias)
        last=gate('fixture '+alias,lambda o,alias=alias:o.focused==alias and alias in o.managed and native(o,'D1',3))
    for command in ('resizeRight','cycleLayout','cycleLayout'):
        before=last.commands_received.get(command,0);driver.hotkey(command)
        last=gate(command,lambda o:o.commands_received.get(command,0)==before+1 and o.focused=='C')
    saved=retained(last.diagnostics['retained']['D1'])
    def retained_ok(o):return retained(o.diagnostics.get('retained',{}).get('D1',{}))==saved
    def action(commands,target,count,created=None):
        nonlocal last
        counts=dict(last.commands_received); start=len(last.diagnostics.get('workspaceTrace',[]))
        events_start=len(last.diagnostics.get('keyEvents',[]))
        if len(commands)>1:driver.hotkey_burst(commands)
        else:driver.hotkey(commands[0])
        increments=Counter(commands)
        def matches(o):
            if not (native(o,target,count) and settled(o,target) and retained_ok(o)
                    and all(o.commands_received.get(k,0)==counts.get(k,0)+v for k,v in increments.items())):return False
            if target=='D1':
                left=Frame(area.x,area.y,area.w*.55,area.h)
                right=Frame(area.x+area.w*.55,area.y,area.w*.45,area.h)
                if o.focused!='C' or not all(same_frame(o.frames.get(a),left if a=='A' else right)for a in 'ABC'):return False
            rows=o.diagnostics.get('workspaceTrace',[])[start:]
            if any(r['kind'] in ('RegularSwitchFailed','RegularSwitchTimedOut')for r in rows):return False
            if created:
                if not creation_trace_matches(rows,o.diagnostics.get('keyEvents',[])[events_start:]):return False
            return True
        last=gate('+'.join(commands),matches)
    action(('focusDesktop9',),'D1',3)
    action(('createDesktop','createDesktop','focusDesktop2','focusNextDesktop','focusPreviousDesktopPosition',
            'focusPreviousDesktop','focusPrevious','focusNext','benignService'),'D4',4,'D4')
    action(('focusDesktop1',),'D1',4)
    action(('focusPreviousDesktop',),'D4',4)
    action(('focusPreviousDesktop',),'D1',4)
    action(('focusDesktop4',),'D4',4)
    action(('focusDesktop1',),'D1',4)
    action(('focusDesktop9',),'D1',4)
    counts=dict(last.commands_received);events_start=len(last.diagnostics['keyEvents'])
    driver.action('createDesktopService')
    def serviced(o):
        events=o.diagnostics.get('keyEvents',[])[events_start:]
        names=('focusPrevious','focusNext','cycleLayout')
        callbacks=[r for r in events if r['kind']=='callback' and r['name']in names]
        return (native(o,'D5',5) and settled(o,'D5') and retained_ok(o)
                and all(o.commands_received.get(k,0)==counts.get(k,0)+n for k,n in
                        [('createDesktop',1),('focusPrevious',2),('focusNext',2),('cycleLayout',2)])
                and len(callbacks)==6 and all(r.get('phase')in ('adding','selecting')for r in callbacks)
                and {r.get('phase')for r in callbacks}=={'adding','selecting'})
    last=gate('same-Space native focus/layout callbacks during add/selection; D5 activated',serviced)
    action(('focusDesktop1',),'D1',5)


def benchmark(driver, *, mode, clock=time.monotonic, sleep=time.sleep):
    from scenarios.desktop_switching import nearest_rank
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


def fullscreen(driver, *, clock=time.monotonic, sleep=time.sleep):
    area=driver.preflight();gate=sampling_gate(driver,scenario_id=SCENARIO_ID+'-fullscreen',clock=clock,sleep=sleep)
    gate('empty native D1',lambda o:o.diagnostics.get('nativeDesktop',{}).get('active')=='D1' and not o.managed)
    driver.create('A')
    last=gate('A native D1',lambda o:o.focused=='A' and same_frame(o.frames.get('A'),area))
    saved=retained(last.diagnostics['retained']['D1'])
    driver.fixture_fullscreen(True)
    last=gate('A native F1',lambda o:o.diagnostics.get('nativeDesktop',{}).get('active')=='F1' and o.focused=='A')
    expected=dict(saved,nativeFullscreen=['A'],unavailable=['A'])
    count=last.commands_received.get('createDesktop',0);start=len(last.diagnostics.get('workspaceTrace',[]))
    driver.hotkey('createDesktop')
    def created(o):
        n=o.diagnostics.get('nativeDesktop',{});w=o.diagnostics.get('workspace',{})
        rows=o.diagnostics.get('workspaceTrace',[])[start:]
        return (n.get('active')=='D4' and n.get('regular')==['D1','D2','D3','D4'] and n.get('count')==5
                and [a for a in n.get('order',[])if a!='F1']==['D1','D2','D3','D4']
                and w.get('active')=='D4' and not w.get('inFlight')
                and retained(o.diagnostics.get('retained',{}).get('D1',{}))==expected
                and o.commands_received.get('createDesktop',0)==count+1
                and sum(r['kind']=='RegularCreatePressed'for r in rows)==1
                and [r['destination']for r in rows if r['kind']=='confirmed']==['D4'])
    gate('fullscreen source creates and focuses D4; exact saved slot retained',created)
    driver.hotkey('focusDesktop1')
    gate('return D1 with A still fullscreen',lambda o:o.diagnostics.get('nativeDesktop',{}).get('active')=='D1'
         and retained(o.diagnostics.get('retained',{}).get('D1',{}))==expected)
    driver.fixture_fullscreen(False)
    gate('exit actual D1 retained geometry; focus not restoration acceptance',lambda o:
         o.diagnostics.get('nativeDesktop',{}).get('active')=='D1' and same_frame(o.frames.get('A'),area)
         and o.diagnostics.get('fixtureNative',{}).get('A')=={'fullscreen':False,'spaces':['D1']})

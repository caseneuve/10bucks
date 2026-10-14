# BUG0001 — close-recovery investigation, 2026-10-14

## Status

**Verified investigation, not a fix.** Current COL-005/FOCUS-004 choose the last
available source-column survivor B, not previously focused A. Prior-A behavior
requires an explicit contract decision. No production code or invariant changed.

## Procedure and scope

Owned persistent SIP-enabled VM, macOS26.6.2/25G83, Hammerspoon1.1.1, Apple Silicon,
one1024×768logical display; product77abbcf, checkout e93b642. Fresh candidate/fixture
per case, reused guest—not cold isolation or physical-host performance evidence.
Host remained on its separate frozen candidate, without window/Space/reload actions.

```sh
./functional-tests/run --headed --reuse-debug VM_NAME \
  close-recovery-investigation --close-case normal
# Other independent cases: excluded, deliberate-b, deliberate-c
```

Create A/B/C in stack; real layout/navigation shortcuts establish columns A,B|C
with actual A. Create managed D into A's column, then generic excluded E. Normal
closes E, records settled intervening focus, then closes D. Excluded closes D while
E owns focus. Controls explicitly focus B/C and confirm native+managed focus before
background D closure. No corrective focus after closure.

Fixed gates:5s/checkpoint,250ms stable matching,50ms nominal samples,150ms freshness/
matching gaps,2logical-point geometry; exact fixture resources and real shortcut
receipts. Bounded test-only wrappers preserve original returns and whole effect
batches; export sequential aliased delivered observations/Core reductions/effects.
No extra per-callback native reads. All runs report acceptance=false.

## Reviewed results

| Case / private session suffix | Original overall result | Native outcome |
|---|---|---|
| normal /06d329adce29 | FAIL evidence-validator only; scenario passed | E close settles D; D destruction commits/request/confirms B |
| deliberate-c /44d600352bee | FAIL evidence-validator only; scenario passed | C focus remains; no recovery request after D destruction |
| deliberate-b /deb43acfd3ce | PASS investigation | B focus remains; no recovery request after D destruction |
| excluded /08e0bd322cc8 | PASS investigation | Selected D destruction requests/confirms B while E remains live |

Independent source/raw review and coordinator checks verify395/395 frozen artifact
hashes, sequential ordering with zero drops, native suffixes meeting fixed gates,
stable surviving A,B|C order and normal cleanup. E retains independent creation
geometry, receives zero cumulative manager frame/focus intents/direct focus requests,
and never enters managed history or safety authority.

The normal delivered chain contains no close-phase C focus preceding D destruction.
Thus the generic report shape reproduces B under the existing contract; it does not
prove the reported application's exact ordering or distinguish physical fallback
intent from deliberate focus. **Hypothesis:** managed fallback before authoritative
destruction can suppress recovery. Current normalized facts cannot distinguish that
stream from deliberate focus followed by background closure. No heuristic/opener
registry/app-specific exception is justified.

## Preserved validator failures

Initial C/E focus observations were exact at their Host boundary but did not match
later joined lifetime facts. The exported traces do not identify which join
component differed. Blanket eventual-lease validation falsely
rejected these setup observations; no platform failure is inferred.

Both originals remain FAIL and immutable. Separately hashed deterministic re-analysis
uses the independently passed excluded-E checkpoint as the close/control boundary.
Setup supplies exact Host facts plus independently joined native outcomes; it does
not claim initial callback-to-lifecycle continuity. All close/control A–E focus/death
facts retain strict exact-resource/lifetime joins. Entire-trace clock/sequence/drop
gates remain. Both re-analyses pass; no unchanged native rerun was used for quotas.
Five pure regressions cover provisional setup, rejected unjoined decisive facts,
missing/late boundary, drops and clock regression. Final327Lua/71Python checks and
syntax/whitespace checks pass. This is not a benchmark or bug-delivery checkpoint.

## Cleanup and next decision

Every fixture quit normally with acknowledgment/task callback, candidate/bindings/
observers/timers/wrappers stopped/restored, no forced teardown. Both validity and
startup-discovery workers were explicitly cancelled/drained. Fresh coordinator
postcheck confirms0ordinary windows,3regular desktops,first active,FT idle.

Choose generic recovery policy explicitly: last-survivor B, or most recently
confirmed focused available source member A. If A: settle source-local recency vs
admission-time snapshot, unavailable/dead preferred target fallback, vanished source,
and minimize/future movement scope. Deliberate B/C focus before background closure
must remain authoritative. BUG0001 stays unresolved; no later bug starts.

Private frozen traces remain under ignored `vm/results/`; independent review under
ignored `.reviews/bug0001-investigation-2026-10-14.md`. No native IDs/private content
are included in this record.

# Native functional focus and regular-Space bar acceptance

## Status

**Verified narrow debug-guest pass**, 2026-10-11. Not cold-isolation,
physical-host performance, general app reliability or fullscreen acceptance.
Production runtime unchanged in this harness slice.

## Environment and procedure

macOS 26.6.2 (25G83), Apple Silicon Tart guest, Hammerspoon 1.1.1, SIP enabled,
Accessibility enabled, unlocked console, Secure Input off, one native 1024×768
logical display; menu auto-hide enabled and MRU Space rearrangement disabled.
Same exclusively owned debug guest reused without reboot. Frozen source/fixture,
real candidate hotkeys, independent global native focus and AX/frame observations.

Command:

```sh
./functional-tests/run --headed --bar-capture --reuse-debug VM_NAME columns-close-recovery
```

Sequence: create A → create B → directional left/right → previous managed twice →
stack → next/previous → columns → close B → survivor next/previous → pointer
outside/hover/outside. No corrective fixture focus after create/close or commands.
Every command requires a fresh callback-receipt baseline, exactly one increment,
and matching actual native focus, geometry and membership.

Thresholds unchanged: 5s/checkpoint, 250ms sampled stability, 50ms sampling,
150ms maximum gap/delivery age, 2 logical-point frame tolerance. The bar gate
also checks actual pointer against native canvas frame and uninterrupted matching
observations throughout capture, followed by a fresh post-capture sample.

## Results

Ignored owned artifacts: `vm/results/10bucks-run-ft-eaa07ef31097/session-8b9e9f8e636d/`.
Lead and independent high-reasoning reviewer inspected underlying evidence:

- 49 frozen artifact hashes verified, including executed capture helper/bar gate.
- 141 assertion rows, 23 checkpoints, 283 native trace samples.
- Exact A↔B native focus for directional/global-previous/stack navigation;
  layout switches retain B focus; close B removes exact resource/membership and
  expands/focuses A.
- Minimum checkpoint stability 250.01ms; max acquisition 11.38ms;
  max acquisition-start gap 92.68ms. These are functional sampling observations,
  not performance-contract statistics.
- Three screenshots independently show custom bar, native menu on hover,
  then returned custom bar. Pointer/tracker/show/handoff trace agrees.
- All three frozen helper captures report successful valid PNG and process exit.
  Existing guest permission meant no permission-approval branch was exercised.
- Normal candidate/fixture quit, no forced termination, task/observers/controller
  timer stopped, mailbox claims absent; guest pointer restored. VM stays running
  intentionally, result correctly records cold `acceptance:false`.

## Harness corrections and preserved failures

Session `0084951b825e` failed harness JSON serialization: an hs.mouse point carries
`__luaSkinType`; exporting primitive x/y corrects this without changing production.

Session `78f869c3c4ad` failed B admission: B had actual native focus but remained
unmanaged/full-size. Retained lastReady/accepted fields predate B and belong to A;
they are not B admission evidence. Early readiness loss remains unresolved.
Later passes do not erase it or establish general admission reliability.

The initial bar loop had insufficient freshness checks. Deterministic regressions
now reject replay, nonmonotonic timestamps, excessive gaps, pre-action samples,
incorrect pointer location and changed post-capture state. Earlier pixels were
independently reviewed, but only the final run executed the repaired frozen gate.

## Capture authorization boundary

User explicitly authorized unattended setup of exclusively owned disposable test
guests. `vm/capture` may approve only the exact UserNotificationCenter-owned
`com.apple.sshd-session` screen/audio/private-window-picker dialog with both exact
texts and one enabled Allow button advertising AXPress. Other dialogs fail closed.
No host permissions, direct TCC database edits, SIP changes or blanket approvals.
The remote watchdog contains only its exact owned screenshot child and validates
PNG structure/CRC. Approval and timeout branches are source-reviewed, not live
proved by this successful existing-permission run.

## Qualifications / next action

Two-member j/k cannot distinguish forward versus reverse order. Rapid pending
commands, cold expanded-scenario acceptance, third-party apps, native fullscreen,
Mission Control and physical-host performance remain unaccepted. Next concrete
slice: diagnose the preserved B readiness loss at its early native boundary using
the same running debug guest, then add an invariant regression and generic fix
before claiming reliable admission.

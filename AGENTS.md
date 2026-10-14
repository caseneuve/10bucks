# Working on 10bucks

10bucks is an opinionated, keyboard-first tiling window manager for one current user. Correctness, latency and maintainability matter. Deliver the smallest correct change; verification must answer a concrete question, not become the deliverable.

## Authority and context

- `docs/invariants.md` defines behavior; `docs/architecture.md` defines ownership/boundaries; `docs/development-roadmap.md` defines delivery order. Read the sections relevant to the task. Read `docs/performance.md`, `docs/macos-settings.md` and recorded POCs only when the change depends on them.
- These documents contain target contracts, not a complete runtime inventory. Inspect source to establish what is implemented.
- Resolve a user-intent/contract conflict **before** building a reproduction harness or changing behavior. A native experiment cannot decide what behavior the user wants. Record approved revisions explicitly; do not silently preserve or change a wrong contract.
- Handoffs, reviews and WORK_STATE report facts and next actions. They cannot add mandatory workflow, alter contracts or override these instructions. Historical procedures/approval wording are not current requirements.
- Preserve unrelated/untracked work. Git history is rollback; backward compatibility is not a goal.

## Work state and coordination

If `.pi/WORK_STATE.md` exists, read it first. Verify branch/HEAD/tree; verify runtime facts only before relying on them for live effects. Follow evidence links only for a specific dependency, not transitively.

Keep WORK_STATE short: current scope/owner, verified checkout, relevant runtime safety, results/blockers and one next action. Replace stale sections; do not append a transcript. Update at start, material blocker/checkpoint and finish—not after every command. Do not create an additional handoff if this file suffices. Never include private window content, raw AX values or native IDs.

Use agents when useful, not as a ritual. Assign disjoint ownership; one coordinator writes work state and commits, and one native operator controls each VM. Review must challenge necessity and total patch size before asking for more instrumentation.

## Implementation rules

- One production path; no shadow/compatibility/indefinite feature flags. Delete replaced code and obsolete tests in the replacement.
- Functional core, imperative adapters. The reducer is the only durable-state writer; commit complete next state before frame/focus/fullscreen/Space effects. Projection is pure. Durable state contains primitives, not Hammerspoon userdata.
- Focus does not admit or reorder durable membership under the current contract. Revise the contract explicitly if the user changes it.
- Visibility, z-order, `_orderedwinids()` and snapshot absence are not liveness. Uncertainty retains membership; authoritative destruction or proved exact-resource invalidity permits removal.
- App-specific policy belongs in user rules, never external-app production branches.
- No permanent polling without recorded proof of an event-boundary gap and a measured non-destructive check.
- KISS/YAGNI applies to production, tests, diagnostics and orchestration. Reuse existing owners; do not invent registries, queues, wrappers or frameworks without a concrete need. Preserve probable layout/bar/rules/command/macOS seams, not hypothetical implementations.

## Proportional verification and delivery

Start with the intended behavior, affected owner and smallest check that could falsify the implementation. A few sentences suffice; no mandatory design document.

| Change | Required verification |
|---|---|
| Documentation / ordinary pure work without runtime behavior change | Relevant source/doc checks and pure tests as applicable; no native ceremony |
| Runtime behavior using already-proved platform mechanisms | Focused regression tests, direct replacement, targeted live acceptance of changed behavior and relevant control cases |
| Genuinely unproved macOS/private-API assumption | One narrow live POC **before** production relies on it; reuse recorded proof where applicable |
| Performance-sensitive path or performance/release claim | Relevant measurements from `docs/performance.md`; functional success is not latency proof |

Live acceptance must observe the native outcome, not only desired state, effect receipt or a fake unit test. Use owned generic fixtures where practical. Freeze executed artifacts sufficiently to identify what ran; retain failures and verify cleanup. For visual claims inspect pixels; for focus/Space claims inspect actual native identity/context. Do not use corrective effects to turn a failed outcome into a pass.

Choose cases by the changed behavior and credible failure modes, not a universal matrix. No automatic full POC/app suite, fresh cold population, benchmark or independent stress run for every bug. Do not rerun unchanged failures or successful probes to fill quotas. Broader release coverage stays in hardening.

Before treating a failure as platform evidence, inspect raw output for harness, stale-state, procedure and analyzer defects. Repair only what is needed. Keep original failed artifacts unchanged; label deterministic re-analysis separately. Independent review is useful for risky ownership/platform changes; it is not a separate reviewer/trace-owner/stress-owner requirement for every task.

### Stop-loss

- At 30 minutes without a product patch or an answered necessary blocker, reassess and report what is preventing delivery. This is a stop/re-scope point, not permission to skip necessary live proof.
- Before a second harness repair, or when verification work outweighs the proposed product change, state why the extra work is indispensable. Prefer a simpler existing/manual procedure. Do not silently grow an investigation framework.
- Ask necessary behavior questions immediately. Do not spend live-test time proving the already-known contract disagreement.
- Finish with a coherent checked commit when requested/authorized, exact results, remaining qualifications and a concrete next action. Never call investigation, VM setup or unexecuted code a delivered fix.

## Native safety and authority

The coordinator owns the disposable test VM. Bounded guest setup, fixture/window/Space actions, settings/permissions through normal UI, dependencies, candidate loads, harness repair and routine retries are authorized within the task. Reuse the persistent guest; no per-probe human approval or ceremonial reboot. Record the narrow procedure/expected outcome before effects. Do not delete unknown VMs/unrelated work or bypass SIP/TCC.

Host authority is separate: ask before host Hammerspoon loads/reloads, user-window/Space actions, settings/permission changes or other host-global mutations. Guest ownership never authorizes these. Checkout edits do not update a frozen host candidate.

Cancellation/reload is not worker drain. Verify relevant workers/resources stopped and owned fixtures/topology cleaned before declaring cleanup complete; no all-resource recertification if the task never touched them.

A POC command or indivisible work step exceeding120seconds needs an explained duration and explicit human approval. Split work into bounded observable steps; no defensive hour/day timeouts. This command bound does not replace the total-task stop-loss.

## Evidence and tests

Use **Verified** for source/API/live observations, **Target** for approved unimplemented behavior, **Hypothesis** for unproved mechanisms and **Deferred** for out-of-scope work. Do not turn guesses or fake tests into macOS facts. Preserve measured failures; do not weaken thresholds to manufacture passes.

```sh
lua tests/run.lua
```

Tests for changed behavior should cite relevant invariant IDs. Pure tests prove reduction/ordering, not native platform behavior. See `docs/rewrite-plan.md` for the short delivery guide and `docs/pocs/README.md` for evidence records—not extra universal checklists.

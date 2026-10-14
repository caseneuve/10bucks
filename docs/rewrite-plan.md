# Selective rewrite — delivery guide

This is the current replacement guide, not a runtime completion report. The old
planning baseline, numbered canary ladder and completed slice prescriptions have
been removed; Git history retains them. Recorded platform results remain under
`pocs/` and must not be rewritten as passes.

## Authority

- [`invariants.md`](invariants.md): intended behavior.
- [`architecture.md`](architecture.md): functional ownership and extension seams.
- [`development-roadmap.md`](development-roadmap.md): current delivery order.
- [`../AGENTS.md`](../AGENTS.md): workflow, proportional verification and authority.
- [`performance.md`](performance.md): budgets and measurement when applicable.
- [`pocs/README.md`](pocs/README.md): lookup index for platform evidence.

Read relevant sections, not every historical record. Inspect current source for
implementation status. Historical handoffs/plans cannot impose additional gates.

## Replace directly

1. Settle the behavior and any contract disagreement first.
2. Identify the existing owner/event/reducer/effect path; choose the smallest change.
3. Add focused regression coverage. Reuse proved platform assumptions; POC only
   a genuinely unproved mechanism the implementation will depend on.
4. Replace the existing path, commit state before effects, remove replaced code/tests.
5. Run targeted native acceptance for changed runtime behavior. Measure performance
   when a changed path presents a concrete latency/query/resource risk or a claim
   requires it. Do not infer native success from reducer state or effect receipts.
6. Review at the risk level of the change, verify affected-resource cleanup, then
   commit/report actual results and qualifications. Apply AGENTS stop-loss if
   verification/coordination starts displacing delivery.

There is no mandatory canary A/B/C ladder, broad application certification,
independent stress population or benchmark for every local fix. Reuse existing
procedures and evidence; do not recreate proof ceremonially. Small patches still
need real native checking when they change native behavior.

## Safety and architectural constraints

One active production implementation. No legacy delegation, compatibility façade,
shadow runtime, indefinite feature flag or app-specific engine policy. Primitive
reducer state, pure projection and imperative adapters. Observation absence is not
death. Unknown liveness remains uncertainty. No permanent polling without recorded
necessity and measured cost.

Develop without mutating the user's host runtime. Owned-VM effects follow AGENTS
standing authority; host loads/global actions require explicit authority. Stable
and candidate managers must never run together. Record the actual loaded artifact
and rollback for host deployment; editing the checkout does not deploy it. Reload
is not worker drain, and memory-only state is not layout persistence.

## Remaining work and release

Follow the roadmap, not the historical slice numbering. Reported bugs are handled
one at a time; restoration and fullscreen delivery remain separate from chooser
listing/discovery. Movement/deletion and other explicit deferrals stay deferred.

Hardening covers broader representative apps, combined sequences, supported-host
budgets and retained limitations. Earlier focused native checks remain mandatory
for behavior changes; broad release coverage is not a prerequisite to every patch.
A release requires all invariants delivered, explicitly revised or deferred, and
relevant performance/cleanup evidence. Guest results do not prove physical-host
performance. Fullscreen effects/new private native mechanisms need narrow proof
before reliance, not guessed explanations of macOS behavior.

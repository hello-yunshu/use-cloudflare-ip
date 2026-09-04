# 2.3 Roadmap

## Phase 1 — Observe

- Compare candidate-pool sizes and best K values.
- Compare target ratios for each `IP_COUNT`.
- Measure audit interval cost, expansion rate, fallback rate, winner recall,
  Top-N recall, probe savings, and wall-clock savings.
- Segment by context fingerprint and IPv4/IPv6/both.

## Phase 2 — Decide

- Determine whether the observed savings are operationally meaningful.
- Check that Native safety and recall remain within the 2.2 acceptance bounds.
- Evaluate the value of Candidate Assisted combined with Adaptive Guarded.

## Phase 3 — Implement only if justified

Any implementation requires a separately approved 2.3 scope, updated
acceptance evidence, and a new exact-head qualification cycle. No automatic
parameter tuning is implied by this roadmap.

## Explicit non-goals

No new Runtime learner, Source learner, Reuse learner, Adaptive learner,
Schema v3, Model Generation 3, auto-tuning without evidence, ML scheduler
replacement, large LuCI redesign, distributed/cloud telemetry, central server,
automatic release tuning, or benchmark project.

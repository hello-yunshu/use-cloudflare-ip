# 2.2 Adaptive Measurement

Adaptive Measurement is an evidence-gated Native probe scheduler.

## Modes

- off: use the existing full Native probe order.
- shadow: use the existing Native probe order and record no production
  influence. This is the default.
- guarded: use a deterministic subset only when fresh qualification exists.
  Qualification loss immediately returns the next run to full Native probing.

The subset is bounded by the requested IP count, a target ratio, a minimum
probe count, and a hard maximum. It includes the Native baseline anchor, the
previous healthy winner when present, family anchors for both, source/family
diversity, and deterministic exploration. Expansion probes remaining candidates
when the safe eligible count is insufficient. Corruption, contract mismatch,
probe errors, or an unqualified state fall back to the complete baseline.

## Evidence and qualification

Only complete full audits are meaningful evidence. Each record carries
runId, context fingerprint, candidate and actual probe counts, baseline/CFST/
adaptive orders, full Native winner/top-N, applied candidates, K25/K40/K60
comparison metrics, best-within-K, quality delta, severe miss, scheduler and
feature-contract versions. The bounded store keeps the last 100 valid records
and quarantines invalid or oversized data.

Qualification requires at least 50 compatible records in a 100-record window:
winner recall >= .98, top-N recall >= .95, severe miss <= .01, eligible
insufficiency <= .01, and probe savings >= .20. Evidence is stale after the
configured age, and context or scheduler-version changes invalidate it.
Negative or stale evidence downgrades to insufficient; no implicit promotion
or real-device claim is made by synthetic tests.

RPC adaptive-status, status JSON, and the LuCI Intelligence page expose the
requested/effective mode, qualification state, freshness, K, fallback, and
contract versions without presenting Shadow evidence as a production win.

# Adaptive Measurement Pre-Probe Feature Contract

Version 1 is a Native Cloudflare-IP contract. The scheduler receives only
candidate metadata available before the target-domain probe begins:

- CFST rank, IP family, candidate/source identifiers, source count, origin,
  stale flag, and source reliability;
- history median/P95/EWMA, consecutive failures, last-seen, prefix/colo
  aggregates, and the previous healthy winner;
- stable candidate ID and IP.

The scheduler must not receive probes, probeSummary, eligible, current
loss/latency/throughput, or any other target-probe result. The same normalized
input produces the same baseline, CFST, and adaptive orders. Missing values are
neutral or conservative and stale data decays toward neutral. Tie-breaking is
by CFST rank and IP.

This contract is intentionally outside Rill. It does not create a learner,
partition, state snapshot, feature schema, or feedback path.

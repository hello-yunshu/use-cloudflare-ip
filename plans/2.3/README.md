# 2.3 Adaptive Measurement — Value & Operational Tuning

2.3 is a measurement and operating-evidence stage for the released 2.2
Native deterministic scheduler. It must answer where Adaptive Measurement
reduces measurement cost without reducing Native result quality.

This directory contains the planning and acceptance boundaries for the bounded
Docker replay harness in `docker/2.3/`. The harness is evidence-only and does
not authorize automatic tuning, a new learner, or a release decision.

## Recommended start condition

Start only after 2.2 is released from an exact qualified `main` SHA and real
runtime observations are available across representative IPv4, IPv6, and both
contexts. Begin implementation only if the Go gate in `ACCEPTANCE.md` is met.

## First evidence to collect

Collect `fullCandidateCount`, `plannedK`, `actualUniqueProbeCount`,
`expansionCount`, `fallbackUsed`, `auditRun`, `measurementDuration`,
`probeSavings`, `winnerRecall`, `topNRecall`, and `contextFingerprint`, with
separate IPv4/IPv6/both and Candidate Shadow/Assisted slices.

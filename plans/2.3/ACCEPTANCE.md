# 2.3 Acceptance and Go / No-Go

## Research questions

- What K and target ratio provide useful savings at each `IP_COUNT`?
- What is the cost of periodic full audits, expansion, and fallback?
- Does the combination of Candidate Assisted and Adaptive Guarded provide
  value while Native remains the safety authority?
- Do IPv4, IPv6, both, and context-specific cohorts behave differently?

## Go gate

Proceed only when a sufficiently sized, complete evidence window shows a
repeatable operational reduction in measurement duration and probe count,
while winner recall, Top-N recall, eligible insufficiency, severe miss, and
fallback behavior remain within the released 2.2 thresholds. The evidence must
be segmented by context and must include complete full-audit records.

## No-Go gate

Do not implement 2.3 if savings are not material, evidence is censored or too
small, quality varies beyond the 2.2 safety envelope, or the result would
require a second learner, schema/model-generation change, cloud telemetry, or
automatic tuning to explain it.

## Data contract boundary

Use the 2.2 status/evidence fields first. Add a forward-compatible diagnostic
field only when the value cannot be reconstructed later and it is required for
one of the research questions. Do not add a new runtime authority or algorithm
for data collection.

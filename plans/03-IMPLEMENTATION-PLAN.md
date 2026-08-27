# Implementation plan and decisions

1. Preserve the 1.8.3 files and add executable module boundaries.
2. Install v2 as `/usr/bin/cf-ip-auto`; install the legacy file separately for compatible transformer/download helpers.
3. Add additive UCI keys for budget, CFST duration/threads/pings, probe limits, Rill and LAN publishing.
4. Build source records with `kind`, `value`, `family`, `sourceId`, `sourceClass`, `stale`, and provenance. Deduplicate by IP.
5. Allocate `floor(B/8)` history, `floor(B/4)` official exploration and the remainder community, with deficits flowing between buckets.
6. Stop proxy only after source fetch/cache, CFST preparation and input generation. Set one global deadline and pass remaining time to every critical operation.
7. Apply only after all selected candidates pass target-domain probes; commit pending managed state only after restart and post-apply validation.
8. Keep the legacy UI and add Candidate Sources and Intelligence pages. Self-update is package-managed and visibly deprecated.
9. Run independent CI jobs with `fail-fast: false`; qualification guard consumes every result.

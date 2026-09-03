# Implementation plan and decisions

1. Preserve the 1.8.3 files and add executable module boundaries.
2. Install v2 as `/usr/bin/cf-ip-auto`; install the legacy file separately for compatible transformer/download helpers.
3. Add additive UCI keys for budget, CFST duration/threads/pings, probe limits, Rill and LAN publishing.
4. Build source records with `kind`, `value`, `family`, `sourceId`, `sourceClass`, `stale`, and provenance. Deduplicate by IP.
5. Allocate `floor(B/8)` history, `floor(B/4)` official exploration and the remainder community, with deficits flowing between buckets.
6. Stop proxy only after source fetch/cache, CFST preparation and input generation. Use separate measurement and recovery deadlines, passing the measurement remainder to critical measurement operations while keeping recovery available after measurement expiry.
7. Apply only after all selected candidates pass target-domain probes; commit pending managed state only after restart and post-apply validation.
8. Keep the legacy UI and add Candidate Sources and Intelligence pages. Self-update is package-managed and visibly deprecated.
9. Run independent CI jobs with `fail-fast: false`; qualification guard consumes every result.

## 2.2 implementation additions

10. Normalize a versioned pre-probe feature contract and generate deterministic
    baseline, CFST-only, and Adaptive orders without current-run target-domain
    measurements.
11. Keep Adaptive defaulted to Shadow; persist bounded audit evidence separately
    from Candidate Rill state, and expose requested/effective mode plus fallback
    diagnostics through RPC, status JSON, and LuCI.
12. Permit Guarded subset probing only after the configured fresh qualification
    window is satisfied. Preserve minimum IP/family/source anchors, deterministic
    exploration, bounded expansion, and full Native fallback.
13. Run periodic full audits independent of evidence eviction and downgrade
    stale, incompatible, negative, corrupt, or insufficient state to Shadow.

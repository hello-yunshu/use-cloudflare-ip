# Cloudflare IP 2.0 clean-rebuild charter

## Fixed baseline and scope

The sole behavior baseline is `main` at `77a65a86a84b5fdf4cd0a854edc83a9c5c7d7fb1`, package `1.8.3`. The active development branch is project-scoped and neutral: `cloudflare-ip-2.0-dev`.

The 2.0 package is an additive rebuild. The legacy implementation remains an independently installed compatibility transformer and the original user-facing surfaces are retained. New source scheduling, observation, ranking, transactions, Rill, and LAN publication are separate responsibilities.

## Non-negotiable invariants

1. A run has one CFST process and one explicit-IP input. Official CIDRs are sampled by the scheduler; community ports and domains never become endpoint configuration.
2. `candidate_budget` is user-controlled and constrained to `100..512`; default `128`.
3. `running` retains the 1.8.3 service/scheduler meaning. `active_run` and `phase` describe an in-flight run.
4. The host transaction owns snapshots, proxy stop, transformer invocation, restart, health verification, commit, and rollback. Adapters do not restart services.
5. Target-domain probes are hard eligibility gates. If no selected candidate passes, there is no apply.
6. PassWall managed state is pending until post-apply health succeeds. OpenClash readback checks intended mapping fields, not only an IP grep.
7. Rill and LAN publishing are optional. Their failure falls back or reports degraded state without invalidating a native selection.
8. Stable release is prohibited until the release gate is evidence-generated and all required qualification jobs are green.

## Evidence vocabulary

`OPEN` means implementation or evidence is still missing. `IMPLEMENTED` means the local path exists. `TESTED` requires an executable local test and, for release claims, an exact Actions job/run and artifact. `BLOCKED` is reserved for device/platform evidence unavailable to this environment.

## Current boundary

The source, observation, transaction, package, RPC, LuCI, and local contract work is performed on the host. Real OpenWrt runtime, actual PassWall/OpenClash installations, public CFST quality, five musl executions, and hardware behavior remain qualification gates until their exact evidence is recorded.

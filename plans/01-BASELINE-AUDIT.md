# 1.8.3 baseline audit

## Files reread

The baseline review covered `cf-openwrt-auto.sh`, package `Makefile`, `/etc/config/cf_ip`, init script, rpcd shim, ACL, menu/controller, all five existing LuCI views, `utils.js`, the 245-line shared CSS, Chinese/English PO and POT, both README files, the two existing shell tests, release/cleanup workflows, conffiles, postinst and prerm.

## Behavior inventory

| Surface | 1.8.3 contract | Rebuild disposition |
|---|---|---|
| Overview | service state, speedtest state, actions, status cards, versions, environment, logs, polling/footer | KEEP + StatusV2 compatibility |
| Settings | enabled/mode/count/family, TCP/HTTP, colo, CFST limits, stop-service, startup and cron | KEEP; additive controls |
| Advanced | mirror, retries, retry delay, verbose, work dir, self-update keys | KEEP reads; self-update DEPRECATE |
| Diagnostics | bounded log/history, clear/read, environment refresh and empty/error states | KEEP |
| PassWall | domains, multiple sections/nodes, suffix `{n}`/`{ip}`, rerun, direct UCI update/restart/rollback | REIMPLEMENT transactionally |
| OpenClash | YAML config, domains, generated variants, transport filters, TLS/Host/SNI, backup CRUD/restart | REIMPLEMENT through pure transformer/readback |
| Scheduler | enable/disable, cron presets/custom, startup delay, old sync cleanup, validation | KEEP behavior; extend validation |
| Package | all arch, LMO, cache invalidation, conffiles, CFST persistence, upgrade hooks | KEEP + module install surface |

## Known baseline risks carried into contracts

The original run path invokes separate IPv4/IPv6 CFST inputs, uses permissive all-fail fallback, and owns proxy lifecycle inside the legacy flow. These are intentionally changed only in the new v2 path and are covered as explicit safety changes. Existing UI/CSS and legacy tests remain regression references.

# Service lifecycle contract

`enable`, `disable`, `start`, `stop`, `restart`, `reload`, validation, cron cleanup, startup delay, CFST persistence and status updates remain init responsibilities. A saved configuration follows structural validation -> semantic `cf-ip-auto --validate-config` -> Save -> Apply -> Restart -> wait-ready. A disabled service is a no-op and removes its plugin cron entry.

During a v2 measurement, the host transaction captures the original proxy state before stopping it. Every stop/CFST/probe/apply/restart operation consumes the same `measurement_timeout`; timeout or signal triggers rollback/recovery and never leaves the proxy intentionally disabled.

# RPC compatibility contract

The rpcd shim exposes the 1.8.3 methods (`status`, `check-env`, `refresh-env`, `run`, `speedtest-status`, `version`, logs, history, download, self-update, start/stop/restart/sync and OpenClash backup CRUD) plus `source-*`, `publisher-status`, and Rill install/remove. Backup methods are real `call` dispatches: they parse stdin JSON, pass an allow-listed ID to the backend, and return backend JSON/side effects.

`status` returns schema 2 while retaining `running`, `best_ips`, `last_run`, `last_result`, environment fields, and mode/count. `running` means enabled service/scheduler; `active_run` and `phase` describe the current task. Unknown methods and malformed IDs fail closed.

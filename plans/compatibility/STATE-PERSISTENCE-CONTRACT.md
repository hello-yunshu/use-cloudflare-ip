# State persistence contract

Persistent: UCI, `/etc/cf_ip/passwall-managed.json`, `/etc/cf_ip/rill-state.json`, source `last-good` caches and bounded run history. Temporary: `/tmp/cf_ip/run-*`, locks, probe/decision files and publisher output. Pending managed state is stored inside the active transaction and atomically replaced only after post-apply health. Corrupt JSON is quarantined or ignored with a visible warning and Native fallback; no recovery guesses a user node.

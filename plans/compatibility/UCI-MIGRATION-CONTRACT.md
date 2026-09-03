# UCI migration contract

All 1.8.3 service, PassWall and OpenClash keys remain readable. New keys are additive: `candidate_budget`, `speedtest_dt`, `speedtest_threads`, `speedtest_ping_count`, `probe_top_count`, `probe_concurrency`, `probe_timeout`, `measurement_timeout`, `builtin_sources`, `rill`, and `lan`.

The old `auto_update`/`self_update_url` values are read for migration but default to disabled in 2.0. Existing `/etc/config/cf_ip`, `/etc/cf_ip`, CFST persistence and run history survive package upgrades. Empty or invalid new values are rejected during semantic validation rather than guessed.

#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
for key in enabled mode ip_count ip_type speedtest_protocol speedtest_cfcolo speedtest_dn speedtest_tll speedtest_tl stop_service startup_delay auto_update self_update_url download_retries download_retry_delay github_mirror verbose work_dir cron_interval cron_custom cfst_persist candidate_budget speedtest_dt speedtest_threads speedtest_ping_count probe_top_count probe_concurrency probe_timeout measurement_timeout; do grep -q "option $key" "$PKG/root/etc/config/cf_ip" || fail "missing UCI key $key"; done
grep -q "option auto_update '0'" "$PKG/root/etc/config/cf_ip"
echo 'legacy UCI migration contract passed'

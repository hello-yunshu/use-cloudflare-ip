# Test evidence matrix

| Contract | Local test | Required Actions evidence | State |
|---|---|---|---|
| legacy RPC/config | `tests/legacy/*`, `tests/legacy-contract.sh` | `legacy-contract` exact SHA/job, run `33270679539` | REMOTE_TESTED |
| source parser/security | source engine + security scripts | `host-contract`, run `33270679539` | REMOTE_TESTED |
| exact input/one CFST | `v2-cfst-exact-input.sh`, `v2-single-cfst.sh` | `host-contract`, run `33270679539` | REMOTE_TESTED |
| observation/eligibility | `v2-observation.sh` | `host-contract`, run `33270679539` | REMOTE_TESTED |
| transaction/rollback | transaction and adapter tests | `legacy-contract`, `host-contract`, package jobs, run `33270679539` | REMOTE_TESTED |
| RPC dispatch | `rpc-roundtrip.sh` | `rpc-luci-contract`, run `33270679539` | REMOTE_TESTED |
| package contents | `package-conffiles.sh` | IPK/APK artifact inspection, run `33270679539` | REMOTE_TESTED |
| Rill consumer/package | same-release adapter smoke; external generic Runtime IPK/APK qualification | exact consumer run `33270679539` plus package-repo qualification run `33260355773` | REMOTE_TESTED |
| device runtime | unavailable on host | OpenWrt device evidence | NOT_EVALUATED |

Exact Cloudflare evidence is commit `0ab252b210f9c100413a028dbed90adf5dbc883d` / Actions run `33270679539`; its qualification manifest reports `automated-qualification` and `releaseEligible: true`. The Rill consumer pin is `hello-yunshu/rill-openwrt-packages@29a17d4c608f610503377f699652c9398d3a8bf4`. Device runtime, hardware coverage, and soak remain `NOT_EVALUATED`.

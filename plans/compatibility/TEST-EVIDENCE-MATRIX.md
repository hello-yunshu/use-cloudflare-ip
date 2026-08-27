# Test evidence matrix

| Contract | Local test | Required Actions evidence | State |
|---|---|---|---|
| legacy RPC/config | `tests/legacy/*`, `tests/legacy-contract.sh` | `legacy-contract` exact SHA/job | OPEN |
| source parser/security | source engine + security scripts | `host-contract` | IMPLEMENTED |
| exact input/one CFST | `v2-cfst-exact-input.sh`, `v2-single-cfst.sh` | `host-contract` | IMPLEMENTED |
| observation/eligibility | `v2-observation.sh` | `host-contract` | IMPLEMENTED |
| transaction/rollback | transaction and adapter tests | `legacy-contract`, package job | OPEN |
| RPC dispatch | `rpc-roundtrip.sh` | `rpc-luci-contract` | OPEN |
| package contents | `package-conffiles.sh` | IPK/APK artifact inspection | OPEN |
| Rill native/musl | adapter smoke | native + five target jobs | OPEN |
| device runtime | unavailable on host | OpenWrt device evidence | BLOCKED |

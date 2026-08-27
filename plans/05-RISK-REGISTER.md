# Risk register

| Risk | Control | Evidence |
|---|---|---|
| legacy feature silently disappears | inventory + preservation matrix + dedicated scripts | local and Actions legacy jobs |
| CFST randomizes broad ranges | scheduler emits only `/32`/`/128` exact hosts | `v2-cfst-exact-input.sh` |
| multiple CFST processes widen outage | one input and process counter | `v2-single-cfst.sh` |
| proxy left disabled | one deadline, recovery path, fake service fixtures | deadline contract |
| user edit overwritten | managed address/remark conflict check | PassWall conflict test |
| rollback leaves managed state ahead | pending state inside transaction | rollback auxiliary-state test |
| OpenClash wrong node accepted | IntendedMapping readback | transformer/readback tests |
| Rill failure blocks native | shadow optional and fallback | Rill adapter tests |
| package loses translations/conffiles | package inspection and LMO gate | OpenWrt package job |
| stale/corrupt source poisons cache | valid parse before last-good update | source security tests |

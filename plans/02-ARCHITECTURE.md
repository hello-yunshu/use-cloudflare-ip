# 2.0 architecture

```text
LuCI -> rpcd/cf_ip -> cf-ip-auto (v2 orchestrator)
                         |-- common/config/status
                         |-- source -> scheduler -> one explicit CFST input
                         |-- observe -> target-domain probe -> native rank
                         |-- transaction -> pure PassWall/OpenClash transformer
                         |                      -> readback -> restart/health
                         |-- optional Rill shadow/feedback
                         `-- optional LAN publisher
```

`source.sh` and `scheduler.sh` concepts never mutate proxy configuration. `observe.sh` only parses measurements and probes. `transaction.sh` is the sole lifecycle owner. `openclash-transform.sh` invokes the legacy-compatible transformation with pure-apply mode; `openclash-readback.sh` verifies name, marker, server, SNI/Host/domain evidence before health probing.

Persistent state is split from run state: `/etc/cf_ip/passwall-managed.json`, `/etc/cf_ip/rill-state.json`, source `last-good` and bounded history are persistent; `/tmp/cf_ip/run-*`, probe files, locks and generated publisher output are rebuildable. Corrupt persistent JSON fails closed and is not guessed.

## 2.2 adaptive measurement boundary

```text
pre-probe candidate metadata -> Native baseline / CFST / Adaptive orders
                              -> Shadow full probe or qualified Guarded subset
                              -> periodic full audit -> bounded evidence state
```

Adaptive Measurement is Native consumer logic and receives only pre-probe
metadata. It cannot create a Runtime learner, partition, feedback path, or
transaction authority. Shadow is the default and keeps the existing Native
probe input unchanged. Guarded is effective only with fresh, context-compatible
full-audit evidence; subset expansion and any scheduler/state/probe failure
fall back to the complete Native probe path.

# Release gates

Development version is `2.0.0-dev`; no stable tag is allowed. `QUALIFICATION_COMPLETE` can be generated only when all 18 legacy items, host/legacy/RPC-LuCI/Rill jobs, five musl targets, IPK/APK builds, rollback gates and real CFST smoke are green. Device/hardware evidence is separate and cannot be inferred from Docker or package builds.

# Host transaction contract

The transaction snapshots the original service/config state, stops the proxy, invokes a pure transformer, reads back intended mappings, restarts, verifies service and target-domain health, then commits. Any timeout/error rolls back config and auxiliary state, restores the original enable state, restarts and verifies recovery. A single monotonic deadline covers the entire proxy-off critical section.

# Aurora UI audit milestones

Scope: LuCI frontend visual refinement for `luci-app-cloudflare-ip`, using an Aurora-compatible preview shell and the in-app browser.

Evidence labels: `PASS`, `FAIL`, `BLOCKED`, `NOT_RUN`, `NOT_EVALUATED`.

## Milestones

| Milestone | Scope | 375px | 768px | 1440px | Navigation/clicks | Audit state |
|---|---|---:|---:|---:|---|---|
| M0 | Baseline, view inventory, runtime entrypoint | PASS (local preview) | PASS (local preview) | PASS (local preview) | PASS (inventory) | PASS; device `NOT_EVALUATED` |
| M1 | Shell, navigation, status and overview blocks | PASS | PASS | PASS | PASS | PASS (local preview) |
| M2 | Settings and integration forms | PASS | PASS | PASS | PASS | PASS (local preview) |
| M3 | Sources, intelligence, backups, logs and records | PASS | PASS | PASS | PASS | PASS (local preview) |
| M4 | Full responsive regression and interaction pass | PASS | PASS | PASS | PASS | PASS (24/24; no overflow) |
| M5 | Static/runtime/package contract validation | PASS (static) | PASS (static) | PASS (static) | PASS (static) | PASS; device `NOT_EVALUATED` |
| M6 | Rill Intelligence page focused audit | PASS | PASS | PASS | PASS (state transitions) | PASS; device `NOT_EVALUATED` |

## Boundary

- The repository currently has no connected LuCI device tab or Aurora runtime URL in the browser session.
- The local preview verifies the frontend DOM/CSS presentation and representative navigation interactions only.
- rpcd/ubus behavior, installed Aurora theme variables, actual LuCI form rendering, and device-sized browser behavior remain `NOT_EVALUATED` until a device URL is available.

## M4 evidence

- In-app browser viewport overrides: 375x900, 768x900, and 1440x900.
- All 8 navigation entries were clicked at all 3 widths: 24/24 visible panel transitions passed.
- All 24 checks reported `scrollWidth === innerWidth`; no horizontal overflow was observed.
- Visual spot checks covered Overview, Settings, Sources, PassWall, OpenClash backups, Advanced, Rill Intelligence, and Diagnostics/log history.

## M5 evidence

- `git diff --check`: PASS.
- All LuCI view modules and `utils.js` passed `node --check`.
- LuCI menu and rpcd ACL JSON passed `jq empty`.
- `tests/legacy/luci-static-contract.sh`: PASS.
- No backend, rpcd, ACL, menu, or package install contract was changed; the shared CSS remains installed by the existing Makefile surface.

## M6 Rill evidence

- Fixed the status contract mismatch: `requestedMode`, `effectiveMode`, and `fallbackReason` are consumed from the status top level, matching the v2 status writer.
- Added an explicit RPC-error presentation: `Status unavailable / Native fallback`.
- Added disabled, healthy, unavailable, and Assisted-to-Shadow fallback summaries without changing Native ranking authority.
- Added Rill page strings to POT, English PO, and Simplified Chinese PO; `msgfmt` and duplicate `msgid` checks passed.
- Browser state checks: 1440px, 768px, and 375px; Assisted interaction displayed the expected fallback sentence and all widths had no horizontal overflow.
- Rill shell contracts passed: `rill-disabled-noexec.sh`, `rill-status-timeout.sh`, `v2-rill-shadow.sh`, and `v2-status.sh`.

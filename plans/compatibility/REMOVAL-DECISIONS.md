# Removal and deprecation decisions

## Self-update: DEPRECATE

2.1 is a multi-file package, so replacing only one shell script is unsafe. The old UCI keys remain readable and the RPC compatibility method returns a structured `deprecated` response. The LuCI page says `Deprecated / package-managed` and does not expose an “Update Script Now” action. Users migrate through IPK/APK package upgrades. `auto_update` defaults to `0`.

## No other 1.8.3 feature is removed

The stricter all-fail NO APPLY rule and target-domain probe gate are safety changes, not silent removals; they are documented and tested. LAN publishing is new and does not replace any existing publisher.

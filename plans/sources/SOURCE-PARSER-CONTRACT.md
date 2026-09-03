# Source parser contract

Accepted endpoint records are IPv4, IPv6, CIDR, preset-aware `IP:port`, and bracketed IPv6 with an optional port. The port is discarded and never reaches CFST, Active Probe, Native Rank or Rill. Domain candidates are rejected without DNS resolution. Remote input is HTTPS-only, bounded by bytes/lines/count, and updates `last-good` only after a valid parse.

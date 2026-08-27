# Source registry and scheduler contract

Official IPv4/IPv6 feeds are the only default-enabled sources and are CIDR inputs. Community presets are opt-in seed sources. Custom sources are either HTTPS text URLs or manual IP/CIDR entries. Each parsed record retains source ID/class/freshness/provenance, but endpoint identity is only a public IP.

Budget allocation is `history=floor(B/8)`, `official=floor(B/4)`, `community=B-history-official`; deficits flow to other valid pools. Duplicate IPs merge provenance and `sourceCount` is admission metadata only. History is freshness-limited and official sampling rotates by run ID across CIDRs.

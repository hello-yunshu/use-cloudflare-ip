# Source registry and scheduler contract

Official IPv4/IPv6 feeds are the only default-enabled sources and are CIDR inputs. Community presets are opt-in seed sources. Custom sources are either HTTPS text URLs or manual IP/CIDR entries. Each parsed record retains source ID/class/freshness/provenance, but endpoint identity is only a public IP.

Budget allocation is `history=floor(B/8)`, `official=floor(B/4)`, `community=B-history-official`; deficits flow to other valid pools. Duplicate IPs merge provenance and `sourceCount` is admission metadata only. History is limited to successful winners observed within seven days by default, and official sampling uses a SHA-256 seed derived from the run sequence, source ID, CIDR and sample index so repeated runs are reproducible while later runs rotate exploration.

# Source security rules

Reject private, loopback, link-local, CGNAT, documentation, benchmark, reserved, multicast, IPv4-mapped, ULA, IPv6 link-local, multicast and documentation ranges. Reject `file://`, shell text, redirects away from HTTPS, oversized responses and malformed lines. No `eval`, command substitution from source content, or DNS candidate resolution is permitted.

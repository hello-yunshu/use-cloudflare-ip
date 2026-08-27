# Candidate scheduler

The scheduler expands official CIDRs to deterministic concrete samples, round-robins families/ranges, merges history/community/official records, deduplicates, and writes one explicit `/32` or `/128` line per candidate. It never emits an official CIDR to CFST and never fills a shortfall by duplicating the first IP.

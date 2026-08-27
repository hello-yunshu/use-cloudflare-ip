# PassWall ownership

`passwall-managed.json` records section, original domain, base remarks, last managed address and last managed remarks. The configured `target_domain` list is the active ownership set. Existing owned sections are found by stable state even after the address is an IP. A changed address or remark is a user conflict and stops the apply. Removed target domains relinquish ownership without touching unrelated sections. New state remains transaction-pending until health commit.

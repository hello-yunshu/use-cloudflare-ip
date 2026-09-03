# LuCI compatibility contract

Existing Overview, Settings, Advanced, Diagnostics, PassWall and OpenClash pages keep their RPC names and shared CSS. New pages are Candidate IP Sources and Intelligence. Shared CSS starts from the full 1.8.3 stylesheet; new classes are appended only.

Installed-aware behavior is required: absent PassWall/OpenClash is shown as unavailable and does not produce a misleading enabled control. RPC promises are wrapped with error notifications and all long operations expose busy/error state through the existing utilities.

# Rill qualification

Native rank remains authoritative and complete when Rill is absent, unsupported, corrupt, timed out or invalid. Native Rust gates are fmt, clippy `-D warnings`, test, release build and smoke. Release qualification additionally executes x86_64, aarch64, riscv64gc, armv7 and i686 musl binaries with the matching QEMU names.

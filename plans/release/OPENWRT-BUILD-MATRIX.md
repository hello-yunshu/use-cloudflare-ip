# OpenWrt build matrix

Required package targets are OpenWrt 24.10.x IPK x86_64 and 25.12.x APK x86_64 using the actual available stable SDK tags. Every SDK Prepare, Build and Inspect step runs with `/builder` as its working directory. Inspection must find the binary, all modules, RPC/init/ACL/menu, full CSS/JS, UCI conffiles and LMO assets.

The source Makefile remains exactly `PKG_VERSION:=2.0.0-dev`. The APK job passes `PKG_VERSION=2.0.0~dev` as a build-only override because APK rejects the hyphenated development form; the IPK job uses the source value. Both artifact types are validated with `tar -tf`, matching the archive format emitted by the OpenWrt SDK package builder.

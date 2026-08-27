# OpenWrt build matrix

Required package targets are OpenWrt 24.10.x IPK x86_64 and 25.12.x APK x86_64 using the actual available stable SDK tags. Every SDK Prepare, Build and Inspect step runs with `/builder` as its working directory. Inspection must find the binary, all modules, RPC/init/ACL/menu, full CSS/JS, UCI conffiles and LMO assets.

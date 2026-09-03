#!/usr/bin/env bash
# Configuration is loaded by cf-ip-auto-v2; this file documents the module
# boundary for package consumers and provides a strict boolean helper.

cfip_config_bool() { cfip_bool "$1"; }

#!/usr/bin/env bash
# CFST process boundary: one task, one input, one invocation.

cfip_cfst_invocation_record() {
    CFIP_CFST_INVOCATION_COUNT=$(( ${CFIP_CFST_INVOCATION_COUNT:-0} + 1 ))
}

#!/usr/bin/env bash
# Deterministic 2.4 context-policy framework.  The shipped policy is
# deliberately conservative until complete Docker evidence justifies a
# context-specific table; it never changes Native eligibility or transaction
# thresholds.

CFIP_CONTEXT_POLICY_ID="${CFIP_CONTEXT_POLICY_ID:-conservative-default}"

cfip_context_pool_bucket() {
    local size="${1:-0}"
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    if ((size <= 16)); then printf small
    elif ((size <= 64)); then printf medium
    else printf large
    fi
}

cfip_context_policy_json() {
    local family="${CFIP_IP_TYPE:-ipv4}" pool="${CFIP_PROBE_TOP_COUNT:-0}" bucket
    bucket="$(cfip_context_pool_bucket "$pool")"
    jq -cn --arg family "$family" --arg bucket "$bucket" --argjson ipCount "${CFIP_IP_COUNT:-1}" \
      --argjson ratio "${CFIP_ADAPTIVE_TARGET_RATIO_PERCENT:-25}" --argjson minProbe "${CFIP_ADAPTIVE_MIN_PROBE_COUNT:-8}" \
      --argjson audit "${CFIP_ADAPTIVE_AUDIT_INTERVAL:-20}" --argjson exploration "${CFIP_ADAPTIVE_EXPLORATION_RATIO_PERCENT:-10}" \
      --arg id "$CFIP_CONTEXT_POLICY_ID" \
      '{schemaVersion:1,policyId:$id,supported:false,reason:"insufficient_context_evidence",context:{ipFamily:$family,poolBucket:$bucket,ipCount:$ipCount},targetRatioPercent:$ratio,minProbeCount:$minProbe,auditInterval:$audit,explorationRatioPercent:$exploration,allowedAdjustments:["targetRatioPercent","minProbeCount","auditInterval","explorationRatioPercent"],protectedBoundaries:["nativeEligibility","transactionHealth","rillSafeTopK","rollbackPolicy"]}'
}

cfip_context_policy_id() {
    cfip_context_policy_json | jq -r '.policyId'
}

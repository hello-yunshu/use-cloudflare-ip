#!/usr/bin/env bash
set -Eeuo pipefail

INPUT="${1:?evidence JSON is required}"
OUTPUT="${2:-${INPUT%.json}-summary.json}"
jq -e 'type=="object" and .schemaVersion==1 and .timingMode=="replayed" and (.scenarios|type=="array")' "$INPUT" >/dev/null
jq '{schemaVersion:1,source:{environment:.environment,timingMode:.timingMode},scenarioCount:(.scenarios|length),aggregate:{meanReplayProbeReductionRatio:(if (.scenarios|length)>0 then ([.scenarios[].probeReductionRatio]|add/length) else 0 end),meanReplayWinnerRecall:(if (.scenarios|length)>0 then ([.scenarios[].winnerRecall]|add/length) else 0 end),meanReplayTopNRecall:(if (.scenarios|length)>0 then ([.scenarios[].topNRecall]|add/length) else 0 end),replayFallbackRate:(if (.scenarios|length)>0 then ([.scenarios[].fallbackRate]|add/length) else 0 end),meanReplayMeasurementDurationMs:(if (.scenarios|length)>0 then ([.scenarios[].measurementDurationMs]|add/length) else 0 end)},byContext:(.scenarios|group_by(.context.family)|map({family:.[0].context.family,count:length,meanReplayProbeReductionRatio:([.[].probeReductionRatio]|add/length),meanReplayWinnerRecall:([.[].winnerRecall]|add/length),meanReplayTopNRecall:([.[].topNRecall]|add/length)}))}' "$INPUT" >"$OUTPUT"
printf '%s\n' "$OUTPUT"

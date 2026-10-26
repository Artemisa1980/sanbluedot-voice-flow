#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
app_path="$project_root/dist/sanblueᵈᵒᵗ VoiceFlow.app"
acceptance_dir="$HOME/Library/Application Support/sanblue.voiceflow"
corpus_path="$acceptance_dir/phase2-corpus.local.json"
results_path="$acceptance_dir/phase2-results.local.jsonl"

if [[ ! -d "$app_path" ]]; then
    echo "VoiceFlow app not found. Run scripts/build-macos-app.sh first." >&2
    exit 1
fi

if [[ ! -f "$corpus_path" ]]; then
    echo "Private Phase 2 corpus not found: $corpus_path" >&2
    exit 1
fi

if pgrep -x "VoiceFlowMac" >/dev/null; then
    echo "A VoiceFlow instance is already running. Quit it first: two instances share" >&2
    echo "the results file and overwrite each other's recordings." >&2
    exit 1
fi

mkdir -p "$acceptance_dir"

completed=0
if [[ -f "$results_path" ]]; then
    completed=$(awk 'NF { count += 1 } END { print count + 0 }' "$results_path")
fi

echo "Phase 2 acceptance progress: $completed/20"
echo "Private results: $results_path"
open -n "$app_path" --args --acceptance-log "$results_path"

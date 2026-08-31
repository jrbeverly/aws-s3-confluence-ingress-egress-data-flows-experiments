#!/usr/bin/env bash
set -euo pipefail

e2e_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
experiment_dir=$(cd "$e2e_dir/../.." && pwd)

bucket=$(terraform -chdir="$experiment_dir" output -raw bucket_name)
run_id=$(date +%s%N)
title="VTT to Confluence E2E $run_id"
key="departures/$run_id.vtt"
fixture=$(mktemp --suffix=.vtt)
trap 'rm -f "$fixture"' EXIT
printf 'WEBVTT\n\n00:00:00.000 --> 00:00:02.000\nRandom cue %s\n' "$run_id" > "$fixture"
metadata=$(jq -nc --arg title "$title" '{title:$title,tags:"e2e,vtt"}')

aws s3api put-object \
  --bucket "$bucket" \
  --key "$key" \
  --body "$fixture" \
  --content-type text/vtt \
  --metadata "$metadata" \
  >/dev/null

page_id=$(PYTHONPATH="$experiment_dir/.build/package" python3 "$e2e_dir/confluence.py" \
  wait-page "$CONFLUENCE_ARRIVALS_PAGE_ID" "$title" "Random cue $run_id" vtt none)
aws s3api wait object-not-exists --bucket "$bucket" --key "$key"

printf 'VTT page: %s/wiki/pages/viewpage.action?pageId=%s\n' "${ATLASSIAN_URL%/}" "$page_id"

#!/usr/bin/env bash
set -euo pipefail

e2e_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
experiment_dir=$(cd "$e2e_dir/../.." && pwd)

bucket=$(terraform -chdir="$experiment_dir" output -raw bucket_name)
run_id=$(date +%s%N)
title="JSON to Confluence E2E $run_id"
key="departures/$run_id.json"
fixture=$(mktemp --suffix=.json)
trap 'rm -f "$fixture"' EXIT
jq -n --arg id "$run_id" '{kind:"random-json-ingress",id:$id,enabled:true}' > "$fixture"
metadata=$(jq -nc --arg title "$title" '{title:$title,tags:"e2e,json"}')

aws s3api put-object \
  --bucket "$bucket" \
  --key "$key" \
  --body "$fixture" \
  --content-type application/json \
  --metadata "$metadata" \
  >/dev/null

page_id=$(PYTHONPATH="$experiment_dir/.build/package" python3 "$e2e_dir/confluence.py" \
  wait-page "$CONFLUENCE_ARRIVALS_PAGE_ID" "$title" "$run_id" json json)
aws s3api wait object-not-exists --bucket "$bucket" --key "$key"

printf 'JSON page: %s/wiki/pages/viewpage.action?pageId=%s\n' "${ATLASSIAN_URL%/}" "$page_id"

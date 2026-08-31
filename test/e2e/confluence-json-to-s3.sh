#!/usr/bin/env bash
set -euo pipefail

e2e_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
experiment_dir=$(cd "$e2e_dir/../.." && pwd)

bucket=$(terraform -chdir="$experiment_dir" output -raw bucket_name)
run_id=$(date +%s%N)
title="Confluence JSON to S3 E2E $run_id"
fixture=$(mktemp --suffix=.json)
actual=$(mktemp --suffix=.json)
trap 'rm -f "$fixture" "$actual"' EXIT
jq -n --arg id "$run_id" '{kind:"random-json-egress",id:$id,values:[3,1,4]}' > "$fixture"

page_id=$(PYTHONPATH="$experiment_dir/.build/package" python3 "$e2e_dir/confluence.py" \
  create-json "$title" "$fixture")
key="e2e-json/$page_id.json"
for _ in {1..90}; do
  if aws s3api head-object --bucket "$bucket" --key "$key" >/dev/null 2>&1; then
    break
  fi
  sleep 5
done
aws s3 cp "s3://$bucket/$key" "$actual" --no-progress
diff <(jq -S . "$fixture") <(jq -S . "$actual")
aws s3api head-object --bucket "$bucket" --key "$key" --output json | jq -e \
  '.Metadata.path == "e2e-json" and (.Metadata.labels | split(",") | index("egress"))' \
  >/dev/null
PYTHONPATH="$experiment_dir/.build/package" python3 "$e2e_dir/confluence.py" wait-deleted "$page_id"

printf 'Consumed Confluence page: %s\n' "$page_id"
printf 'JSON object: s3://%s/%s\n' "$bucket" "$key"

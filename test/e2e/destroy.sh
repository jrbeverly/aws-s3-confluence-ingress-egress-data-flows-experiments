#!/usr/bin/env bash
set -euo pipefail

e2e_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
experiment_dir=$(cd "$e2e_dir/../.." && pwd)

export TF_VAR_confluence_url="$ATLASSIAN_URL"
export TF_VAR_confluence_email="$ATLASSIAN_EMAIL"
export TF_VAR_confluence_api_token="$ATLASSIAN_API_TOKEN"
export TF_VAR_confluence_space_key="$CONFLUENCE_SPACE"
export TF_VAR_departures_parent_page_id="$CONFLUENCE_DEPARTURES_PAGE_ID"
export TF_VAR_arrivals_parent_page_id="$CONFLUENCE_ARRIVALS_PAGE_ID"

terraform -chdir="$experiment_dir" destroy -auto-approve -input=false

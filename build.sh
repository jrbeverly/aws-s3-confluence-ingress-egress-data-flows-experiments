#!/usr/bin/env bash
set -euo pipefail

experiment_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
package_dir="$experiment_dir/.build/package"

rm -rf "$package_dir"
mkdir -p "$package_dir"
python3 -m pip install --quiet --target "$package_dir" -r "$experiment_dir/requirements.txt"
cp "$experiment_dir/publisher.py" "$experiment_dir/exporter.py" "$package_dir/"


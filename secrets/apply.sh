#!/usr/bin/env bash
# Apply every secrets/*.yaml (gitignored) to the cluster.
# Refuses to apply if any *.yaml still contains a CHANGEME placeholder.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

shopt -s nullglob
files=( *.yaml )
[[ ${#files[@]} -eq 0 ]] && { echo "No *.yaml files found. Did you copy from *.yaml.example?"; exit 1; }

# Refuse to apply if any file still has CHANGEME
bad=0
for f in "${files[@]}"; do
  if grep -q CHANGEME "$f"; then
    echo "  $f still contains CHANGEME — fill it in"
    bad=1
  fi
done
[[ $bad -eq 0 ]] || { echo "Fix the files above and re-run."; exit 1; }

# Apply each
for f in "${files[@]}"; do
  echo "==> $f"
  kubectl apply -f "$f"
done

echo "Done."

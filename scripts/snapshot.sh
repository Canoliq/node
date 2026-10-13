#!/usr/bin/env bash
# Restore the node from the latest mainnet snapshot.
set -euo pipefail
: "${SNAPSHOT_URL:?SNAPSHOT_URL is required}"

if [[ -d data/canopy && -n "$(ls -A data/canopy)" ]]; then
	echo "This wipes data/canopy and restores from:"
	echo "  $SNAPSHOT_URL"
	read -rp "Continue? [y/N]: " ok
	[[ "$ok" == [Yy] ]] || exit 0
else
	echo "data/canopy is missing or empty; skipping wipe confirmation."
	echo "Restoring from:"
	echo "  $SNAPSHOT_URL"
fi

docker compose stop node || true

echo "==== downloading snapshot ===="
wget -O snapshot.tar.gz "$SNAPSHOT_URL"
rm -rf data/canopy
mkdir -p data/canopy
echo "==== extracting snapshot ===="
if command -v pv >/dev/null 2>&1; then
	pv snapshot.tar.gz | tar -xzf - -C data/canopy/
else
	# no pv, fall back to a running file count.
	tar -xzvf snapshot.tar.gz -C data/canopy/ 2>&1 |
		awk '{printf "\r  %d files extracted", NR} END {print ""}'
fi
rm -f snapshot.tar.gz
echo "==== chain data restored ===="

docker compose up -d node
echo "==== node restarted from snapshot ===="

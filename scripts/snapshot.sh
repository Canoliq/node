#!/usr/bin/env bash
# Restore the node from the latest mainnet snapshot.
#
# Integrity: if SNAPSHOT_SHA256 is set, or "<SNAPSHOT_URL>.sha256" can be
# downloaded, the archive is verified before anything is wiped or extracted,
# and a mismatch aborts. With neither available it warns and continues.
set -euo pipefail
: "${SNAPSHOT_URL:?SNAPSHOT_URL is required}"

sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}

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

docker compose stop canoliq-node || true

echo "==== downloading snapshot ===="
wget -O snapshot.tar.gz "$SNAPSHOT_URL"

echo "==== verifying snapshot ===="
expected="${SNAPSHOT_SHA256:-}"
if [[ -z "$expected" ]] && wget -q -O snapshot.tar.gz.sha256 "${SNAPSHOT_URL}.sha256"; then
	# "<hash>" or "<hash>  <filename>" (sha256sum format)
	expected="$(awk 'NR==1 {print $1}' snapshot.tar.gz.sha256)"
fi
rm -f snapshot.tar.gz.sha256
if [[ -n "$expected" ]]; then
	expected="$(printf '%s' "$expected" | tr 'A-F' 'a-f')"
	actual="$(sha256_of snapshot.tar.gz)"
	if [[ "$actual" != "$expected" ]]; then
		echo "ERROR: snapshot checksum mismatch" >&2
		echo "  expected: $expected" >&2
		echo "  actual:   $actual" >&2
		echo "Nothing was wiped; the download was removed. The node was stopped: start it again with make node-up." >&2
		rm -f snapshot.tar.gz
		exit 1
	fi
	echo "sha256 OK: $actual"
else
	echo "WARNING: no checksum available (set SNAPSHOT_SHA256 or publish ${SNAPSHOT_URL}.sha256);"
	echo "         the snapshot is NOT verified."
fi

rm -rf data/canopy
mkdir -p data/canopy
echo "==== extracting snapshot ===="
if command -v pv >/dev/null 2>&1; then
	pv snapshot.tar.gz | tar --no-same-owner -xzf - -C data/canopy/
else
	# no pv, fall back to a running file count.
	tar --no-same-owner -xzvf snapshot.tar.gz -C data/canopy/ 2>&1 |
		awk '{printf "\r  %d files extracted", NR} END {print ""}'
fi
rm -f snapshot.tar.gz
echo "==== chain data restored ===="

docker compose up -d canoliq-node
echo "==== node restarted from snapshot ===="

#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0
for f in tests/*.lua; do
	echo "== $f"
	if ! nvim --headless -u NONE -l "$f"; then
		fail=1
	fi
done
exit $fail

#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$ROOT_DIR/bin/egress-check" --help >/dev/null
"$ROOT_DIR/bin/egress-check" --dry-run --config "$ROOT_DIR/config/egress-check.example.env" --mihomo-config "$ROOT_DIR/config/mihomo.example.yaml" >"$TMP_DIR/dry-run.out"
grep -q 'RESULT: OK' "$TMP_DIR/dry-run.out"
"$ROOT_DIR/scripts/install.sh" --dry-run --prefix "$TMP_DIR/prefix" --config-dir "$TMP_DIR/config" >"$TMP_DIR/install.out"
grep -q 'dry run complete' "$TMP_DIR/install.out"
if [[ -e "$TMP_DIR/prefix" || -e "$TMP_DIR/config" ]]; then
    printf 'dry run wrote files\n' >&2
    exit 1
fi
if "$ROOT_DIR/bin/egress-check" --bad-flag >/dev/null 2>&1; then
    printf 'expected failure for bad flag\n' >&2
    exit 1
fi
printf 'smoke: ok\n'

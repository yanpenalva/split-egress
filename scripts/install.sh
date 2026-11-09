#!/usr/bin/env bash
set -euo pipefail
umask 022

PREFIX="${HOME}/.local"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/split-egress"
DRY_RUN=false
FORCE=false
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

usage() {
    cat <<'EOF'
Usage: install.sh [options]

Options:
  --dry-run                 Print actions without writing files
  --force                   Backup and replace existing files
  --prefix DIR              Install prefix (default: ~/.local)
  --config-dir DIR          Configuration directory
  --help, -h                Show this help
EOF
}

run() {
    if $DRY_RUN; then
        printf '+'
        printf ' %q' "$@"
        printf '\n'
        return
    fi
    "$@"
}

backup_file() {
    local file backup
    file="$1"
    backup="${file}.bak.${TIMESTAMP}"
    if $DRY_RUN; then
        printf '+ cp -a %q %q\n' "$file" "$backup"
        return
    fi
    cp -a "$file" "$backup"
}

install_file() {
    local src dest mode
    src="$1"
    dest="$2"
    mode="$3"
    if [[ ! -f "$src" ]]; then
        printf 'missing source: %s\n' "$src" >&2
        exit 2
    fi
    if [[ -e "$dest" ]]; then
        if ! $FORCE; then
            printf 'kept existing: %s\n' "$dest"
            return
        fi
        backup_file "$dest"
    fi
    run install -D -m "$mode" "$src" "$dest"
}

need_value() {
    if [[ $# -lt 2 || -z "$2" ]]; then
        printf 'missing value for %s\n' "$1" >&2
        exit 2
    fi
}

while (($#)); do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --prefix)
            need_value "$1" "${2:-}"
            PREFIX="$2"
            shift 2
            ;;
        --config-dir)
            need_value "$1" "${2:-}"
            CONFIG_DIR="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf 'unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$PREFIX" || "$PREFIX" == "/" ]]; then
    printf 'invalid prefix: %s\n' "$PREFIX" >&2
    exit 2
fi

if [[ "$PREFIX" == /usr* && "$EUID" -ne 0 ]]; then
    printf 'prefix %s requires root\n' "$PREFIX" >&2
    exit 2
fi

install_file "$ROOT_DIR/bin/egress-check" "$PREFIX/bin/egress-check" 0755
install_file "$ROOT_DIR/scripts/routing-up.sh" "$PREFIX/lib/split-egress/routing-up.sh" 0755
install_file "$ROOT_DIR/config/egress-check.example.env" "$CONFIG_DIR/config.env" 0644

if $DRY_RUN; then
    printf '\ndry run complete\n'
else
    printf '\ninstalled\n'
fi
printf '  binary: %s\n' "$PREFIX/bin/egress-check"
printf '  config: %s\n' "$CONFIG_DIR/config.env"
printf '  routing: %s\n' "$PREFIX/lib/split-egress/routing-up.sh"

if [[ ":$PATH:" != *":$PREFIX/bin:"* ]]; then
    printf '\nadd to PATH: put %s/bin in your PATH\n' "$PREFIX"
fi

printf '\nnext\n'
printf '  1. edit %s\n' "$CONFIG_DIR/config.env"
printf '  2. run %s/bin/egress-check --dry-run\n' "$PREFIX"
printf '  3. run %s/bin/egress-check\n' "$PREFIX"

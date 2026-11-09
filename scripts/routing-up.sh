#!/usr/bin/env bash
set -euo pipefail
umask 022

SECONDARY_IF="${SECONDARY_IF:-}"
SECONDARY_GW="${SECONDARY_GW:-}"
ROUTING_TABLE="${ROUTING_TABLE:-100}"
ROUTING_MARK="${ROUTING_MARK:-100}"
DRY_RUN=false
ACTION="up"

usage() {
    cat <<'EOF'
Usage: routing-up.sh [options]

Options:
  --dry-run                 Print actions without changing routing
  --down                    Remove the policy route and rule
  --interface IFACE         Secondary interface
  --gateway ADDR            Secondary gateway
  --table NUMBER            Routing table
  --mark NUMBER             Routing mark
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
        --down)
            ACTION="down"
            shift
            ;;
        --interface)
            need_value "$1" "${2:-}"
            SECONDARY_IF="$2"
            shift 2
            ;;
        --gateway)
            need_value "$1" "${2:-}"
            SECONDARY_GW="$2"
            shift 2
            ;;
        --table)
            need_value "$1" "${2:-}"
            ROUTING_TABLE="$2"
            shift 2
            ;;
        --mark)
            need_value "$1" "${2:-}"
            ROUTING_MARK="$2"
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

if [[ -z "$SECONDARY_IF" ]]; then
    printf 'secondary interface is required\n' >&2
    exit 2
fi

if ! [[ "$ROUTING_MARK" =~ ^[0-9]+$ ]]; then
    printf 'routing mark must be decimal\n' >&2
    exit 2
fi

if ! $DRY_RUN && [[ "$EUID" -ne 0 ]]; then
    printf 'routing changes require root\n' >&2
    exit 2
fi

if [[ "$ACTION" == "up" ]]; then
    if [[ -z "$SECONDARY_GW" ]]; then
        printf 'secondary gateway is required\n' >&2
        exit 2
    fi
    run ip route replace default via "$SECONDARY_GW" dev "$SECONDARY_IF" table "$ROUTING_TABLE"
    run ip rule del fwmark "$ROUTING_MARK" table "$ROUTING_TABLE" 2>/dev/null || true
    run ip rule add fwmark "$ROUTING_MARK" table "$ROUTING_TABLE"
    run sysctl -w "net.ipv4.conf.${SECONDARY_IF}.rp_filter=2"
    run sysctl -w "net.ipv6.conf.${SECONDARY_IF}.disable_ipv6=1"
    exit 0
fi

run ip rule del fwmark "$ROUTING_MARK" table "$ROUTING_TABLE" 2>/dev/null || true
run ip route flush table "$ROUTING_TABLE" 2>/dev/null || true
run sysctl -w "net.ipv6.conf.${SECONDARY_IF}.disable_ipv6=0" 2>/dev/null || true

# split-egress

[![ci](https://github.com/yanpenalva/split-egress/actions/workflows/ci.yml/badge.svg)](https://github.com/yanpenalva/split-egress/actions/workflows/ci.yml)

Per-provider egress policy and verification for Linux.

`split-egress` steers selected AI provider domains over a dedicated secondary WAN while keeping all other traffic on the primary WAN. It uses mihomo for rule-based proxying, Linux policy routing for interface selection, and a single verification command to prove the result.

## What this is

- A Linux egress policy pattern for machines with two uplinks.
- A mihomo example configuration.
- A verification CLI that checks routing, DNS, provider reachability, and isolation.
- A small installer with dry-run, backup, and validation safeguards.

## What this is not

- Not a VPN, anonymity tool, or traffic-hiding system.
- Not a firewall or inspection bypass.
- Not a replacement for network policy, authorization, or acceptable-use rules.
- Not undetectable: DNS, endpoint telemetry, traffic shape, and carrier metadata still exist.

Use it only on systems and networks where you have permission to change egress policy.

## How it works

```
application
    |
    v
mihomo :7890
    |
    +-- AI domain rule ------> secondary group -> direct proxy (SO_MARK 100, wwan0)
    +-- internal domain rule -> DIRECT -> primary WAN
    +-- everything else -----> DIRECT -> primary WAN

kernel
    fwmark 100 -> table 100 -> default via secondary gateway
```

1. mihomo listens on localhost and matches destinations by domain.
2. AI domains match a rule and go to the secondary proxy group.
3. The secondary proxy is a `direct` outbound bound to the secondary interface.
4. Marked packets are routed by a dedicated kernel table.
5. DNS policy sends selected domains to DoH; internal domains use the internal resolver.
6. The secondary group contains only the secondary uplink, so if it is down, AI traffic fails closed instead of leaking over the primary WAN.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full design.

## Features

- Per-domain egress policy without a VPN.
- Explicit primary and secondary WAN separation.
- DNS policy for internal and external domains.
- Fail-closed behavior when the secondary link is unavailable.
- Verification CLI with dry-run mode and redacted output.
- Installer with backups and `mihomo -t` validation.
- Optional systemd unit for persistent policy routing.

## Requirements

### Linux machine

- Linux with `iproute2`, `systemd`, and Bash 4 or newer.
- Root access to configure policy routing.
- Two network uplinks, each with its own gateway.
- `mihomo` installed and reachable on localhost.
- `curl`, `dig`, `awk`, `grep`, and `sed`.
- Optional: `jq` for mihomo API inspection.
- Optional: `vnstat` for secondary-link data usage.

Package examples:

```bash
sudo apt install curl dnsutils iproute2 jq vnstat
sudo dnf install curl bind-utils iproute jq vnstat
sudo pacman -S curl bind iproute2 jq vnstat
```

### Browser

No browser extension is required. If you want browser-only routing, a SwitchyOmega-style extension is optional. Read [docs/BROWSER-PROXY.md](docs/BROWSER-PROXY.md) first: extensions are browser-only, are not fail-closed, and can conflict with system proxy settings.

## Quick start

```bash
git clone git@github.com:yanpenalva/split-egress.git
cd split-egress

./scripts/install.sh --dry-run
./scripts/install.sh
```

Edit the installed configuration:

```bash
$EDITOR ~/.config/split-egress/config.env
```

Set at least:

```bash
SECONDARY_IF="wwan0"
SECONDARY_GROUP="secondary"
MIHOMO_CONFIG="/etc/mihomo/config.yaml"
ROUTING_TABLE="100"
ROUTING_MARK="100"
```

Install and validate the mihomo example:

```bash
sudo mkdir -p /etc/mihomo
sudo cp config/mihomo.example.yaml /etc/mihomo/config.yaml
sudo mihomo -t -d /etc/mihomo
sudo systemctl restart mihomo
```

Apply policy routing:

```bash
sudo ./scripts/routing-up.sh \
  --interface wwan0 \
  --gateway 192.0.2.1 \
  --table 100 \
  --mark 100
```

Verify:

```bash
egress-check --dry-run
egress-check
```

Expected result:

```
RESULT: OK (0 issues, 0 warnings)
```

## Configuration

`~/.config/split-egress/config.env` is a Bash-sourced environment file.

| Variable | Default | Purpose |
|---|---|---|
| `PRIMARY_IF` | auto-detected | Primary WAN interface |
| `SECONDARY_IF` | `wwan0` | Secondary WAN interface |
| `PROXY_URL` | `http://127.0.0.1:7890` | Local mihomo HTTP proxy |
| `MIHOMO_API` | `http://127.0.0.1:9090` | mihomo external controller |
| `MIHOMO_CONFIG` | `~/.config/mihomo/config.yaml` | mihomo configuration |
| `MIHOMO_DNS` | `127.0.0.1:1053` | mihomo DNS listener |
| `INTERNAL_URL` | empty | Optional internal URL checked directly |
| `IP_ECHO_URL` | `https://ifconfig.me` | Public IP echo service |
| `LATENCY_HOST` | `api.anthropic.com` | Latency comparison target |
| `CURL_TIMEOUT` | `8` | Network timeout in seconds |
| `ROUTING_TABLE` | `100` | Policy routing table |
| `ROUTING_MARK` | `100` | Decimal routing mark |
| `SECONDARY_GROUP` | `secondary` | mihomo proxy group name |
| `AI_HOSTS` | provider list | Hosts probed by the checker |
| `AI_DOMAINS` | domain list | Domains checked in the config |

`ROUTING_MARK` must be decimal. `ip rule` displays it in hexadecimal.

## Verification

The checker validates:

- Required commands and optional tools.
- mihomo configuration syntax and required rules.
- Secondary interface and routing mark.
- Policy routing table, fwmark rule, `rp_filter`, and IPv6 state.
- Primary and secondary path selection.
- Direct and proxy exit IP separation.
- AI provider reachability through the proxy.
- DNS resolution through mihomo.
- Direct versus proxy latency.
- Secondary-link data usage.

Exit codes:

| Code | Meaning |
|---|---|
| `0` | All checks passed |
| `1` | One or more checks failed |
| `2` | Usage or configuration error |

See [docs/VERIFICATION.md](docs/VERIFICATION.md) for output interpretation and DNS/fail-closed tests.

## Installation safeguards

- `--dry-run` prints every file operation without writing anything.
- Existing files are never replaced unless `--force` is set.
- `--force` creates a timestamped `.bak` copy before replacing a file.
- `mihomo -t` validates the example configuration before installation.
- The installer refuses a root-owned prefix without root privileges.
- The routing script supports `--dry-run` and `--down`.
- The checker supports `--redact-ips` for screenshots and issue reports.

Rollback:

```bash
sudo ./scripts/routing-up.sh --down \
  --interface wwan0 \
  --table 100 \
  --mark 100

sudo cp /etc/mihomo/config.yaml.bak.YYYYMMDD_HHMMSS /etc/mihomo/config.yaml
sudo systemctl restart mihomo
```

## Limitations

- The secondary link must have a default gateway and working DNS.
- Carrier-grade NAT, weak signal, or congestion can make the secondary path slow.
- Applications that ignore `HTTP_PROXY` and `HTTPS_PROXY` bypass mihomo.
- The example uses `MATCH,DIRECT`; a new provider is not steered until you add its domain.
- The example does not include vendor-specific exceptions. Add them deliberately.
- The checker assumes `ip` and `dig` are available; missing tools produce failed checks.
- Browser extensions are outside the system policy and can override it.

## Security

- Treat `config.env` as executable code: it is sourced by the checker.
- Never commit a real `config.env`, API keys, internal hostnames, or public IPs.
- Review the example before installing it on a production machine.
- See [SECURITY.md](SECURITY.md) for reporting and scope.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Installation](docs/INSTALLATION.md)
- [Verification](docs/VERIFICATION.md)
- [Browser proxy](docs/BROWSER-PROXY.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## License

MIT. See [LICENSE](LICENSE).

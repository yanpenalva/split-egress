# Installation

## Before you start

You need:

- A Linux machine with `systemd` and Bash 4 or newer.
- Root access for policy routing.
- Two working uplinks, each with a gateway.
- A secondary interface that can reach the internet independently.
- `mihomo` installed on the machine.
- `curl`, `dig`, `awk`, `grep`, and `sed`.

Confirm the uplinks:

```bash
ip -br addr
ip route show default
```

Example:

```
default via 192.0.2.1 dev wan0 metric 100
default via 198.51.100.1 dev wwan0 metric 2000
```

In this example:

- `wan0` is the primary WAN.
- `wwan0` is the secondary WAN.
- `198.51.100.1` is the secondary gateway.

Record your real values. Do not copy the documentation addresses into a production system.

## 1. Install Linux dependencies

Debian or Ubuntu:

```bash
sudo apt update
sudo apt install curl dnsutils iproute2 jq vnstat
```

Fedora:

```bash
sudo dnf install curl bind-utils iproute jq vnstat
```

Arch:

```bash
sudo pacman -S curl bind iproute2 jq vnstat
```

`jq` and `vnstat` are optional. The checker reports them as warnings when missing.

## 2. Install mihomo

Install mihomo from its official release page and place the binary in a directory in `PATH`.

```bash
sudo install -m 0755 mihomo /usr/local/bin/mihomo
mihomo -v
```

Create the configuration directory:

```bash
sudo mkdir -p /etc/mihomo
```

If your distribution provides a mihomo systemd unit, use it. Otherwise create one from `systemd/mihomo.service.example` or adapt your existing unit.

Confirm the service:

```bash
sudo systemctl status mihomo
```

Do not continue until mihomo is installed and the service can start.

## 3. Install split-egress

From the repository root:

```bash
./scripts/install.sh --dry-run
./scripts/install.sh
```

The dry run prints every file operation and writes nothing. Review it before the real install.

The installer places:

- `~/.local/bin/egress-check`
- `~/.local/lib/split-egress/routing-up.sh`
- `~/.config/split-egress/config.env`

If `~/.local/bin` is not in `PATH`, add it:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Make it persistent in your shell profile.

## 4. Configure the checker

Edit:

```bash
$EDITOR ~/.config/split-egress/config.env
```

Set the real values:

```bash
PRIMARY_IF="wan0"
SECONDARY_IF="wwan0"
PROXY_URL="http://127.0.0.1:7890"
MIHOMO_API="http://127.0.0.1:9090"
MIHOMO_CONFIG="/etc/mihomo/config.yaml"
MIHOMO_DNS="127.0.0.1:1053"
INTERNAL_URL=""
IP_ECHO_URL="https://ifconfig.me"
LATENCY_HOST="api.anthropic.com"
CURL_TIMEOUT="8"
ROUTING_TABLE="100"
ROUTING_MARK="100"
SECONDARY_GROUP="secondary"
```

`ROUTING_MARK` must be decimal. The kernel displays it as hexadecimal.

## 5. Install the mihomo example

Back up an existing configuration first:

```bash
sudo cp -a /etc/mihomo/config.yaml /etc/mihomo/config.yaml.bak.$(date +%Y%m%d_%H%M%S)
```

Copy the example:

```bash
sudo cp config/mihomo.example.yaml /etc/mihomo/config.yaml
```

Edit the placeholders:

- `interface-name: wwan0`
- `routing-mark: 100`
- `nameserver` and `nameserver-policy` addresses
- `internal.example`
- provider rules, if your provider list differs

Validate before restarting:

```bash
sudo mihomo -t -d /etc/mihomo
```

If validation fails, restore the backup and fix the configuration. Do not restart a broken service.

Restart:

```bash
sudo systemctl restart mihomo
sudo systemctl status mihomo
```

The installer can also copy the example for you:

```bash
./scripts/install.sh --with-mihomo-config --mihomo-config /etc/mihomo/config.yaml
```

That path requires root and refuses to overwrite an existing file unless `--force` is set.

## 6. Apply policy routing

Use the routing helper:

```bash
sudo ./scripts/routing-up.sh \
  --interface wwan0 \
  --gateway 198.51.100.1 \
  --table 100 \
  --mark 100
```

Dry run first:

```bash
./scripts/routing-up.sh --dry-run \
  --interface wwan0 \
  --gateway 198.51.100.1 \
  --table 100 \
  --mark 100
```

The script:

- Adds or replaces the default route in table 100.
- Removes and re-adds the fwmark rule.
- Sets `rp_filter=2` on the secondary interface.
- Disables IPv6 on the secondary interface.

These changes are not persistent by themselves. Install the systemd unit if you need them after reboot:

```bash
sudo cp systemd/split-egress-routing.service.example /etc/systemd/system/split-egress-routing.service
sudo systemctl daemon-reload
sudo systemctl enable --now split-egress-routing.service
```

Edit the unit first. Its example paths assume `/usr/local/lib/split-egress/routing-up.sh` and placeholder interface values.

If the helper is installed under `~/.local`, either copy it to `/usr/local/lib/split-egress/` or update `ExecStart` and `ExecStop` in the unit.

## 7. Verify

Dry run:

```bash
egress-check --dry-run
```

Live check:

```bash
egress-check
```

Redacted output for screenshots or issue reports:

```bash
egress-check --redact-ips
```

Expected:

```
RESULT: OK (0 issues, 0 warnings)
```

If the result is not OK, read [TROUBLESHOOTING.md](TROUBLESHOOTING.md) before changing more settings.

## 8. Browser configuration

No browser extension is required when the system proxy is already set.

If you want browser-only routing, read [BROWSER-PROXY.md](BROWSER-PROXY.md). Keep one source of truth:

- System policy active: leave the browser on **System** proxy.
- Browser-only test: use a dedicated browser profile and set the extension explicitly.
- Do not configure both layers at once.

## Installation safeguards

### Dry run

Every installer and routing command supports `--dry-run`. Run it first.

### Backups

- The installer backs up an existing file before `--force` replaces it.
- The mihomo configuration should be backed up manually before the first copy.
- Backups use a timestamp suffix and are ignored by Git.

### No silent overwrite

- Existing files are kept unless `--force` is set.
- Root-owned prefixes require root.
- The installer validates the mihomo example with `mihomo -t` before copying it.

### Lockout protection

Policy routing can interrupt connectivity. Before applying changes:

- Keep a second terminal open.
- Know the primary gateway and interface.
- Know how to remove the rule and flush the table.
- Test on a non-critical machine first.
- Do not run the changes over the only remote session without an out-of-band recovery path.

Rollback:

```bash
sudo ./scripts/routing-up.sh --down \
  --interface wwan0 \
  --table 100 \
  --mark 100

sudo cp /etc/mihomo/config.yaml.bak.YYYYMMDD_HHMMSS /etc/mihomo/config.yaml
sudo systemctl restart mihomo
```

### Installation issues to anticipate

| Issue | Safeguard |
|---|---|
| Missing `dig` or `curl` | Installer and checker report missing commands |
| mihomo not installed | Installer refuses `--with-mihomo-config` |
| Invalid mihomo config | `mihomo -t` runs before install and in the checker |
| Existing config overwritten | Backups and `--force` requirement |
| Interface name wrong | Checker compares the env file with the mihomo config |
| Routing mark mismatch | Checker compares the decimal mark with the config and `ip rule` |
| DoH endpoint blocked | Checker reports DNS failures; test before rollout |
| Secondary link down | Verifier fails; fail-closed group prevents fallback |
| Browser overrides system proxy | One-source-of-truth guidance in browser docs |
| Lost connectivity | Rollback commands and `--down` support |

## Unsupported setups

The example does not support:

- IPv6-only secondary links.
- Multiple secondary interfaces at once.
- Interfaces without a default gateway.
- Policy routing inside containers without host network access.
- Windows, macOS, or non-systemd Linux.

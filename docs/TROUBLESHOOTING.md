# Troubleshooting

## First checks

```bash
egress-check --dry-run
egress-check
systemctl status mihomo
journalctl -u mihomo --since "10 min ago"
ip rule
ip route show table 100
```

Most failures are one of: mihomo is not running, the secondary route is missing, the fwmark rule is missing, or the interface name does not match the configuration.

## `config not found`

The checker could not find the environment file.

```bash
egress-check --config ~/.config/split-egress/config.env --dry-run
```

Confirm the path and rerun the installer if the file is missing.

## `missing commands`

Install the missing package:

```bash
sudo apt install curl dnsutils iproute2
```

`dig` is in `dnsutils` on Debian and Ubuntu, and in `bind-utils` on Fedora.

## `mihomo not installed`

The checker can still validate the configuration, but it cannot validate the service.

Install mihomo, or set `MIHOMO_CONFIG` to the configuration file you want to inspect.

## `secondary interface is not set`

Set `SECONDARY_IF` in `config.env`.

The checker can auto-detect it from the first `interface-name` line in the mihomo config, but an explicit value is safer.

## `secondary interface not found`

The interface in `config.env` does not match the mihomo config.

```bash
ip -br addr
grep -n "interface-name" /etc/mihomo/config.yaml
```

Update one of them. The values must match exactly.

## `routing mark not found`

The decimal mark in `config.env` does not match the mihomo config.

```bash
grep -n "routing-mark" /etc/mihomo/config.yaml
```

`ROUTING_MARK=100` matches `routing-mark: 100`. The kernel displays the same mark as `0x64`.

## `table 100 has no default route`

Add the secondary route:

```bash
sudo ip route replace default via 198.51.100.1 dev wwan0 table 100
```

Or rerun the routing helper:

```bash
sudo ./scripts/routing-up.sh --interface wwan0 --gateway 198.51.100.1 --table 100 --mark 100
```

## `fwmark rule missing`

```bash
sudo ip rule add fwmark 100 table 100
```

Check:

```bash
ip rule
```

Expected:

```
32764: from all fwmark 0x64 lookup 100
```

The rule number is assigned by the kernel and may differ.

## `rp_filter wwan0=1` or `unknown`

Set loose reverse-path filtering:

```bash
sudo sysctl -w net.ipv4.conf.wwan0.rp_filter=2
```

Strict mode (`1`) can drop replies that arrive on the secondary interface.

## `IPv6 active on wwan0`

Disable IPv6 on the secondary interface:

```bash
sudo sysctl -w net.ipv6.conf.wwan0.disable_ipv6=1
```

If IPv6 is required, extend the policy routing and the verifier deliberately. Do not leave a partial IPv6 path.

## `secondary path: 1.1.1.1 not via wwan0`

The interface has no route to the destination, or the secondary link is down.

```bash
ip route get 1.1.1.1 oif wwan0
ip link show wwan0
```

Check the gateway and the interface state.

## `primary path` warning

This warning means `1.1.1.1` does not use the expected primary interface. It can be caused by a third default route or a VPN.

```bash
ip route show default
```

The checker uses the first default route as the primary interface when `PRIMARY_IF` is unset. Set `PRIMARY_IF` explicitly if the order is ambiguous.

## `direct and proxy IPs match`

The proxy path is using the same egress as the direct path.

Possible causes:

- The mihomo rule for `IP_ECHO_URL` is not pointing at the secondary group.
- The secondary proxy is not bound to the secondary interface.
- The routing mark is not set or does not match the kernel rule.
- The IP echo domain is routed `DIRECT`.

Check the rule:

```bash
grep -n "ifconfig.me" /etc/mihomo/config.yaml
```

The example routes `ifconfig.me` to `secondary`.

## `provider unreachable` or HTTP `000`

The proxy completed the connection locally but the upstream request failed.

Check:

```bash
curl -v -x http://127.0.0.1:7890 https://api.anthropic.com
journalctl -u mihomo --since "5 min ago"
ip route get 1.1.1.1 oif wwan0
```

Common causes:

- Secondary link down.
- Carrier congestion or packet loss.
- The provider blocks the secondary egress address.
- IPv6 attempted on an IPv4-only link.
- TCP Fast Open incompatibility.

If `tfo: true` is the only recent change, set it to `false` and retest.

If the secondary link is reachable but slow, raise `CURL_TIMEOUT` in `config.env` — for example, `12` or `15` — and rerun. The checker retries once, but a single request can still exceed a short timeout.

## `DNS fail`

The mihomo DNS listener did not return an address.

```bash
dig +short @127.0.0.1 -p 1053 api.anthropic.com
grep -n "nameserver" /etc/mihomo/config.yaml
```

Check:

- `MIHOMO_DNS` points at the listener.
- mihomo is running.
- The DoH endpoint is reachable.
- The `nameserver-policy` entry covers the hostname.

If the DoH endpoint is blocked by the primary network, use a different DoH endpoint or a local forwarder. The checker reports the failure; it does not fix it.

## High proxy latency

A secondary mobile or congested link can be much slower than the primary WAN.

Check:

```bash
ping -I wwan0 -c 5 1.1.1.1
vnstat -i wwan0 -d 1
```

This is a link-quality issue, not a routing configuration issue. The verifier deliberately reports both direct and proxy latency so the difference is visible.

## Browser still uses the primary path

Check the effective browser proxy:

```
chrome://net-internals/#proxy
edge://net-internals/#proxy
```

Common causes:

- The browser extension is set to Direct.
- The browser uses System proxy while the system proxy is unset.
- The extension overrides the system proxy.
- A PAC file returns `DIRECT`.
- QUIC or WebRTC uses a different path.

Use one layer at a time. See [BROWSER-PROXY.md](BROWSER-PROXY.md).

## New provider uses the primary path

The example ends with `MATCH,DIRECT`. A provider that is not listed uses the primary WAN.

Add:

1. The domain suffix to the mihomo rules.
2. The domain to `AI_DOMAINS`.
3. The API host to `AI_HOSTS`.

Then rerun `egress-check`.

## A model works but its provider API does not

A model name is not a domain. Some clients use a gateway domain for model access. For example, OpenCode Go uses `opencode.ai`, while the direct DeepSeek API uses `api.deepseek.com`.

Check the actual base URL in the client configuration before editing the egress rules. If the model works and the direct API fails, the client is probably using a gateway, and the direct API is a separate policy decision.

## Fail-closed test succeeds through the primary WAN

The secondary group has a fallback that should not be there.

```bash
curl -s http://127.0.0.1:9090/proxies/secondary | jq '{now, all}'
```

`all` must contain only `secondary-uplink`. Remove `DIRECT`, the primary outbound, or any other proxy from the group.

## mihomo configuration validation fails

```bash
sudo mihomo -t -d /etc/mihomo
```

Read the first error. Common causes:

- Invalid YAML indentation.
- A proxy group referencing a missing proxy.
- A duplicate name.
- An unsupported DNS key.

Restore the last backup if needed.

## Lost connectivity after applying routing

Use a second terminal, or the local console, to roll back:

```bash
sudo ./scripts/routing-up.sh --down \
  --interface wwan0 \
  --table 100 \
  --mark 100

sudo ip route show table 100
sudo ip rule
```

Then restore the mihomo backup:

```bash
sudo cp /etc/mihomo/config.yaml.bak.YYYYMMDD_HHMMSS /etc/mihomo/config.yaml
sudo systemctl restart mihomo
```

## Logs and state

```bash
systemctl status mihomo
journalctl -u mihomo --since "15 min ago"
ip rule
ip route show table 100
ip route get 1.1.1.1 oif wwan0
ss -ltnp | grep -E '7890|7891|9090|1053'
```

The checker is intentionally read-only. It reports state; it does not repair it.

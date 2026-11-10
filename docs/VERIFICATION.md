# Verification

`egress-check` exercises the live path. It is designed to answer four questions:

1. Is the configuration internally consistent?
2. Does policy routing send marked traffic over the secondary WAN?
3. Do AI provider requests actually use the secondary egress?
4. Are DNS and fail-closed behavior what the design claims?

## Commands

```bash
egress-check --dry-run
egress-check
egress-check --redact-ips
```

Use `--dry-run` after editing the environment file. It validates dependencies and configuration without network probes.

Use `--redact-ips` when sharing output publicly. It reports that the direct and proxy IPs are distinct without printing either address.

## Exit codes

| Code | Meaning | Action |
|---|---|---|
| `0` | All checks passed | None |
| `1` | One or more checks failed | Read the failed lines and troubleshoot |
| `2` | Usage or configuration error | Fix the command or environment file |

Warnings do not change the exit code when every required check passes. They indicate optional tools or behavior worth reviewing.

## Sample output

```
[0] Dependencies
  OK    required commands
  WARN  vnstat not installed

[1] Configuration
  OK    mihomo config: /etc/mihomo/config.yaml
  OK    secondary interface: wwan0
  OK    routing mark: 100
  OK    AI domain rules: secondary
  OK    direct domains: not proxied
  OK    mihomo config validation

[2] Routing
  OK    table 100: default via 198.51.100.1 dev wwan0
  OK    fwmark 0x64 -> table 100
  OK    rp_filter wwan0=2
  OK    IPv6 disabled on wwan0
  OK    secondary path: 1.1.1.1 via wwan0
  OK    primary path: 1.1.1.1 via wan0
  OK    group secondary -> secondary-uplink

[3] IP audit
  OK    direct=203.0.113.10 proxy=198.51.100.20

[4] AI providers
  OK    api.openai.com HTTP 421 0.18s DNS 203.0.113.30
  OK    api.anthropic.com HTTP 404 0.14s DNS 203.0.113.31
  OK    claude.com HTTP 200 0.36s DNS 203.0.113.38
  OK    generativelanguage.googleapis.com HTTP 404 0.31s DNS 203.0.113.32
  OK    openrouter.ai HTTP 200 0.41s DNS 203.0.113.34
  OK    api.cline.bot HTTP 401 0.28s DNS 203.0.113.35
  OK    api.deepseek.com HTTP 401 0.26s DNS 203.0.113.36
  OK    api.z.ai HTTP 301 0.24s DNS 203.0.113.37
  OK    opencode.ai HTTP 200 0.23s direct

[5] Latency
  direct=0.14s proxy=0.16s host=api.anthropic.com

[6] Data usage
  2026-01-01  120.00 MiB | 20.00 MiB | 140.00 MiB | 13.00 kbit/s

RESULT: OK (0 issues, 0 warnings)
```

The addresses above are documentation examples. Real output contains your addresses.

## Section reference

### `[0] Dependencies`

Required commands are `ip`, `curl`, `awk`, `grep`, `sed`, and `dig`.

Missing required commands produce `FAIL`. Missing optional tools (`mihomo`, `jq`, `vnstat`) produce `WARN`.

### `[1] Configuration`

Checks:

- The mihomo file exists.
- The secondary interface from `config.env` exists in the mihomo config.
- The decimal routing mark exists in the mihomo config.
- Every domain in `AI_DOMAINS` has a `DOMAIN-SUFFIX,...,SECONDARY_GROUP` rule.
- Every domain in `DIRECT_DOMAINS` does not have a proxy rule.
- `mihomo -t` accepts the file.

If you add a provider, add it to both `AI_DOMAINS` and the mihomo rules.

### `[2] Routing`

Checks:

- Table `ROUTING_TABLE` has a default route.
- `ip rule` contains `fwmark <mark>` pointing at that table.
- `rp_filter` on the secondary interface is `2`.
- The secondary interface has no global IPv6 address.
- `ip route get 1.1.1.1 oif <secondary>` uses the secondary interface.
- `ip route get 1.1.1.1` uses the primary interface.
- The mihomo group named by `SECONDARY_GROUP` is reachable and reports the expected outbound when `jq` is installed.

A missing fwmark rule or table route means the kernel will not send marked traffic over the secondary WAN.

### `[3] IP audit`

Compares:

- A direct request to `IP_ECHO_URL`, bypassing the proxy.
- The same request through `PROXY_URL`.

The addresses must differ. If they match, the proxy path is not using a distinct egress.

If `INTERNAL_URL` is set, the checker requests it directly, bypassing the proxy. This confirms that an internal service still uses the primary path. A reachable internal URL is reported as `OK`; an unreachable one is a warning, not a failure.

### `[4] AI providers`

Each host in `AI_HOSTS` is requested through the proxy. Any HTTP status other than `000` counts as reachable.

Each host in `DIRECT_HOSTS` is requested without the proxy and reported as `direct`.

Expected status codes:

- `421` for OpenAI root requests.
- `404` for Anthropic and Gemini API roots.
- `401` for authenticated API roots.
- `200` or `301` for provider landing pages.

These are not failures. `000` means the request did not complete.

The `DNS` field is the address returned by the mihomo DNS listener. `DNS fail` means the host did not resolve through that listener.

### `[5] Latency`

Compares a direct request and a proxied request to `LATENCY_HOST`.

This is informational. A large difference is normal when the secondary link is a mobile or congested uplink. A sudden increase is a signal to check the secondary link.

### `[6] Data usage`

Runs `vnstat -i <secondary> -d 1` when `vnstat` is installed. This is informational.

## Additional tests

### DNS leak test

Start a capture on the primary interface:

```bash
sudo tcpdump -ni wan0 'udp port 53'
```

Generate AI provider traffic through the proxy in another terminal. If plaintext DNS queries for AI domains appear on the primary interface, the DNS policy is not working.

DoH traffic to `1.1.1.1:443` is encrypted and is expected to appear as TLS, not as a DNS query.

### Fail-closed test

Disable the secondary link or unplug the secondary interface, then run:

```bash
curl -x http://127.0.0.1:7890 --max-time 5 https://api.anthropic.com
```

Expected: the request fails. It must not succeed through the primary WAN.

Restore the link and run `egress-check` again.

### Proxy group selection

Inspect the group:

```bash
curl -s http://127.0.0.1:9090/proxies/secondary | jq '{now, all, alive}'
```

Expected: `now` is `secondary-uplink` and `all` contains only `secondary-uplink`. A primary or `DIRECT` entry in `all` breaks fail-closed behavior.

### Route inspection

```bash
ip rule
ip route show table 100
ip route get 1.1.1.1 oif wwan0
```

The fwmark rule must point at the table that contains the secondary default route.

## Common false alarms

- `421`, `404`, and `401` from provider roots are expected.
- `WARN vnstat not installed` only affects the data-usage section.
- A high proxy latency on a mobile link is not a configuration failure.
- A `DNS fail` line does not necessarily mean the HTTPS request failed; it means the DNS listener did not return an address for that host.

# Architecture

## Purpose

`split-egress` gives one Linux workstation two independent egress paths:

- A **primary WAN** for normal traffic, internal services, package managers, and everything not explicitly selected.
- A **secondary WAN** for selected AI provider domains.

The goal is deterministic per-domain routing without a VPN, without changing the default route for the whole machine, and without falling back to the primary WAN when the secondary link is unavailable.

## Components

| Component | Responsibility |
|---|---|
| mihomo | Match destinations by domain and select an outbound |
| `secondary-uplink` | Direct outbound bound to the secondary interface and routing mark |
| `secondary` group | Fail-closed group containing only the secondary outbound |
| Policy table | Kernel table with the secondary default route |
| fwmark rule | Send marked packets to the policy table |
| DNS policy | Resolve internal and AI domains through different resolvers |
| `egress-check` | Prove the configured behavior without guessing |

## Packet flow

```
application
    |
    | HTTP proxy :7890
    v
mihomo
    |
    +-- DOMAIN-SUFFIX,internal.example -> DIRECT
    |       |
    |       v
    |   primary routing table -> primary WAN
    |
    +-- DOMAIN-SUFFIX,openai.com -> secondary
    |       |
    |       v
    |   secondary-uplink
    |       interface-name: wwan0
    |       routing-mark: 100
    |       |
    |       v
    |   fwmark 0x64 -> table 100 -> secondary gateway
    |
    +-- MATCH,DIRECT -> primary WAN
```

The primary WAN remains the kernel default route. Only traffic that matches an AI rule and receives the routing mark uses the secondary table.

## Why a routing mark

The secondary interface may also have a default route, but the kernel must not use it for unmarked traffic. The mark creates a narrow policy:

1. mihomo creates a socket for the secondary outbound.
2. The socket receives `SO_MARK 100`.
3. `ip rule` matches `fwmark 0x64` and selects table 100.
4. Table 100 contains only the secondary default route.

Unmarked traffic never enters table 100, so the primary WAN remains unaffected.

## Why `rp_filter=2`

Reverse-path filtering in strict mode can drop replies that arrive on a different interface than the one the kernel expects. Policy routing often creates this asymmetry.

`net.ipv4.conf.<secondary>.rp_filter=2` enables loose reverse-path filtering:

- The source address must still be routable.
- The reply does not have to arrive on the same interface as the outgoing packet.

This is the minimum needed for the secondary path to work without disabling reverse-path filtering globally.

## Why IPv6 is disabled

The example disables IPv6 on the secondary interface and sets `ipv6: false` in mihomo.

Reasons:

- Many secondary links provide IPv6 that bypasses the IPv4 policy route.
- A partial IPv6 path can silently use the primary WAN or an unexpected route.
- The example is IPv4-only so the verification result is unambiguous.

If your secondary uplink has a fully tested IPv6 policy, extend the design deliberately and add IPv6 checks to the verifier.

## DNS behavior

```
internal domain -> internal resolver -> internal address
AI domain       -> DoH resolver      -> public address
other domain    -> primary resolver  -> public address
```

The example uses:

- `192.0.2.53` as a placeholder internal resolver.
- `1.1.1.1` over DoH for selected AI domains.
- The primary resolver for everything else.

The DNS policy is part of the isolation. Routing TCP traffic over the secondary WAN while resolving AI domains through the primary resolver leaks provider names to the primary network. The verifier checks both the rule set and mihomo DNS resolution.

DoH hides query names inside TLS, but the connection to the DoH resolver still uses the primary WAN. If the primary network blocks the DoH endpoint, the AI domain resolution fails. Test the endpoint before relying on it.

## Fail-closed behavior

The `secondary` group contains only `secondary-uplink`.

It does not contain `DIRECT` or a primary-WAN outbound. If the secondary interface is down, mihomo has no fallback for AI domains and the request fails.

That is intentional:

- A failed AI request is visible and reversible.
- A silent fallback to the primary WAN defeats the policy and is harder to detect.

The verifier should be run after any change to the secondary link. A request that fails when the secondary link is intentionally disabled is the expected result.

## Improving reliability without a corporate fallback

Adding the primary WAN to the group defeats the isolation. If the secondary link is unreliable, add a second non-corporate uplink instead — for example, a personal Wi-Fi hotspot — and gate it by SSID. Do not add `DIRECT` or a primary outbound to the group.

A second non-corporate uplink preserves the fail-closed property: AI traffic can move between non-corporate paths, but it never falls back to the primary WAN.

## Why `MATCH,DIRECT`

The final rule sends everything not explicitly listed to `DIRECT`, which uses the primary routing table.

This keeps the blast radius small:

- Internal services continue to use the primary WAN.
- Package managers, browsers, and system updates are unaffected.
- Only the listed AI domains use the secondary WAN.

The tradeoff is that a new AI provider is not steered until its domain is added. The verifier checks every domain in `AI_DOMAINS`, so adding a provider requires updating both the mihomo config and the environment file.

## Provider gateway vs provider API

A model name is not an egress policy.

Some clients access models through a gateway domain. For example, OpenCode Go serves models through `opencode.ai`, while the direct DeepSeek API is `api.deepseek.com`. A DeepSeek model can therefore work while the direct DeepSeek API does not, and the two paths can have different reachability, TLS inspection, and DNS behavior.

Before changing a rule, confirm which endpoint the client actually uses:

1. Check the provider configuration and the client's base URL.
2. Inspect the TLS certificate issuer on the direct path.
3. Compare a direct request with a proxied request.
4. Add or remove the gateway domain, not the model name.

The example configuration lists provider domains, not model names. Treat that list as a starting point.

If the gateway is directly reachable and you accept primary-WAN visibility, remove its rule and add the gateway domain to `NO_PROXY`. Do not remove the provider API rule unless the API is also directly reachable.

## Verification model

`egress-check` is not a configuration linter. It exercises the live path:

1. Validate the mihomo file with `mihomo -t`.
2. Confirm the secondary interface and routing mark exist in the config.
3. Confirm every `AI_DOMAINS` suffix has a rule pointing at `SECONDARY_GROUP`.
4. Confirm table 100 has a default route.
5. Confirm the fwmark rule exists.
6. Confirm `rp_filter=2` and IPv6 is inactive on the secondary interface.
7. Confirm `ip route get 1.1.1.1 oif <secondary>` uses the secondary interface.
8. Compare direct and proxied exit IPs.
9. Probe each `AI_HOSTS` endpoint through the proxy.
10. Resolve each host through the mihomo DNS listener.
11. Compare direct and proxy latency.
12. Report secondary-link data usage when `vnstat` is available.

The result is evidence, not inference.

## Tradeoffs

| Choice | Benefit | Cost |
|---|---|---|
| Per-domain rules | Narrow blast radius | New providers need explicit rules |
| Fail-closed group | No silent primary fallback | AI traffic stops when secondary is down |
| Policy routing | No VPN or default-route change | Root access and kernel tuning |
| DoH for AI domains | Query names are encrypted | DoH endpoint must be reachable |
| IPv4-only example | Predictable verification | No IPv6 support out of the box |
| Browser extension optional | Per-browser testing | Extra layer, DNS/WebRTC caveats |

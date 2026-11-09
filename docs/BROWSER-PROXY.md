# Browser proxy

## Is a browser proxy extension required?

No. When the operating system proxy is configured, the browser inherits it.

A SwitchyOmega-style extension is optional. It is useful when you want one browser profile to use a different proxy from the rest of the system, typically for testing.

Examples include Proxy Switcher Omega, ZeroOmega, and Proxy SwitchyOmega. They are different extensions with similar behavior. Check the publisher, permissions, and version before installing any of them.

## What it is good for

- Browser-only testing.
- A dedicated browser profile pointed at the local mihomo proxy.
- Quickly switching between Direct, System, HTTP, and SOCKS profiles.
- Per-site rules through PAC or extension rules.

## What it does not do

- It does not affect CLI tools, daemons, package managers, or MCP servers.
- It does not provide fail-closed behavior.
- It does not guarantee DNS privacy.
- It does not prevent WebRTC leaks.
- It is not a security boundary.
- It is not a substitute for the operating-system policy.

## One source of truth

Do not configure both the operating system proxy and a browser extension at the same time unless you have tested the result.

The browser may:

- Override the system proxy.
- Chain the extension proxy on top of the system proxy.
- Resolve DNS locally before sending the request.
- Fall back to direct when the proxy is unavailable.

That makes `egress-check` results and browser behavior diverge.

Recommended combinations:

| Goal | System proxy | Browser extension |
|---|---|---|
| Apply policy to the whole machine | Enabled | Set to **System** |
| Test only one browser profile | Disabled or irrelevant | Explicit proxy profile |
| Quick direct browsing | Enabled | Set to **Direct** |
| Troubleshooting | One layer only | Remove or disable the other layer |

## Configuration

HTTP proxy:

```
http://127.0.0.1:7890
```

SOCKS5 proxy:

```
socks5://127.0.0.1:7891
```

For SOCKS5, enable remote DNS if the extension offers it. With local DNS, the browser resolves the hostname before the proxy sees it.

Use a dedicated browser profile for the test. Disable synchronization for that profile if you do not want the proxy settings copied to other devices.

## DNS and WebRTC

Even with a proxy configured, a browser can leak information through:

- Local DNS resolution.
- WebRTC candidates.
- Prefetch and preconnect behavior.
- Extension background requests.

If DNS privacy matters, use the HTTP proxy rather than a locally resolving SOCKS5 profile, and test the browser with a DNS leak test and a WebRTC test.

The operating-system policy remains the authoritative path. The browser extension is a convenience, not a guarantee.

## Extension permissions

Proxy extensions commonly request permissions such as:

- `proxy`
- `webRequest`
- `storage`
- `tabs`

Those permissions are broad enough to observe or modify browser traffic. Treat the extension as a supply-chain dependency:

- Install from the official store listing.
- Review the publisher and permissions.
- Pin the version where possible.
- Remove extensions you no longer use.
- Prefer the browser's built-in proxy settings for a single static proxy.

## Verify the effective browser proxy

Chrome and Edge:

```
chrome://net-internals/#proxy
edge://net-internals/#proxy
```

Firefox:

```
about:preferences#general
```

Look for **Network Settings**.

Then request the same IP echo service used by the checker:

```bash
curl -x http://127.0.0.1:7890 https://ifconfig.me
```

Compare the browser result with the direct and proxy results from `egress-check`.

## Recommended documentation wording

If you document a browser extension in your own deployment, keep it short and explicit:

> Browser-level proxy configuration is optional and intended for testing. It affects only the browser profile where it is installed. It is not fail-closed, does not cover CLI tools, and can conflict with the operating-system proxy. Use one layer at a time and verify the effective proxy before relying on it.

Do not describe a browser extension as making traffic invisible, anonymous, or undetectable. It does not.

# Security

## Scope

`split-egress` changes Linux egress policy and local proxy configuration. It does not provide anonymity, encryption beyond the selected upstream protocols, or protection from a compromised host.

## Responsible use

Use this project only on systems and networks where you have authorization to change routing and proxy behavior.

You are responsible for complying with:

- Applicable law.
- Your organization's acceptable-use and network policies.
- Contracts with network and service providers.
- The terms of service of the providers you access.

The project is a routing tool. It is not a justification for circumventing controls you are not authorized to bypass.

## Secrets

Never commit:

- API keys or tokens.
- Real `config.env` files.
- Internal hostnames.
- Private or public IP addresses from your environment.
- Backups containing the above.

The repository ignores `.env`, `config.env`, `.bak`, and `.bak.*` files. That is a safety net, not a substitute for reviewing what you stage.

`config.env` is sourced by the checker. Treat it as executable code:

- Keep it owned by your user.
- Use mode `0600` if it contains sensitive values.
- Review changes before running the checker.
- Do not source a config file from an untrusted source.

## Network changes

Policy routing and firewall changes can interrupt connectivity.

Before applying changes:

- Read the rollback section in [docs/INSTALLATION.md](docs/INSTALLATION.md).
- Keep a second terminal or out-of-band access path available.
- Test on a non-critical machine first.
- Back up the existing mihomo configuration.
- Run `--dry-run` before the real command.

## Browser extensions

Browser proxy extensions are optional and outside the system policy. They may request broad permissions and may observe or modify browser traffic.

See [docs/BROWSER-PROXY.md](docs/BROWSER-PROXY.md) before installing one.

## Reporting a vulnerability

Open a private security advisory on the repository or contact the maintainer directly.

Include:

- A description of the issue.
- Steps to reproduce.
- Affected version or commit.
- Impact.
- Any suggested fix.

Do not include real credentials, internal hostnames, or personal data in a public issue.

## No warranty

The software is provided under the MIT License, without warranty of any kind. See [LICENSE](LICENSE).

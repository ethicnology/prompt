# Private OpenCode Server Setup

Prompt is designed for a private OpenCode server reachable over WireGuard. Do
not expose the OpenCode HTTP port to the public Internet.

## Why OpenCode Must Stay Private

An OpenCode server is not a passive chat website. A client that reaches it can
read session history, inspect workspace metadata, submit prompts, and request
tools that may read, edit, or execute commands in the server workspace.

Its environment and configuration can also provide access to sensitive
credentials, including:

- GitHub, GitLab, or other source-control tokens used by the workspace.
- API keys or OAuth sessions for AI providers.
- MCP credentials and service tokens.
- Private source code, tool output, and file paths.

HTTP Basic authentication is necessary defense in depth, but it is not a
reason to expose OpenCode publicly. Keep the listener and firewall restricted
to WireGuard peers.

## Server Listener

Bind OpenCode to its WireGuard address, not `0.0.0.0` or the public interface.
For a server whose WireGuard address is `10.80.0.1`:

```ini
[Service]
Environment=OPENCODE_SERVER_USERNAME=opencode
EnvironmentFile=/etc/opencode-web.env
ExecStart=/usr/local/bin/opencode web --hostname 10.80.0.1 --port 4096
```

`/etc/opencode-web.env` must contain `OPENCODE_SERVER_PASSWORD` and be owned by
root with mode `0600`. Never commit it, print it, or copy it into a client
configuration file.

The systemd service should run as an unprivileged account and retain hardening
such as `NoNewPrivileges=true`, `ProtectSystem=strict`, `PrivateTmp=true`, and
a small `ReadWritePaths` allowlist.

## UFW Policy

Start from a deny-by-default inbound policy. Allow only SSH administration and
the WireGuard UDP port on the public interface. Permit OpenCode only from a
known WireGuard peer.

```sh
sudo ufw default deny incoming
sudo ufw allow 22/tcp
sudo ufw allow 51820/udp
sudo ufw allow in on wg0 from 10.80.0.2 to 10.80.0.1 port 4096 proto tcp comment 'OpenCode from WireGuard phone'
sudo ufw deny in on wg0 from 10.80.0.2 comment 'Restrict WireGuard phone ingress'
sudo ufw enable
```

Rule order matters: the OpenCode allow rule must appear before the broad
WireGuard deny rule. Check the result with:

```sh
sudo ufw status numbered
```

For several peers, add an explicit allow rule for each trusted peer or use a
dedicated WireGuard subnet rule only when every peer is equally trusted.

## Prompt Connection

On Android and Linux, Prompt accepts an HTTP origin only when it is a private
RFC1918 IPv4 address, a Tailscale CGNAT IPv4 address in `100.64.0.0/10`, or an
IPv6 ULA address. This supports ordinary WireGuard and Tailscale deployments
without hard-coding one server address into the application.

Examples:

```text
http://10.80.0.1:4096
http://172.20.0.5:4096
http://100.64.0.1:4096
http://[fd00::1]:4096
```

Prompt sends Basic authentication on every OpenCode request when configured.
The password is held in platform secure storage, not in the UI state, Drift,
or logs.

## Web deployment with Caddy

WireGuard encrypts native client traffic, but a browser requires HTTPS for the
microphone and secure browser APIs. When Web support is deployed, place Caddy
on the WireGuard address and proxy to OpenCode. Prefer a DNS-01 ACME
certificate for a private DNS name; it works on Android, Linux, and browsers
without installing a private CA on every device.

Do not publish the Caddy listener on the public interface. `tls internal` is
possible, but requires trusting Caddy's private root CA on every device and is
therefore not the default recommendation.

The repository does not deploy or configure Caddy for you. The following is a
concrete example for a private DNS name whose certificate is issued with DNS-01;
replace the domain, certificate issuer credentials, and filesystem paths for
your host. This example requires a Caddy build with the Cloudflare DNS module.
It serves the built Flutter files and sends all non-file requests to the local
OpenCode listener, so the browser's configured HTTPS origin can use a
same-origin connection.

```caddyfile
opencode.example.internal {
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }

    root * /srv/prompt/web

    header {
        # Keep this policy aligned with Flutter Web's generated loader. The
        # API and SSE traffic is same-origin; add only the exact HTTPS/WSS
        # origins used by this deployment if a separate API origin is needed.
        Content-Security-Policy "default-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'none'; form-action 'self'; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; worker-src 'self' blob:; manifest-src 'self'; media-src 'self' blob:"
        Referrer-Policy "no-referrer"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        Permissions-Policy "camera=(), geolocation=(), payment=(), usb=()"
        Strict-Transport-Security "max-age=31536000"
    }

    @flutter_files file
    handle @flutter_files {
        file_server
    }

    handle {
        reverse_proxy 127.0.0.1:4096
    }
}
```

The HTTP response header is normative; the generated page's metadata must not
be treated as a substitute for it. `script-src 'unsafe-inline'` and
`wasm-unsafe-eval` are retained because Flutter's generated bootstrap and
compiled runtime need them. Keep `connect-src 'self'` when the OpenCode API is
same-origin. If the app is deliberately configured with another private HTTPS
origin, replace it with that exact origin (and its `wss:` endpoint), rather than
using a wildcard; the browser and server must then also allow that origin's CORS
policy.

## Temporary APK Sharing

An APK can be served temporarily only on the WireGuard address. Add a narrowly
scoped UFW rule before any broader `DENY` rule for that peer, then remove the
rule and stop the server after download. Never use a public file server for
debug APKs that may contain development configuration.

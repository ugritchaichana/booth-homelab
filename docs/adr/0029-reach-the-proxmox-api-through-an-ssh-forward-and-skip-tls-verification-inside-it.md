# 0029. Reach the Proxmox API through an SSH forward and skip TLS verification inside it

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D50 in docs/platform/requirements.md (refines ADR 0022)

## Context

The OpenTofu provider speaks HTTPS to the Proxmox API on port 8006. The host's certificate is self-signed, and its firewall admits port 8006 only from the management address (ADR 0027). The workstation reaches the host over an SSH session whose host key is pinned (ADR 0022).

Measured on the host: `pveproxy` listens on `*:8006` (`host-facts` socket listing), so the forward's target `127.0.0.1:8006` on the host is served. Measured 2026-10-07 on the new stack: `tofu plan` with a data source dials the API at plan time and fails with `connect: connection refused` when the endpoint is dead, so every plan and apply needs the forward.

## Options considered

1. Connect to `https://<host>:8006` directly with the certificate pinned or `insecure` — needs the port open to the workstation, and either a pin to maintain or no authentication of the server.
2. Replace the host certificate with one from a private CA the workstation trusts — verified TLS, but adds a CA and a renewal job to Phase 2.
3. SSH local forward `127.0.0.1:18006` to the host's `127.0.0.1:8006` as the `automation` user, provider endpoint on the loopback address, `insecure = true`.

## Decision

Option 3.

- `scripts/iac/tofu.sh` opens the forward with the rendered SSH config (`StrictHostKeyChecking yes`, pinned key) for the commands that dial the API, and closes it on exit. Concurrent runs for the same host share one forward through a shared lock; the last one out closes it.
- `providers.tf` sets `insecure = true` and no `ssh {}` block. `api_endpoint` is validated as a loopback HTTPS URL, so the flag cannot be pointed at another machine by a variable.
- The API token reaches the provider only through `PROXMOX_VE_API_TOKEN` in the `tofu` process environment.

## Rationale and trade-offs

- The server is authenticated by the SSH host-key pin, and the TLS hop ends on the host's own loopback, so skipping certificate verification removes no check that the SSH layer does not already make.
- Accepted loss: while a forward is open, any local process of the same machine can connect to `127.0.0.1:18006`; it still needs the token. One forward per machine means one host at a time: a second host's forward fails on the busy port instead of silently reusing the first.
- If a resource needs the provider's SSH access, add a second forward to the host's `127.0.0.1:22` rather than an `ssh {}` block with a password or the root key.
- Revisit when the control path moves off the workstation: a runner on the guest network can verify a certificate from the private CA of option 2.

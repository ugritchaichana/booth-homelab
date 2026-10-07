# 0043. Use Debian's docker.io in the VM class with a socket-only daemon

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D70 in docs/platform/requirements.md

## Context

ADR 0015 puts Docker workloads in a VM runner class; its acceptance proof is a job running `docker run hello-world` inside a VM runner. The class template (ADR 0038, ADR 0040) must therefore carry a container engine and the GitHub Actions runner, built from pinned artifacts only. Job code that can reach the engine is root inside the VM, which ADR 0015 accepts because the VM is the boundary.

Measured 2026-10-07: Debian 13 (trixie) ships `docker.io` 26.1.5+dfsg1-9+deb13u1 with `containerd` 1.7.24~ds1-6+deb13u1 and `runc` 1.1.15+ds1-2+b4 (`apt-cache policy` on a trixie host after `apt-get update`). Upstream `docker-ce` is newer.

## Options considered

1. Debian `docker.io` — signed by the Debian archive key already trusted, security fixes arrive through Debian's cadence, no extra key or source; the engine is older than upstream.
2. Upstream `docker-ce` from Docker's apt repository — a newer engine and buildx/compose plugins; needs a third-party key and source (`signed-by` plus a pinned fingerprint), and that key can sign replacements for packages it names.
3. A static tarball from the Docker download site — pinned by hash, but outside apt, so no security updates path and a hand-written systemd unit.

## Decision

Option 1. The class pins the exact `docker.io`, `containerd` and `runc` versions in `bundles/vm-docker/versions.yml`.

- `daemon.json` carries log rotation only: no `hosts`, no `-H tcp://`, no TLS listener, no insecure registries, and no registry auth file (`/root/.docker` is removed; finalize rejects any `.docker/config.json`). The engine listens on the unix socket only.
- The `runner` user is in the `docker` group, which is root-equivalent inside the VM. It has no sudo. The runner is unpacked under `/opt/actions-runner` from the release tarball with its pinned sha256 and is never configured (no `.runner`, no `.credentials*`).
- The in-guest run fails when an installed version differs from `versions.yml`; the manifest records OS release, kernel, docker version, runner version and the sha256 of `versions.yml`.

## Rationale and trade-offs

- No third-party signing key enters the template, which is the provenance row of the Phase 3 security review (row 2).
- Pinned apt versions go stale: when Debian publishes a security update, the old version leaves the mirror and the build fails until `versions.yml` is bumped. This is intended; the failure is the signal.
- Named partial: the engine lacks upstream's newest features and the buildx and compose plugins. Jobs needing them install them per job, or this decision is revisited.
- The claim "hello-world passes on a clone" is not proven by this change; it is the host proof (UNVERIFIED until then).

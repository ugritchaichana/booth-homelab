# 0071. Reach the simulation cache over a tailnet connector inside the guest, with a tripwire

- Status: Accepted; the tripwire mechanism is superseded by 0072 (the tailnet join stands)
- Date: 2026-10-21
- Deciders: owner
- Decision log: D104 in docs/platform/requirements.md
- Refines: ADR 0008
- Builds on: ADR 0070

## Context

Hosted runners must reach the store of ADR 0070 without a public endpoint. The owner chose a tailnet join over a public tunnel on 2026-10-21. The workstation also runs another overlay client, and a tailnet daemon there dialed upstream from the wrong interface when it forwarded into the lab (ADR 0008, measured 2026-10-06), so the connector must not live on it. ADR 0008 keeps the hypervisor off the tailnet because a tailnet interface there gives a guest a route in (R15); this decision puts one node inside one guest, so the guest itself must have no route and no proxy into the tailnet.

## Options considered

1. Public HTTPS funnel to the store: anyone on the internet reaches the store's pre-authentication surface.
2. A tunnel with an edge-checked service token: strong, needs an account and a zone the owner may not have.
3. Hosted runners join the tailnet as ephemeral nodes tagged `tag:ci-sim`; the store's node is tagged `tag:lab-cache`; one grant between the tags.

## Decision

Option 3, with the connector inside the `sim-cache` container only.

- `tailscaled` runs in userspace networking (`--tun=userspace-networking`): no tun device, no kernel route, no local proxy listener. A process in the container has no path into the tailnet; the node only accepts connections. The hypervisor and every other guest stay off the tailnet.
- The policy snippet `iac/tailnet/sim-cache-policy.json` holds the tag owners, exactly one grant (`tag:ci-sim` to `tag:lab-cache`, tcp on the cache port) and a `tests` block asserting the allowed port, denied ports and that `tag:lab-cache` opens no connection. No rule has `tag:lab-cache` as source. The owner pastes it; the repository cannot reach the admin console.
- Join key: one pre-authorized, single-use key minted at apply time, stored in the SOPS file for the run, written to tmpfs for the join, removed in an `always` block and unset afterwards.
- Hosted runners join as `tag:ci-sim` through the vendor's GitHub action, preferably with workload-identity federation from the repository's OIDC token, or an OAuth client limited to minting that tag, so no auth key is stored. The action always passes `--accept-routes`, and the owner's full policy may still hold a default allow-all, so the snippet's `tests` also deny `tag:ci-sim` every member device (the PVE UI forward on 8006 and ssh, as `autogroup:member:*`) and every `tag:lab-cache` port outside the cache port (ranges either side of it, plus the store ports and their gRPC twins). The owner removes or narrows any allow-all rule before saving, so those tests pass; a policy that still allows it is rejected on save (HYPOTHESIS: the console accepts port ranges in a test destination).
- Tripwire (`iac/ansible/roles/sim_cache_service/files/tripwire.py`): MinIO posts every audit event to a loopback sink that appends it to `/var/log/sim-cache/audit.jsonl`. A request with no access key, or a key outside `sim-read`, `sim-write` and the root user, stops `tailscaled`, writes `/var/lib/sim-cache/state/tripwire/tripped` and puts the object `_control/tripwire`. Health probes are ignored. `tailscaled` requires the tripwire unit and refuses to start while the marker exists. The sink sees events as they arrive; detection and containment take one request, not a polling interval.
- The next run reads the object `_control/tripwire` through the read user and fails red with `infra: cache tripwire`. A hosted runner cannot read it once the connector is down; it sees an unreachable store.

## Rationale and trade-offs

- A leaked tag key reaches one port and still needs the store's keys. A stolen store key is bounded by the policies of ADR 0070.
- Fail closed: a stopped sink stops the connector; a trip needs an owner to rearm (`RUNBOOK.md` 2.11, step 11). A false positive from an unauthenticated internal request costs availability, not safety. HYPOTHESIS until measured: no such request occurs idle (check f).
- The tripwire does not see an attack that names a known key (ADR 0070, Consequences).
- HYPOTHESIS until the host proof: inbound tailnet connections reach `127.0.0.1` in userspace mode; the connector accepts `--auth-key=file:`; anonymous requests carry an empty access key in the audit event.
- Measured nothing yet: no run id exists; the offline proof is `tests/isolation/test-sim-cache-role.sh` (a live sink with a fake `systemctl`, an anonymous request stops the connector and leaves the marker, a known user does not).

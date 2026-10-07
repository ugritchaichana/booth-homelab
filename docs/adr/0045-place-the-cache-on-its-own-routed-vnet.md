# 0045. Place the cache on its own routed vnet

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D73 in docs/platform/requirements.md
- Refines: ADR 0030

## Context

The cache service needs an address every runner guest can reach. Guests live on the `guests` vnet, whose ports are isolated (ADR 0030). Measured on the host: two guests on `guests` cannot reach each other, even with the guest firewall off.

## Options considered

1. A peer guest on `guests` — port isolation drops the traffic, so no runner could reach it.
2. The cache on the hypervisor — reachable from the guests' gateway address, but the untrusted runners would then have a path to the host, which ADR 0027 closes on purpose.
3. A second vnet `cache` in the same zone: `10.99.17.0/24`, gateway `10.99.17.1`, isolated ports, SNAT, routed through the host. The cache container sits at `10.99.17.10`.

## Decision

Option 3.

- OpenTofu: the SDN module takes `additional_vnets`, a map of vnet id to `cidr` and `gateway`, all in the zone the module already owns. The existing resource addresses are unchanged, so the host plan adds the vnet and subnet and replaces only the experimental applier resource.
- Inventory: `cache_network` (`vnet`, `cidr`, `gateway`) and `cache_endpoint` (`address`, `port`) under the host. A host without them plans no second vnet and renders no cache firewall lines. The port is data and may change when the store is chosen.
- The host forwards IPv4 per interface. The SDN-generated interface configuration for `cache` is expected to set it the way it does for `guests`; the runbook checks `net.ipv4.conf.cache.forwarding`.

## Rationale and trade-offs

- Runners and the cache are different subnets, so the only path between them is the routed one, where the firewall (ADR 0046) decides what passes.
- The cache vnet has isolated ports too, so a compromised cache container cannot reach another guest that is later placed on its vnet.
- SNAT on `cache` is harmless: the SDN rule applies to traffic leaving through the uplink, and runner-to-cache traffic does not, so the cache should see the runner address. HYPOTHESIS until the host proof: the source address the cache logs.
- The cache container's own firewall carries `guest-egress`, so it cannot reach the guests subnet or the host either.

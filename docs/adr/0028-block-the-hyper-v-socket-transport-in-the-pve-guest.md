# 0028. Block the Hyper-V socket transport in the PVE guest

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D62 in docs/platform/requirements.md

## Context

Measured on the PVE VM (`host-facts` section 7, 2026-10-06): `hv_sock` is loaded with no users, next to `hv_vmbus`, `hv_utils`, `hv_balloon`, `hv_storvsc` and `hv_netvsc`; the `hyperv-daemons` package is absent.

Hyper-V sockets are a byte-stream channel between the Hyper-V host and a guest that runs without the network stack ("All communication over Hyper-V sockets runs without using networking", https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/user-guide/make-integration-service). The Linux side is the vsock transport in `hv_sock` (https://github.com/torvalds/linux/blob/master/net/vmw_vsock/hyperv_transport.c). It therefore does not cross the Hyper-V port ACLs (ADR 0007) or any guest or PVE firewall rule; those filter network traffic only. The same page says a host service must be registered in the host registry under a GUID before guests can reach it, so exposure needs a host-side registration; that limit is documentation, not measured here.

Inferred, not measured: with the module loaded, a guest process opening an `AF_VSOCK` socket to a registered host service would reach it outside every network control the isolation design relies on (R15).

## Options considered

1. Leave the module loaded — nothing to maintain, but an unfiltered host-to-guest channel stays available to any guest process.
2. Block the module in the guest (`install hv_sock /bin/false`) and unload it — closes the channel inside the guest; the Hyper-V side is unchanged.
3. Also remove the integration devices from the VM on the Hyper-V side — closes it at the boundary, but needs host rights and a VM configuration change this phase does not make.

## Decision

Option 2, implemented by `iac/ansible/roles/hyperv_guest`: a modprobe drop-in with `install hv_sock /bin/false`, an unload when loaded, and an assertion that no KVP, VSS or file-copy daemon is installed or running.

## Rationale and trade-offs

- The block is in the guest, which is the layer this repository controls with a reviewed, repeatable change; a guest-side root user can undo it, so it is a hygiene control, not a boundary. Option 3 is the stronger control and stays open for a later phase.
- Accepted loss: Hyper-V integration features that use host-guest channels (key-value exchange, VSS-consistent checkpoints). ADR 0019 takes restore points only while the VM is Off, so the VSS path is not used, and the daemons are absent.
- `hv_vmbus`, `hv_storvsc` and `hv_netvsc` stay loaded: disk and network need them.
- Not proven until the first converge: that `hv_sock` unloads cleanly and `modprobe -n -v hv_sock` then prints `install /bin/false`.

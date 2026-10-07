# 01. Architecture and Design

Covers the host, the VM, the networks, the guests and the two isolation layers. The canonical page is [docs/handoff/architecture.md](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/handoff/architecture.md).

Guests created by flavor (the demo guests `demo-lxc-runner-v<N>` and `demo-vm-docker-v<N>`, VMIDs 9501 and 9502): [ADR 0055](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/adr/0055-create-flavor-sized-guests-from-a-declarative-list-with-one-command.md) and "Guests by flavor" in [iac/tofu/README.md](https://github.com/ugritchaichana/booth-homelab/blob/master/iac/tofu/README.md).

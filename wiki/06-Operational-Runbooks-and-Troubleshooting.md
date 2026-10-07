# 06. Operational Runbooks and Troubleshooting

The procedures live in `RUNBOOK.md` in the repository, so they are reviewed with the code. This page says where to find each one and lists the defects that only the real host exposed.

## Where each procedure lives

| Task | Where |
|---|---|
| Create, start, stop and checkpoint the `pve01` VM; the Windows isolation layer | `scripts/hyperv/README.md` |
| Converge the host, run OpenTofu | `iac/ansible/README.md`, `iac/tofu/README.md`, the stack READMEs |
| Build, check, roll back and recover golden templates; bump a pinned toolchain | `RUNBOOK.md` section 9 |
| Pin a template version for one consumer | `RUNBOOK.md` section 10 |
| Run the R15 isolation proof | `RUNBOOK.md` section 11, `tests/isolation/README.md` |
| Run, rotate and purge the build cache | `RUNBOOK.md` section 12 |
| Rotate or recover a secret | `iac/secrets/README.md` |
| Publish evidence | `docs/knowledge/README.md` |

Every command that touches the host goes through `scripts/iac/ansible.sh` or `scripts/iac/tofu.sh`; never call `ansible-playbook` or `tofu` directly against the host.

## Safety nets to know about

| Net | What it does |
|---|---|
| SSH dead-man | A change to sshd or root keys arms a timer that restores the previous access; a second run refuses while one is armed (`iac/ansible/README.md`) |
| Firewall dead-man | A change to the host or cluster firewall files restores the previous state if not confirmed, also after a reboot |
| Guest firewall guard | A timer stops any guest whose firewall deviates from its vnet policy |
| Start gate | The cache container starts only after its firewall reads back compliant |
| Stopped-VM checkpoint | `Invoke-PveVm.ps1 -Action Checkpoint` works only while the VM is Off; a restore plus start takes about 16 s (row 45) |

## Failures seen on the real host

Full list with fixes: `docs/knowledge/real-host-defects.md`. The ones an operator is most likely to meet again:

| Symptom | Cause | Where handled |
|---|---|---|
| A converge failed at the firewall check and the dead-man restored the previous state | The compile check read `ignore <chain>` lines as errors | Fixed; the restore itself worked on the real host (row 46) |
| A template build ends `REFUSED thin pool ... is above` | The pre-build space guard | `RUNBOOK.md` section 9.5 |
| Plan stops with `Expected exactly one <class> template` | No `current` tag yet, or two guests carry it | `RUNBOOK.md` section 10.1 |
| Cache service fails to bind its address after a container start | The unit started before the address existed | Fixed by the address wait (row 67) |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` on a probe guest | A new probe generation has new host keys | The key-generation play now forgets the old ones (row 70) |
| A converge rebooted the host | `pve_host` applies pending kernel updates by design | Drain any pool first once runners exist (`RUNBOOK.md` section 12.6) |
| An Ansible run over the proxy hop lost the result of a long upgrade | The SSH hop dropped the session | async with polling and keep-alives (row 41, 43) |
| A converge was suspended mid-run | The laptop entered Modern Standby on battery | Keep the laptop awake for the whole run; the attempt was invalid and was repeated (row 43) |

## Description
<!-- Provide a concise description of the changes, architectural decisions, and motivation. -->

## Type of Change
- [ ] 🐛 Bug fix (non-breaking change fixing an issue)
- [ ] ✨ New feature (non-breaking change adding functionality)
- [ ] ⚡ Performance optimization (latency/throughput improvements)
- [ ] 🔒 Security hardening (firewall, isolation, secrets hygiene)
- [ ] 🏗️ Infrastructure-as-Code (OpenTofu, Ansible, Proxmox topology)
- [ ] 🧪 Testing & SDET (DAG diffing, unit/integration suites)

## Verification & Ground Truth Evidence
<!-- Cite automated test outputs, exit codes, and verification commands. -->
- [ ] `.NET Tests`: `dotnet test apps/backend/SdetTestingRig.sln` passed
- [ ] `Angular Jest Tests`: `python scripts/ci/run_ct103_tests.py` passed
- [ ] `AST Graph Diff Runner`: `bash tests/verify-affected-graph.sh` and `pwsh ./tests/verify-affected-graph.ps1` passed
- [ ] `IaC CI Quality Gate`: `tofu validate` passed
- [ ] `Language Compliance`: 0 Thai characters in repository code and documentation

## Checklist
- [ ] My code adheres to the 8 Core Engineering Pillars (GEMINI.md / AGENTS.md).
- [ ] No plaintext secrets or private VPN IPs committed.
- [ ] Documentation and wiki mirrored if relevant.

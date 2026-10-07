# 0017. Size templates by generic cloud flavors

- Status: Accepted
- Date: 2026-10-06
- Deciders: owner
- Decision log: D1 in docs/platform/requirements.md (requirement R3)

## Context

Runners and services are cloned from golden templates, and every clone needs a vCPU, memory and disk size. The owner wants a neutral baseline that can be adapted later by editing data, not code (R3, R16). Sizing numbers scattered through resource definitions are hard to review and impossible to reuse for another host.

The tree already resolves sizes from a catalog: `iac/tofu/flavors.json` maps a provider and an instance name to `cores`, `memory_mb`, `disk_gb` and `balloon_mb`, and `iac/tofu/main.tf:9-11` looks the values up with `local.resolve_flavor[var.cloud_provider][var.runner_dotnet_flavor]`. The catalog holds five providers (`iac/tofu/flavors.json:6`, `:20`, `:31`, `:42`, `:52`).

## Options considered

1. Named runner classes defined by one workload set — readable for that set, but the names and sizes encode one set of workloads and are not neutral. Another adopter has to rename everything.
2. Generic public-cloud flavors in a data catalog — names such as `t3.medium` are widely known, the same name means the same size on every host, and adding a size is a data change.
3. Raw vCPU, memory and disk numbers in each resource — no catalog to maintain, but sizes repeat, drift apart and cannot be validated centrally.

## Decision

Option 2. Size comes from a flavor name in `iac/tofu/flavors.json`. Example: `aws/t3.medium` is 2 vCPU, 4096 MB and 30 GB (`iac/tofu/flavors.json:11`).

- The catalog is the only place sizes are written. Resources read them through the lookup above.
- A test asserts that every catalog entry has positive `cores`, `memory_mb` and `disk_gb`, and `tofu plan -var 'flavor=aws/t3.medium'` must show 2 cores and 4096 MB (R3 acceptance).
- Every template carries a version tag and a manifest of operating-system and toolchain versions.

## Rationale and trade-offs

- A catalog lookup keeps sizing reviewable in one file and keeps the stack provider-neutral, which is what the owner needs to adapt it in a fork. The owner stated: use generic cloud flavors now and adapt to other baselines later.
- The numbers are the catalog's choice, not a copy of a cloud's hardware: public clouds do not attach a fixed disk size to an instance type, so `disk_gb` and `balloon_mb` are values this repository picks. Do not read a flavor as a promise of cloud-equivalent performance.
- The flavor is resolved at plan time, so changing a catalog entry changes every clone of that flavor at its next apply; templates carry versions so a rollback is a variable change.
- The R3 plan and catalog tests are not in the tree at this commit; the catalog and lookup are.
- Revisit when an adopter needs a size no public flavor describes: add a catalog entry rather than a new mechanism.

# Sample applications

Small workloads that the CI executes: a .NET 8 backend solution and an Angular (Jest) frontend. They exist to give the platform something real to build, test and cache; improving them is not a platform goal.

| Path | Content |
|---|---|
| `backend/` | .NET 8 solution `SdetTestingRig.sln`; `Directory.Build.props` makes the build deterministic |
| `backend/src/` | `Core.Domain`, `Core.Application`, `Billing.Api`, `Order.Api` |
| `backend/tests/` | `Billing.Api.UnitTests`, `Order.Api.UnitTests`, `Order.Api.IntegrationTests` |
| `frontend/` | Angular standalone components tested with Jest and jsdom (no browser); billing and order components and their specs under `src/app/` |
| `fixtures/tax-rounding.json` | Shared cases for the backend and frontend rounding tests |

## Lockfiles

Every backend project carries a `packages.lock.json` and the frontend a `package-lock.json`. The build cache keys dependency entries on their hashes (ADR 0049), so a dependency change must come with the lockfile change. The pipeline restores in locked mode (`dotnet restore --locked-mode`, `npm ci`).

## Run locally

```sh
dotnet test apps/backend/SdetTestingRig.sln
npm ci --prefix apps/frontend
npm test --prefix apps/frontend -- --silent
```

The .NET selector that runs only the test projects affected by a change, and its harness:

```sh
bash scripts/apps/dotnet-affected-test.sh <base-ref> <head-ref>
bash tests/verify-affected-graph.sh
```

The selector has one implementation, a shell script; on Windows run it in WSL (ADR 0056). See `wiki/04-SDET-Transitive-Affected-Testing.md`.

## Flaky tests

- A test that fails and then passes on the same commit, with no code change, is flaky.
- Within 24 hours it is quarantined (skipped with a reason that links its tracking issue) and an issue is opened.
- It returns only after 20 consecutive green repeat runs, recorded in the issue.

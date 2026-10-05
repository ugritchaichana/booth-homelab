# Applications & Workload Codebases

This directory contains the target applications and test suites executed by the continuous testing rig.

---

## 📁 Workload Architecture

```
apps/
├── backend/                  # .NET 8 Multi-Project Enterprise Solution
│   ├── SdetTestingRig.sln
│   ├── Directory.Build.props # Enforces /p:Deterministic=true
│   ├── src/
│   │   ├── Core.Domain/      # Domain entities (Money, Order, Invoice)
│   │   ├── Core.Application/ # Business logic services
│   │   ├── Billing.Api/      # Billing REST service
│   │   └── Order.Api/        # Order REST service
│   └── tests/
│       ├── Billing.Api.UnitTests/
│       ├── Order.Api.UnitTests/
│       └── Order.Api.IntegrationTests/
│
└── frontend/                 # Angular 18/19 Standalone Component Suite
    ├── package.json          # Modern Angular dependencies
    ├── jest.config.js        # Pure headless jsdom test preset
    ├── setup-jest.ts         # Angular zone.js & Jest polyfills
    └── src/app/
        ├── billing/          # Billing summary component & service
        └── order/            # Order checkout component & service
```

---

## 🧪 Local Execution

### 1. Backend (.NET 8)
```powershell
dotnet test apps/backend/SdetTestingRig.sln --verbosity quiet
```

### 2. Frontend (Angular Jest)
```bash
npm test --prefix apps/frontend -- --silent
```

### 3. Transitive Graph Diff Engine
```powershell
pwsh -File ./tests/verify-affected-graph.ps1
```

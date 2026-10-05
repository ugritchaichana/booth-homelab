# 06. Operational Runbooks and Troubleshooting

**Standard:** Continuous Testing Infrastructure Specification  
**Status:** Active  
**Revision:** Phase 2 Complete (Dual-Runner .NET 8 + Angular Jest Rig Live)  

---

## 1. Proxmox Container Lifecycle Commands

All containers on Proxmox VE can be inspected and managed from the host shell (`root@100.121.209.85` via Python Paramiko or console):

```bash
# List all containers and status
pct list

# Start / Stop / Restart containers
pct start 102; pct start 103; pct start 104
pct stop 102; pct stop 103; pct stop 104

# Execute commands inside container directly from PVE Host:
# CT 102 (.NET 8 Runner):
pct exec 102 -- systemctl status actions.runner.ugritchaichana-booth-homelab.gha-runner-01.service --no-pager

# CT 103 (Angular Jest Runner):
pct exec 103 -- systemctl status actions.runner.ugritchaichana-booth-homelab.gha-runner-angular.service --no-pager

# CT 104 (MinIO S3 Cache):
pct exec 104 -- systemctl status minio --no-pager
```

---

## 2. GitHub Actions Runner Maintenance & Token Rotation

### 2.1 Restarting Runner Daemons
If a runner shows offline in GitHub Actions:
```bash
# CT 102 (.NET Runner):
pct exec 102 -- systemctl restart actions.runner.ugritchaichana-booth-homelab.gha-runner-01.service

# CT 103 (Angular Jest Runner):
pct exec 103 -- systemctl restart actions.runner.ugritchaichana-booth-homelab.gha-runner-angular.service
```

### 2.2 Rotating Runner Registration Token (60-Minute Expiry SOP)
Runner tokens expire after 1 hour. If re-enrolling or re-installing:
```bash
# 1. Generate registration token via GitHub CLI on host:
RUNNER_TOKEN=$(gh api --method POST \
  -H "Accept: application/vnd.github+json" \
  /repos/ugritchaichana/booth-homelab/actions/runners/registration-token \
  --jq .token)

# 2. Re-enroll CT 102 (.NET Runner):
pct exec 102 -- bash -c "
  cd /home/runner/actions-runner
  sudo ./svc.sh stop || true
  sudo ./svc.sh uninstall || true
  su - runner -c 'cd /home/runner/actions-runner && ./config.sh --url https://github.com/ugritchaichana/booth-homelab --token $RUNNER_TOKEN --name gha-runner-01 --labels self-hosted,linux,proxmox,dotnet --unattended --replace'
  sudo ./svc.sh install runner
  sudo ./svc.sh start
"

# 3. Re-enroll CT 103 (Angular Jest Runner):
pct exec 103 -- bash -c "
  cd /home/runner/actions-runner
  sudo ./svc.sh stop || true
  sudo ./svc.sh uninstall || true
  su - runner -c 'cd /home/runner/actions-runner && ./config.sh --url https://github.com/ugritchaichana/booth-homelab --token $RUNNER_TOKEN --name gha-runner-angular --labels self-hosted,linux,proxmox,angular --unattended --replace'
  sudo ./svc.sh install runner
  sudo ./svc.sh start
"
```

---

## 3. Direct In-Container Test Execution (Offline Manual Debugging)

To execute test suites directly inside LXC containers without triggering GitHub Actions:

```bash
# CT 102 (.NET 8 Unit & Integration Tests):
pct exec 102 -- su - runner -c "
  cd /home/runner/actions-runner/_work/booth-homelab/booth-homelab/apps/backend
  dotnet test SdetTestingRig.sln --configuration Release --logger 'console;verbosity=normal'
"

# CT 103 (Angular 18/19 Jest Standalone Tests - 19 Tests / 4 Suites):
pct exec 103 -- su - runner -c "
  cd /home/runner/actions-runner/_work/booth-homelab/booth-homelab/apps/frontend
  npx jest --ci --colors --coverage
"
```

---

## 4. MinIO S3 Operations & Disaster Recovery (CT 104)

### 4.1 Inspecting Buckets and Cache Payloads
```bash
# On CT 102 (.NET runner with mc installed):
pct exec 102 -- mc ls minio/build-cache
pct exec 102 -- mc ls minio/build-cache/branches/master/
pct exec 102 -- mc ls minio/build-cache/npm/
pct exec 102 -- mc ls minio/sdet-test-artifacts
```

### 4.2 Disaster Recovery & Bucket Re-initialization
If CT 104 is wiped, rebuilt, or cache corrupted:
```bash
# 1. Register a temporary admin alias (runners never hold root credentials):
pct exec 102 -- mc alias set minio-admin http://10.99.20.20:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"

# 2. Re-create required buckets:
pct exec 102 -- mc mb -p minio-admin/build-cache
pct exec 102 -- mc mb -p minio-admin/sdet-test-artifacts

# 3. Apply 7-day automatic TTL expiration:
pct exec 102 -- mc ilm rule add --expire-days 7 minio-admin/build-cache
pct exec 102 -- mc ilm rule add --expire-days 7 minio-admin/sdet-test-artifacts

# 4. Re-create the scoped IAM users, policies and runner reader aliases (the script also removes the admin alias):
python scripts/proxmox/configure_iam_cache_accounts.py
```

### 4.3 Cache Purge (Testing Cold Builds)
```bash
pct exec 102 -- mc rm --recursive --force minio/build-cache/branches/master/
pct exec 102 -- mc rm --recursive --force minio/build-cache/npm/
```

### 4.4 Enterprise Credential Hardening & Rotation SOP
> [!WARNING]
> **Credential Security Advisory:** Administrative and host credentials must be securely managed via environment variables and encrypted vaults. Never commit default credentials to version control.

- **Password Standard (NIST SP 800-63B / CIS):** $\ge 20$ chars for admin accounts, $\ge 32$ chars for API tokens, mixing uppercase, lowercase, numbers, and special symbols (`!@#$%^&*()-_+=[{]}|:;,.<>?~`). Zero dictionary words.
- **Rotate MinIO Root:** Update `/etc/conf.d/minio` on CT 104 (`MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`), restart service with `rc-service minio restart`, and update runner aliases:
  ```bash
  pct exec 102 -- mc alias set minio http://10.99.20.20:9000 <user> <password>
  pct exec 103 -- mc alias set minio http://10.99.20.20:9000 <user> <password>
  ```
- **Scoped IAM Service Accounts:** Create non-root users with least privilege (`mc admin user add` + `mc admin policy attach minio readonly|readwrite --user <user>`).

---

## 5. Hyper-V & Host Lifecycle Operations (Environment A)

PowerShell commands for host control (run as Administrator on Windows 11 host):

```powershell
# Check Proxmox-Lab VM Status
Get-VM "Proxmox-Lab"

# Start Hypervisor VM
Start-VM "Proxmox-Lab"

# Verify Nested AMD-V Virtualization (Must be True)
Get-VMProcessor "Proxmox-Lab" | Select-Object VMName, ExposeVirtualizationExtensions

# Enable MAC Address Spoofing for nested bridge network
Get-VMNetworkAdapter "Proxmox-Lab" | Set-VMNetworkAdapter -MacAddressSpoofing On
```

---

## 6. The 6 Empirical Traps & Runtime Mitigations

1. **OpenSSH Interactive Prompt Hang:** Never execute raw `ssh root@100.121.209.85` via Windows PowerShell; use Python Paramiko with explicit password.
2. **GitHub Actions Composite Action Order:** Always place `actions/checkout@v4` as the first step before calling local composite actions (`./.github/actions/...`).
3. **Container File Injection:** Host `/tmp` files are invisible in LXC; use `pct push <vmid> <host_path> <container_path>`.
4. **Debian 12 UsrMerge Path:** MinIO Client `mc` resides in `/bin/mc`; resolve dynamically via `$(command -v mc || echo '/usr/bin/mc')`.
5. **Pure Headless Angular JSdom Ceiling:** Never install Chrome/Chromium in CT 103; keep it headless with `jest-preset-angular` to respect the 1.5GB RAM ceiling.
6. **.NET Money Entity Default:** In `Core.Domain`, `Money.Currency` defaults to `"USD"` (not `"THB"`).

---

## 7. Disabling Automatic Copilot Pull Request Reviewer

If GitHub automatically attaches `copilot-pull-request-reviewer` to new pull requests:
1. Open account settings: [GitHub Copilot Settings](https://github.com/settings/copilot).
2. Click **Code review** in the sidebar.
3. Toggle off **Automatic Copilot code review**.
4. To remove Copilot from active pull requests:
   ```bash
   gh api --method DELETE repos/ugritchaichana/booth-homelab/pulls/<PR_NUMBER>/requested_reviewers -f "reviewers[]=copilot-pull-request-reviewer"
   ```

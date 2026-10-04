# 06. Operational Runbooks and Troubleshooting

## 1. Proxmox Container Lifecycle Commands

All containers on Proxmox VE can be inspected and managed from the host shell (`root@100.121.209.85`):

```bash
# List all containers and status
pct list

# Start / Stop / Restart container
pct start 102
pct stop 102
pct reboot 102

# Enter container interactive bash/sh
pct enter 102

# Execute command inside container directly from PVE
pct exec 102 -- systemctl status actions.runner.*
pct exec 104 -- service minio status
```

---

## 2. GitHub Actions Runner Maintenance

### Restarting the Runner Daemon
If the runner shows offline in GitHub:
```bash
# Inside CT 102 or via pct exec 102:
systemctl restart actions.runner.ugritchaichana-booth-homelab.gha-runner-01.service
systemctl status actions.runner.ugritchaichana-booth-homelab.gha-runner-01.service --no-pager
```

### Rotating Runner Registration Token
Runner tokens expire after 1 hour. If re-registering:
```bash
# Generate registration token via GitHub CLI on host:
gh api -X POST repos/ugritchaichana/booth-homelab/actions/runners/registration-token --jq .token

# On CT 102:
cd /home/runner/actions-runner
./config.sh remove --token <TOKEN>
./config.sh --url https://github.com/ugritchaichana/booth-homelab --token <NEW_TOKEN> --name pve-runner-01 --labels proxmox,linux,x64 --unattended
```

---

## 3. MinIO S3 Operations & Troubleshooting

### Inspecting Buckets and Objects
```bash
# On CT 102:
mc ls minio/build-cache
mc ls minio/build-cache/branches/master/
mc ls minio/test-artifacts
```

### Checking OpenRC Service Logs
```bash
# Inside CT 104 (Alpine):
service minio status
cat /var/log/minio.log
```

---

## 4. Hyper-V & Windows Host Network Rescue

If the Proxmox VM loses network connectivity following a Windows reboot or Hyper-V Default Switch subnet change:

1. **Verify Hyper-V Default Switch Subnet:**
   ```powershell
   Get-NetIPAddress -InterfaceAlias "vEthernet (Default Switch)"
   ```
2. **Renew Proxmox DHCP Lease on `vmbr0`:**
   ```bash
   dhclient -r vmbr0
   dhclient vmbr0
   ip addr show vmbr0
   ```
3. **Verify NAT Masquerade on Proxmox:**
   ```bash
   iptables -t nat -L POSTROUTING -n -v
   # If missing, re-apply:
   iptables -t nat -A POSTROUTING -s 10.99.20.0/24 -o vmbr0 -j MASQUERADE
   ```

---

## 5. Disabling Automatic Copilot Pull Request Reviewer

If GitHub automatically attaches `copilot-pull-request-reviewer` to new pull requests:
1. Open your GitHub account settings: [GitHub Copilot Settings](https://github.com/settings/copilot).
2. Click **Code review** in the sidebar.
3. Toggle off **Automatic Copilot code review**.
4. To remove Copilot from existing or active pull requests:
   ```bash
   gh api --method DELETE repos/ugritchaichana/booth-homelab/pulls/<PR_NUMBER>/requested_reviewers -f "reviewers[]=copilot-pull-request-reviewer"
   ```

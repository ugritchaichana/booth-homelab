# J9: Post-change regression gate (Windows + VM + Docker)

**Date:** 2026-10-06  
**Duration:** Docker startup 12.6 s, teardown: force-stop path used  
**VM:** pve01 confirmed running (Hyper-V Hypervisor Partition counter pve01:hvpt = 12 vCPU)

## Gate Results

| Check | Command/Metric | Expected | Actual | Status |
|---|---|---|---|---|
| 1a | `wsl -l -v` before | Debian Stopped, docker-desktop Stopped | Debian Stopped, docker-desktop Stopped | PASS |
| 1b | Debian boot time | N/A | 2.28 seconds | Recorded |
| 2 | RAM before Docker (MB) | Recorded, no threshold in brief | 7608 | Recorded |
| 3 | Docker status before | Stopped | Stopped, docker info exit 1 | PASS |
| 3a | Docker startup time (s) | N/A | 12.6 | Recorded |
| 3b | docker info exit code | 0 | 0 | PASS |
| 3c | Server Version | N/A | 29.8.2 | Recorded |
| 3d | RAM while Docker up (MB) | Recorded | 6063 | Recorded |
| 3e | `docker run --rm hello-world` | Exit 0, "Hello from Docker!" | Exit 0, "Hello from Docker!" | PASS |
| 3f | RAM after hello-world (MB) | Recorded | 6007 | Recorded |
| 3g | Min RAM during startup (MB) | ≥ 2048 | 6049 (at 12.6s) | PASS |
| 4 | C: free (GB) | ≥ 20 | 163.9 | PASS |
| 5 | VPN IPv4 routes | 7 | 7 | PASS |
| 6 | VPN services status | Recorded, no threshold in brief | Netbird Running, Tailscale Running | Recorded |
| 7 | Internet (1.1.1.1:443) | TcpTestSucceeded | True | PASS |
| 8 | RAM at end (MB) | ≥ 4096 | 7051 | PASS |
| 1c | `wsl -l -v` after | Debian Stopped/Running, docker-desktop Stopped | Debian Stopped, docker-desktop Stopped | PASS |

---

## Raw Outputs

### 1a. WSL Status Before

```
NAME              STATE           VERSION
* Debian            Stopped         2
  docker-desktop    Stopped         2
```

### 1b. Debian Boot (with timing)

```
Exit code: 0
Time: 2.2795477 seconds
```

### 2. RAM Available Before Docker

```
7608 MB
(Measured with WSL utility VM already running from Debian boot in step 1b)
```

### 3. Docker Desktop Startup, Poll, and Tests

**Starting Docker Desktop...**  
**Polling docker info (poll interval 5 s, max 180 s):**

```
  [2.2s] docker info exit 1, RAM available: 8844 MB
  [12.6s] docker info exit 0, RAM available: 6049 MB
Docker daemon is responsive!
```

**Server Version:**
```
Server Version: 29.8.2
```

**RAM available (Docker up, idle):**
```
6063 MB
```

**`docker run --rm hello-world` output:**
```
Exit code: 0
Hello from Docker!
```

**RAM available (Docker up, after hello-world):**
```
6007 MB
```

**Docker startup summary:**
```
Time to ready: 12.6 seconds
Min RAM during startup: 6049 MB at 12.6 seconds
hello-world exit code: 0
```

### 3h. Docker Teardown and Verification

**Attempted graceful shutdown:**

```
Attempting graceful shutdown with --quit...
[2026-10-06T09:09:12.483183900Z][Docker Desktop.exe] backend already running, signaling show-dashboard
```

`--quit` not supported on this Docker build (signals show-dashboard instead of exiting) → waited 20 s with no process exit → used `Stop-Process -Name 'Docker Desktop' -Force`.

**WSL termination:**

```
Terminating WSL docker-desktop distro...
The operation completed successfully.
Waiting 10 seconds for memory to settle...
```

**Final verification (processes and docker info):**

```
[No processes listed]

docker info exit: 1
```

Docker Desktop and all com.docker.* processes confirmed stopped; docker daemon unresponsive.

### 4. C: Drive Free Space

```
163.9 GB
```

### 5. Host VPN — IPv4 Routes Count

```
7
```

(Routes on interfaces not Wi-Fi, Loopback, vEthernet; excluding 0.0.0.0/0, /32, multicast 224.0.0.0/4–239.255.255.255)

### 6. Mesh VPN Services Status

```
Name       Status
----       ------
Netbird   Running
Tailscale Running
```

### 7. Host Internet Connectivity

```
TcpTestSucceeded: True
(Test-NetConnection 1.1.1.1 -Port 443)
```

### 8. RAM Available at End

```
7051 MB
(VM pve01 still running, Docker and docker-desktop WSL distro stopped)
WSL state: Debian Stopped, docker-desktop Stopped
```

### VM Confirmation

**Hyper-V Hypervisor Partition counter:**
```
InstanceName           CookedValue
--------               -----------
pve01:hvpt             12.00
_total                 12.00
```

**Total physical memory and arithmetic:**
```
Total physical memory: 43.8 GB
Available before Docker: 7608 MB
Arithmetic (total - available): 37243 MB ≈ pve01 20 GiB + host (CONSISTENT WITH)
```

---

## Summary

| Metric | Value |
|---|---|
| All checks | ✓ PASS |
| RAM before Docker | 7608 MB |
| Min RAM during Docker startup | 6049 MB (at 12.6s) |
| RAM while Docker idle | 6063 MB |
| RAM at end (Docker stopped) | 7051 MB |
| Docker startup time | 12.6 seconds |
| No RAM threshold breach | ✓ 2048 MB minimum not reached |
| VM status | ✓ CONFIRMED (pve01:hvpt) |

---

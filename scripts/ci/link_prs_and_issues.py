import json
import subprocess

PROJECT_ID = "PVT_kwHOBLpMNs4BlsmX"
FIELD_STATUS_ID = "PVTSSF_lAHOBLpMNs4BlsmXzhkYYrw"
STATUS_DONE_ID = "98236657"

# 1. Update Project Status for PR items to 'Done'
res = subprocess.run("gh project item-list 4 --owner ugritchaichana --format json", shell=True, capture_output=True, encoding="utf-8")
items = json.loads(res.stdout).get("items", [])

for item in items:
    content_type = item.get("type")
    item_id = item.get("id")
    title = item.get("content", {}).get("title", "")
    if content_type == "PullRequest":
        cmd = f"gh project item-edit --project-id {PROJECT_ID} --id {item_id} --field-id {FIELD_STATUS_ID} --single-select-option-id {STATUS_DONE_ID}"
        subprocess.run(cmd, shell=True, capture_output=True)
        print(f"[PROJECT] Set PR '{title}' status to Done")

# 2. Update Issue #12 Body with explicit PR URLs
issue_12_body = """### Summary
Conducted live performance benchmark tests across Master baseline, PR #1, and PR #2 to measure build and test acceleration.

### Linked Pull Requests & Verification Records
- **Pull Request #1:** https://github.com/ugritchaichana/booth-homelab/pull/1
  - **GHA Run:** https://github.com/ugritchaichana/booth-homelab/actions/runs/37225258263
  - **Result:** Cache HIT (71.68 MiB in 110ms @ 836 MiB/s) -> Tested ONLY `Billing.Api.UnitTests` -> Passed in 23s
- **Pull Request #2:** https://github.com/ugritchaichana/booth-homelab/pull/2
  - **GHA Run:** https://github.com/ugritchaichana/booth-homelab/actions/runs/37225396301
  - **Result:** Cache HIT (128ms) -> Partial Build in 3,616ms -> Tested ONLY `Order.Api.UnitTests` -> Passed in 24s

### Benchmark Telemetry Results
- **Cold Run (Master):** Build duration 4,630 ms | Generated 72MB Zstd cache to MinIO S3 in 1.4s.
- **PR #1 (Billing.Api modified):**
  - Downloaded 71.68 MiB from MinIO at **836.59 MiB/s** in **110 ms**.
  - Decompressed in **987 ms**.
  - Executed ONLY `Billing.Api.UnitTests` (Skipped `Order.Api.UnitTests` 100%).
  - Total pipeline time: **23s**.
- **PR #2 (Order.Api modified):**
  - Cache Hit! Downloaded in **128 ms**.
  - Recompiled in **3,616 ms** with MSBuild Timestamp Synchronization.
  - Executed ONLY `Order.Api.UnitTests` (Skipped `Billing.Api.UnitTests` 100%).
  - Saved new cache in **1,615 ms** | Total pipeline time: **24s**.
"""

import tempfile
with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False, suffix=".md") as tf:
    tf.write(issue_12_body)
    tf_path = tf.name

subprocess.run(f'gh issue edit 12 --repo ugritchaichana/booth-homelab --body-file "{tf_path}"', shell=True)
print("[ISSUE 12] Updated with PR #1 and PR #2 links")

# 3. Update PR #1 and PR #2 Bodies with backlinks to Issue #12 and Project Board
pr1_body = """### Overview
Test PR #1 to verify deep remote caching and affected test runner.

### Traceability & Verification
- **Issue Reference:** Closes #12
- **GitHub Project Board:** https://github.com/users/ugritchaichana/projects/4
- **Live GHA Execution Run:** https://github.com/ugritchaichana/booth-homelab/actions/runs/37225258263
- **Tested Target:** `Billing.Api.UnitTests` only (Order suites skipped)
"""

with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False, suffix=".md") as tf:
    tf.write(pr1_body)
    tf1_path = tf.name
subprocess.run(f'gh pr edit 1 --repo ugritchaichana/booth-homelab --body-file "{tf1_path}"', shell=True)
print("[PR 1] Updated with backlinks")

pr2_body = """### Overview
Test PR #2: Restore cache from base, partial build Order.Api, run affected tests ONLY for Order.Api, update cache.

### Traceability & Verification
- **Issue Reference:** Related to #12
- **GitHub Project Board:** https://github.com/users/ugritchaichana/projects/4
- **Live GHA Execution Run:** https://github.com/ugritchaichana/booth-homelab/actions/runs/37225396301
- **Tested Target:** `Order.Api.UnitTests` only (Billing suites skipped)
"""

with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False, suffix=".md") as tf:
    tf.write(pr2_body)
    tf2_path = tf.name
subprocess.run(f'gh pr edit 2 --repo ugritchaichana/booth-homelab --body-file "{tf2_path}"', shell=True)
print("[PR 2] Updated with backlinks")

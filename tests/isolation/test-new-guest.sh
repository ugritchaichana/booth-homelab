#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$repo/scripts/iac/new-guest.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fails=0

cat > "$work/tofu.sh" << 'STUB'
#!/usr/bin/env bash
echo "$*" >> "$STUB_TOFU_LOG"
case " $* " in
  *" plan -detailed-exitcode "*)
    code="$(head -n 1 "$STUB_PLAN_CODES")"
    tail -n +2 "$STUB_PLAN_CODES" > "$STUB_PLAN_CODES.next" && mv "$STUB_PLAN_CODES.next" "$STUB_PLAN_CODES"
    exit "${code:-0}"
    ;;
esac
STUB
cat > "$work/two-hosts.yml" << 'ROWS'
---
all:
  children:
    pve_hosts:
      hosts:
        pve01: {}
        example-pve02: {}
ROWS

export HOMELAB_TOFU_SH="$work/tofu.sh" HOMELAB_GUESTS_FILE="$work/guests.yml" STUB_TOFU_LOG="$work/tofu.log" STUB_PLAN_CODES="$work/plan.codes"

reset() {
  : > "$STUB_PLAN_CODES"
  printf -- '---\nguests: {}\n' > "$HOMELAB_GUESTS_FILE"
  : > "$STUB_TOFU_LOG"
}

run() {
  "$BASH" "$script" "$@" > "$work/out.txt" 2>&1 && rc=0 || rc=$?
}

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; sed 's/^/     | /' "$work/out.txt"; fails=$((fails + 1)); }

expect_exit() {
  local name="$1" want_rc="$2" pattern="$3"
  if [ "$rc" -eq "$want_rc" ] && grep -qE -- "$pattern" "$work/out.txt"; then pass "$name"; else fail "$name (rc=$rc, wanted rc=$want_rc and /$pattern/)"; fi
}

expect_rejected() {
  local name="$1" pattern="$2"
  if [ "$rc" -eq 1 ] && [ "$(grep -c . "$work/out.txt")" -eq 1 ] && grep -qE -- "$pattern" "$work/out.txt"     && [ ! -s "$STUB_TOFU_LOG" ] && [ "$(cat "$HOMELAB_GUESTS_FILE")" = "$(printf -- '---
guests: {}')" ]; then
    pass "$name"
  else
    fail "$name (rc=$rc, log=$(cat "$STUB_TOFU_LOG"))"
  fi
}

expect_file() {
  local name="$1" want="$2"
  if [ "$(cat "$HOMELAB_GUESTS_FILE")" = "$want" ]; then pass "$name"; else
    echo "FAIL $name"; sed 's/^/     | /' "$HOMELAB_GUESTS_FILE"; fails=$((fails + 1))
  fi
}

expect_log() {
  local name="$1" want="$2"
  if [ "$(cat "$STUB_TOFU_LOG")" = "$want" ]; then pass "$name"; else
    echo "FAIL $name"; sed 's/^/     | /' "$STUB_TOFU_LOG"; fails=$((fails + 1))
  fi
}

reset
run
expect_exit "no arguments is a usage error" 2 '^usage: new-guest.sh'
run --flavor aws/t3.medium
expect_exit "a missing template is a usage error" 2 '^usage: new-guest.sh'
run --flavor aws/t3.medium --template lxc-runner --bogus
expect_exit "an unknown option is a usage error" 2 '^usage: new-guest.sh'
run --flavor aws/t3.medium --template
expect_exit "an option without a value is a usage error" 2 '^usage: new-guest.sh'

reset
run --flavor aws/t3.nonexistent --template lxc-runner
expect_rejected "an unknown flavor exits 1 with one line and changes nothing" '^ERROR: flavor aws/t3.nonexistent is not in iac/tofu/flavors.json$'
run --flavor t3.medium --template lxc-runner
expect_rejected "a flavor without a provider exits 1" '^ERROR: flavor t3.medium is not in'
run --flavor aws/t3.medium --template windows-server
expect_rejected "an unknown template class exits 1 with one line" '^ERROR: template windows-server is not one of: lxc-runner vm-docker$'
run --flavor aws/t3.medium --template lxc-runner --role Bad_Role
expect_rejected "a role that is not a hostname exits 1" '^ERROR: role Bad_Role must be'
run --flavor aws/t3.medium --template lxc-runner --version 4
expect_rejected "a version without the v exits 1" '^ERROR: version 4 must look like v4$'
run --flavor aws/t3.medium --template lxc-runner --version v0
expect_rejected "version v0 exits 1" '^ERROR: version v0 must look like v4$'
run --flavor aws/t3.medium --template lxc-runner --role "$(printf 'a%.0s' $(seq 1 55))"
expect_rejected "a role that makes the name longer than 63 characters exits 1" '^ERROR: role a+ makes the name'
run --flavor aws/t3.medium --template lxc-runner --host nonexistent
expect_rejected "a host outside the inventory exits 1" '^ERROR: host nonexistent is not a pve_hosts entry'
HOMELAB_INVENTORY="$work/two-hosts.yml" run --flavor aws/t3.medium --template lxc-runner
expect_rejected "several hosts without --host exits 1" '^ERROR: several hosts in the inventory; pass --host: pve01 example-pve02$'

applied() { grep -c ' apply ' "$STUB_TOFU_LOG" || true; }
auto="guest pve01 apply -auto-approve -var=guests_file=$HOMELAB_GUESTS_FILE"
settled="guest pve01 plan -detailed-exitcode -var=guests_file=$HOMELAB_GUESTS_FILE"
init="guest pve01 init -input=false"
entry_lxc="$(printf -- '---\nguests:\n  pve01:\n    demo-lxc-runner:\n      flavor: aws/t3.medium\n      template_class: lxc-runner\n      slot: 1')"

reset
run --flavor aws/t3.medium --template lxc-runner --role demo
expect_exit "a valid request exits 0 and names the guest" 0 '^guest demo-lxc-runner on pve01: aws/t3.medium, lxc-runner, slot 1$'
expect_file "the entry is keyed role-class under the host with slot 1 and no pin" "$entry_lxc"
expect_log "without --apply the stack is initialised then planned, never applied" "$(printf '%s\nguest pve01 plan -var=guests_file=%s' "$init" "$HOMELAB_GUESTS_FILE")"

: > "$STUB_TOFU_LOG"
run --flavor aws/t3.medium --template lxc-runner --role demo --apply
expect_exit "re-adding the same role and class is idempotent" 0 'slot 1$'
expect_log "--apply applies without asking, then checks the plan is settled" "$(printf '%s\n%s\n%s' "$init" "$auto" "$settled")"
expect_file "the file is unchanged by the repeat" "$entry_lxc"

: > "$STUB_TOFU_LOG"; printf '2\n0\n' > "$STUB_PLAN_CODES"
run --flavor aws/t3.medium --template lxc-runner --role demo --apply
expect_exit "drift after the first apply: exit 0" 0 'slot 1$'
expect_log "drift triggers exactly one more apply and a final settled plan" "$(printf '%s\n%s\n%s\n%s\n%s' "$init" "$auto" "$settled" "$auto" "$settled")"

: > "$STUB_TOFU_LOG"; printf '2\n2\n' > "$STUB_PLAN_CODES"
run --flavor aws/t3.medium --template lxc-runner --role demo --apply
expect_exit "drift that persists fails with one line" 1 '^ERROR: the plan still shows changes after two applies'
if [ "$(applied)" -eq 2 ]; then pass "persistent drift stops after two applies"; else fail "persistent drift ran $(applied) applies"; fi

: > "$STUB_TOFU_LOG"; printf '1\n' > "$STUB_PLAN_CODES"
run --flavor aws/t3.medium --template lxc-runner --role demo --apply
expect_exit "a plan error after apply fails" 1 '^ERROR: plan failed with exit 1 after apply'
if [ "$(applied)" -eq 1 ]; then pass "a plan error does not trigger another apply"; else fail "a plan error ran $(applied) applies"; fi

: > "$STUB_PLAN_CODES"
run --flavor aws/t3.large --template lxc-runner --role demo --version v4
expect_exit "updating a role and class reports the same slot" 0 '^guest demo-lxc-runner on pve01: aws/t3.large, lxc-runner v4, slot 1$'
expect_file "an update replaces the fields, keeps the slot and records the pin" "$(printf -- '---\nguests:\n  pve01:\n    demo-lxc-runner:\n      flavor: aws/t3.large\n      template_class: lxc-runner\n      template_version: 4\n      slot: 1')"

run --flavor aws/t3.large --template lxc-runner --name demo
expect_file "--name is an alias of --role and an update without --version drops the pin" "$(printf -- '---\nguests:\n  pve01:\n    demo-lxc-runner:\n      flavor: aws/t3.large\n      template_class: lxc-runner\n      slot: 1')"

run --flavor aws/t3.medium --template vm-docker --role demo
expect_exit "the same role with the other class is a second guest in the next slot" 0 '^guest demo-vm-docker on pve01: aws/t3.medium, vm-docker, slot 2$'
if [ "$(grep -c 'template_class:' "$HOMELAB_GUESTS_FILE")" -eq 2 ] && grep -q '^    demo-lxc-runner:' "$HOMELAB_GUESTS_FILE" && grep -q '^    demo-vm-docker:' "$HOMELAB_GUESTS_FILE"; then pass "demo-lxc-runner and demo-vm-docker sit side by side"; else fail "the two classes of one role were not kept apart"; fi

reset
cat > "$HOMELAB_GUESTS_FILE" << 'ROWS'
---
guests:
  pve01:
    first-lxc-runner:
      flavor: aws/t3.medium
      template_class: lxc-runner
      slot: 1
    third-lxc-runner:
      flavor: aws/t3.medium
      template_class: lxc-runner
      slot: 3
  example-pve02:
    other-lxc-runner:
      flavor: aws/t3.medium
      template_class: lxc-runner
      slot: 2
ROWS
run --flavor aws/t3.small --template lxc-runner
expect_exit "a new guest takes the lowest free slot of its host and the default role" 0 '^guest guest-02-lxc-runner on pve01: aws/t3.small, lxc-runner, slot 2$'
run --flavor aws/t3.small --template lxc-runner --role last
expect_exit "the next new guest skips the used slots" 0 '^guest last-lxc-runner on pve01: .*slot 4$'
if grep -q 'other-lxc-runner:' "$HOMELAB_GUESTS_FILE" && [ "$(grep -c 'slot: 2' "$HOMELAB_GUESTS_FILE")" -eq 2 ]; then pass "another host's guests are kept and do not use up this host's slots"; else fail "another host's section was lost"; fi

reset
run --flavor aws/t3.medium --template lxc-runner --role demo --host pve01
expect_exit "--host pve01 is accepted" 0 '^guest demo-lxc-runner on pve01'

[ "$fails" -eq 0 ] && echo "all new-guest checks passed" || { echo "$fails new-guest check(s) failed" >&2; exit 1; }

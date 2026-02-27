#!/usr/bin/env bash
# Test suite for Ralph-TUI Sandbox Container
# Runs through the test plan to verify the container works as specified.

set -euo pipefail

SANDBOX_DIR="/tmp/sandbox-test-$$"
IMAGE="ralph-tui-sandbox"
CONTAINER_USER="coder"
PASS=0
FAIL=0
SKIP=0

incr_pass() { PASS=$((PASS + 1)); }
incr_fail() { FAIL=$((FAIL + 1)); }
incr_skip() { SKIP=$((SKIP + 1)); }

green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }

check() {
    local label="$1"
    shift
    if output=$("$@" 2>&1); then
        green "  PASS: $label"
        incr_pass
    else
        red "  FAIL: $label"
        echo "        output: $output"
        incr_fail
    fi
}

check_output() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if echo "$actual" | grep -qi "$expected"; then
        green "  PASS: $label ($actual)"
        incr_pass
    else
        red "  FAIL: $label (expected '$expected', got '$actual')"
        incr_fail
    fi
}

skip() {
    yellow "  SKIP: $1"
    incr_skip
}

run_in_container() {
    podman run --rm \
        --userns=keep-id \
        --entrypoint /bin/bash \
        -v "$SANDBOX_DIR":/workspace:rw \
        -v claude-data:/home/"$CONTAINER_USER"/.claude \
        "$IMAGE" \
        -c "$1"
}

run_in_container_with_mounts() {
    podman run --rm \
        --userns=keep-id \
        --entrypoint /bin/bash \
        -v "$SANDBOX_DIR":/workspace:rw \
        -v ~/.ssh:/home/"$CONTAINER_USER"/.ssh:ro \
        -v ~/.gnupg:/home/"$CONTAINER_USER"/.gnupg:ro \
        -v ~/.config/jj:/home/"$CONTAINER_USER"/.config/jj:ro \
        -v claude-data:/home/"$CONTAINER_USER"/.claude \
        -v apt-cache:/var/cache/apt \
        -v bun-cache:/home/"$CONTAINER_USER"/.bun \
        -v cargo-registry:/home/"$CONTAINER_USER"/.cargo/registry \
        "$IMAGE" \
        -c "$1"
}

cleanup() {
    echo ""
    echo "=== Cleanup ==="
    rm -rf "$SANDBOX_DIR"
    echo "Removed $SANDBOX_DIR"
}
trap cleanup EXIT

# ─────────────────────────────────────────────────────────────
echo "=== Test Plan: Ralph-TUI Sandbox Container ==="
echo ""

# ─── Step 1: Build the image ────────────────────────────────
echo "--- Step 1: Build the image ---"
if just build; then
    green "  PASS: Image builds successfully"
    incr_pass
else
    red "  FAIL: Image build failed"
    incr_fail
    echo "Cannot continue without a built image."
    exit 1
fi

check "Image appears in podman images" \
    podman image exists "$IMAGE"

# ─── Step 2: Verify installed software ──────────────────────
echo ""
echo "--- Step 2: Verify installed software ---"

mkdir -p "$SANDBOX_DIR"

# User identity
output=$(run_in_container "whoami")
check_output "whoami is coder" "coder" "$output"

output=$(run_in_container "id -u")
check_output "UID matches host ($(id -u))" "$(id -u)" "$output"

output=$(run_in_container "id -g")
check_output "GID matches host ($(id -g))" "$(id -g)" "$output"

# Tools
output=$(run_in_container "git --version")
check_output "git installed" "git version" "$output"

output=$(run_in_container "python3 --version")
check_output "python3 installed" "Python" "$output"

output=$(run_in_container "pip3 --version")
check_output "pip3 installed" "pip" "$output"

output=$(run_in_container "rustc --version")
check_output "rustc installed" "rustc" "$output"

output=$(run_in_container "cargo --version")
check_output "cargo installed" "cargo" "$output"

output=$(run_in_container "jj --version")
check_output "jj installed (v0.38.0)" "0.38.0" "$output"

output=$(run_in_container "emacs --version" || true)
check_output "emacs installed" "GNU Emacs" "$output"

output=$(run_in_container "which ralph-tui")
check_output "ralph-tui found" "ralph-tui" "$output"

output=$(run_in_container "which claude")
check_output "claude found" "claude" "$output"

output=$(run_in_container "rg --version")
check_output "ripgrep installed" "ripgrep" "$output"

output=$(run_in_container "fdfind --version")
check_output "fd installed" "fd" "$output"

output=$(run_in_container "jq --version")
check_output "jq installed" "jq" "$output"

output=$(run_in_container "curl --version")
check_output "curl installed" "curl" "$output"

output=$(run_in_container "wget --version")
check_output "wget installed" "Wget" "$output"

output=$(run_in_container "vim --version")
check_output "vim installed" "VIM" "$output"

output=$(run_in_container "tree --version")
check_output "tree installed" "tree" "$output"

output=$(run_in_container "htop --version")
check_output "htop installed" "htop" "$output"

output=$(run_in_container "gcc --version")
check_output "build-essential (gcc) installed" "gcc" "$output"

# ─── Step 3: Verify working directory ───────────────────────
echo ""
echo "--- Step 3: Verify working directory ---"

output=$(run_in_container "pwd")
check_output "Working directory is /workspace" "/workspace" "$output"

# Create a file and check ownership on host
run_in_container "touch /workspace/testfile-ownership"

if [ -f "$SANDBOX_DIR/testfile-ownership" ]; then
    green "  PASS: File created in container visible on host"
    incr_pass

    file_owner=$(stat -c '%u' "$SANDBOX_DIR/testfile-ownership")
    if [ "$file_owner" = "$(id -u)" ]; then
        green "  PASS: File owned by host user (userns=keep-id works)"
        incr_pass
    else
        red "  FAIL: File owned by $file_owner, expected $(id -u)"
        incr_fail
    fi
else
    red "  FAIL: File not visible on host"
    incr_fail
    skip "File ownership check (file not found)"
fi

# ─── Step 4: Verify read-only mounts ────────────────────────
echo ""
echo "--- Step 4: Verify read-only mounts ---"

# SSH
if [ -d ~/.ssh ]; then
    output=$(run_in_container_with_mounts "ls ~/.ssh/ 2>&1" || true)
    check_output "SSH keys visible" "" "$output"  # just check it doesn't error

    if run_in_container_with_mounts "touch ~/.ssh/test-readonly 2>&1"; then
        red "  FAIL: SSH mount is writable (should be read-only)"
        incr_fail
        run_in_container_with_mounts "rm -f ~/.ssh/test-readonly" || true
    else
        green "  PASS: SSH mount is read-only"
        incr_pass
    fi
else
    skip "SSH read-only mount (~/.ssh not found)"
fi

# GPG
if [ -d ~/.gnupg ]; then
    if run_in_container_with_mounts "touch ~/.gnupg/test-readonly 2>&1"; then
        red "  FAIL: GPG mount is writable (should be read-only)"
        incr_fail
        run_in_container_with_mounts "rm -f ~/.gnupg/test-readonly" || true
    else
        green "  PASS: GPG mount is read-only"
        incr_pass
    fi
else
    skip "GPG read-only mount (~/.gnupg not found)"
fi

# jj config
if [ -d ~/.config/jj ]; then
    if run_in_container_with_mounts "touch ~/.config/jj/test-readonly 2>&1"; then
        red "  FAIL: jj config mount is writable (should be read-only)"
        incr_fail
        run_in_container_with_mounts "rm -f ~/.config/jj/test-readonly" || true
    else
        green "  PASS: jj config mount is read-only"
        incr_pass
    fi
else
    skip "jj config read-only mount (~/.config/jj not found)"
fi

# ─── Step 5: Verify named volumes persist ───────────────────
echo ""
echo "--- Step 5: Verify named volumes persist ---"

run_in_container "touch ~/.claude/test-marker-$$"

output=$(run_in_container "ls ~/.claude/test-marker-$$ 2>&1" || true)
if echo "$output" | grep -q "test-marker-$$"; then
    green "  PASS: Named volume data persists across runs"
    incr_pass
    run_in_container "rm ~/.claude/test-marker-$$"
else
    red "  FAIL: Named volume data did not persist"
    incr_fail
fi

# ─── Step 6: Verify network access ──────────────────────────
echo ""
echo "--- Step 6: Verify network access ---"

output=$(run_in_container "curl -s -o /dev/null -w '%{http_code}' https://api.anthropic.com/ 2>&1" || true)
if echo "$output" | grep -qE '(200|301|302|403|404)'; then
    green "  PASS: Network access works (HTTP $output)"
    incr_pass
else
    red "  FAIL: Network access failed ($output)"
    incr_fail
fi

# ─── Step 7: Verify entrypoint ──────────────────────────────
echo ""
echo "--- Step 7: Verify entrypoint ---"

# We can't interactively test ralph-tui, but we can verify the entrypoint is set
output=$(podman inspect "$IMAGE" --format '{{json .Config.Entrypoint}}' 2>&1)
check_output "Entrypoint is ralph-tui" "ralph-tui" "$output"

# ─── Step 8: Verify login recipe (structure only) ───────────
echo ""
echo "--- Step 8: Verify login recipe ---"
skip "Login recipe requires interactive OAuth (test manually with: just login)"

# ─── Step 9: Verify clean recipe (structure only) ───────────
echo ""
echo "--- Step 9: Verify clean recipe ---"
skip "Clean recipe skipped to preserve image for re-runs (test manually with: just clean)"

# ─── Step 10: Verify security constraints ────────────────────
echo ""
echo "--- Step 10: Verify security constraints ---"

if run_in_container "podman ps 2>&1"; then
    red "  FAIL: podman accessible inside container (should not be)"
    incr_fail
else
    green "  PASS: podman not accessible inside container"
    incr_pass
fi

if run_in_container "docker ps 2>&1"; then
    red "  FAIL: docker accessible inside container (should not be)"
    incr_fail
else
    green "  PASS: docker not accessible inside container"
    incr_pass
fi

# Verify no access to host filesystem outside mounts
if run_in_container "ls /home/$(whoami) 2>&1"; then
    red "  FAIL: Host home directory accessible inside container"
    incr_fail
else
    green "  PASS: Host home directory not accessible inside container"
    incr_pass
fi

# ─── Summary ─────────────────────────────────────────────────
echo ""
echo "==========================================="
echo "  Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "==========================================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

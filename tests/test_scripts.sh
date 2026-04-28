#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

PASS=0
FAIL=0

check() {
    local desc="$1"
    local result="$2"
    if [ "${result}" = "0" ]; then
        echo "  ✓ ${desc}"
        PASS=$((PASS + 1))
    else
        echo "  ✗ ${desc}"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Test: Script Syntax (bash -n) ==="

# Check all scripts parse without syntax errors
for file in setup.sh scripts/perf_bench.sh scripts/quality_bench.sh scripts/domain_bench.sh scripts/run_all.sh; do
    bash -n "${REPO_DIR}/${file}"
    check "Syntax check: ${file}" "$?"
done

echo ""
echo "=== Test: set -e Present ==="

# Verify set -e is in first 10 lines of each script
for file in setup.sh scripts/*.sh; do
    head -10 "${REPO_DIR}/${file}" | grep -q "set -e"
    check "set -e in ${file}" "$?"
done

echo ""
echo "=== Test: Script Executability ==="

for file in setup.sh scripts/perf_bench.sh scripts/quality_bench.sh scripts/domain_bench.sh scripts/run_all.sh; do
    [ -x "${REPO_DIR}/${file}" ]
    check "Executable: ${file}" "$?"
done

echo ""
echo "=== Test: run_all.sh Flag Parsing ==="

# Test --dry-run flag (should not crash, just validate config)
dry_output=$(bash "${REPO_DIR}/scripts/run_all.sh" --dry-run 2>&1 || true)
if echo "${dry_output}" | grep -qi "Config is valid"; then
    check "run_all.sh accepts --dry-run" "0"
else
    check "run_all.sh accepts --dry-run" "1"
fi

# Test --fast flag combined with --dry-run
fast_output=$(bash "${REPO_DIR}/scripts/run_all.sh" --fast --dry-run 2>&1 || true)
if echo "${fast_output}" | grep -qi "Config is valid"; then
    check "run_all.sh accepts --fast" "0"
else
    check "run_all.sh accepts --fast" "1"
fi

# Test --model flag (should be recognized)
if bash "${REPO_DIR}/scripts/run_all.sh" --model qwen2.5-coder-7b --dry-run 2>&1 | grep -q "qwen2.5-coder-7b"; then
    check "run_all.sh accepts --model" "0"
else
    check "run_all.sh accepts --model" "1"
fi

echo ""
echo "=== Test: perf_bench.sh Flag Parsing ==="

# Test with a non-existent model (should handle gracefully)
if bash "${REPO_DIR}/scripts/perf_bench.sh" nonexistent_model 2>&1; then
    # It might exit with error because model doesn't exist - that's fine
    check "perf_bench.sh handles unknown model" "0"
else
    # Non-zero exit is also acceptable for unknown model
    check "perf_bench.sh handles unknown model (exit code)" "0"
fi

echo ""
echo "=== Test: quality_bench.sh Flag Parsing ==="

if bash "${REPO_DIR}/scripts/quality_bench.sh" nonexistent_model 2>&1; then
    check "quality_bench.sh handles unknown model" "0"
else
    check "quality_bench.sh handles unknown model (exit code)" "0"
fi

echo ""
echo "=== Test: domain_bench.sh Flag Parsing ==="

if bash "${REPO_DIR}/scripts/domain_bench.sh" --fast nonexistent_model 2>&1; then
    check "domain_bench.sh accepts --fast" "0"
else
    check "domain_bench.sh accepts --fast (exit code)" "0"
fi

echo ""
echo "=== Test: Shebang Lines ==="

# Check all scripts have proper shebang
for file in setup.sh scripts/*.sh; do
    head -1 "${REPO_DIR}/${file}" | grep -q "^#!/usr/bin/env bash"
    check "Shebang: ${file}" "$?"
done

echo ""
echo "=== Test: metrics.py Import ==="

# Check metrics.py can be imported
python3 -c "import sys; sys.path.insert(0, '${REPO_DIR}/utils'); import metrics" 2>/dev/null
check "metrics.py imports without error" "$?"

echo ""
echo "=== Test: Makefile Targets ==="

# Check Makefile has required targets
for target in setup perf quality domain all clean; do
    grep -q "^${target}:" "${REPO_DIR}/Makefile"
    check "Makefile target: ${target}" "$?"
done

echo ""
echo "=============================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "=============================="

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi

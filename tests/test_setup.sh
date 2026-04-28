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

echo "=== Test: Project Structure ==="

# Check required directories
for dir in config scripts utils results tests; do
    [ -d "${REPO_DIR}/${dir}" ]
    check "Directory exists: ${dir}" "$?"
done

# Check required files
for file in README.md requirements.txt setup.sh Makefile; do
    [ -f "${REPO_DIR}/${file}" ]
    check "File exists: ${file}" "$?"
done

# Check script files
for file in perf_bench.sh quality_bench.sh domain_bench.sh run_all.sh; do
    [ -f "${REPO_DIR}/scripts/${file}" ]
    check "Script exists: scripts/${file}" "$?"
done

# Check utils
[ -f "${REPO_DIR}/utils/metrics.py" ]
check "File exists: utils/metrics.py" "$?"

# Check test files
for file in test_setup.sh test_metrics.py test_scripts.sh; do
    [ -f "${REPO_DIR}/tests/${file}" ]
    check "Test file exists: tests/${file}" "$?"
done

echo ""
echo "=== Test: File Permissions ==="

# Check scripts are executable
for file in setup.sh scripts/perf_bench.sh scripts/quality_bench.sh scripts/domain_bench.sh scripts/run_all.sh; do
    [ -x "${REPO_DIR}/${file}" ]
    check "Executable: ${file}" "$?"
done

echo ""
echo "=== Test: requirements.txt ==="

# Check required packages
for pkg in lm-eval bigcode-eval pandas pyyaml rich; do
    grep -q "${pkg}" "${REPO_DIR}/requirements.txt"
    check "Package in requirements.txt: ${pkg}" "$?"
done

echo ""
echo "=== Test: config/models.yaml ==="

# Check YAML is valid
python3 -c "import yaml; yaml.safe_load(open('${REPO_DIR}/config/models.yaml'))"
check "models.yaml is valid YAML" "$?"

# Check required model fields
python3 -c "
import yaml
with open('${REPO_DIR}/config/models.yaml') as f:
    config = yaml.safe_load(f)
models = config.get('models', {})
assert len(models) > 0, 'No models defined'
for name, info in models.items():
    assert 'path' in info, f'Missing path for {name}'
    assert 'api_model' in info, f'Missing api_model for {name}'
    assert 'quant' in info, f'Missing quant for {name}'
"
check "models.yaml has valid model entries" "$?"

echo ""
echo "=== Test: Script Headers ==="

# Check all scripts have set -e
for file in setup.sh scripts/*.sh; do
    head -5 "${REPO_DIR}/${file}" | grep -q "set -e"
    check "set -e in ${file}" "$?"
done

echo ""
echo "=== Test: No Hardcoded Absolute Paths ==="

# Check for hardcoded /home/ paths in scripts
if grep -rn '/home/amine\|/usr/local/bin\|/opt/' "${REPO_DIR}/setup.sh" "${REPO_DIR}/scripts/"*.sh 2>/dev/null; then
    check "No hardcoded absolute paths" "1"
else
    check "No hardcoded absolute paths" "0"
fi

echo ""
echo "=============================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "=============================="

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi

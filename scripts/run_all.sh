#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG="${REPO_DIR}/config/models.yaml"
RESULTS_DIR="${REPO_DIR}/results"
METRICS_SCRIPT="${REPO_DIR}/utils/metrics.py"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[ALL]${NC}   $*"; }
warn()  { echo -e "${YELLOW}[ALL]${NC}   $*"; }
error() { echo -e "${RED}[ALL]${NC}  $*"; }

# Parse flags
FAST_MODE=0
FILTER_MODEL=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fast) FAST_MODE=1; shift ;;
        --model) FILTER_MODEL="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        *) shift ;;
    esac
done

mkdir -p "${RESULTS_DIR}"

DATE_STR=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${RESULTS_DIR}/run_${DATE_STR}.log"

# Dry-run: validate config and list models
if [ "${DRY_RUN}" -eq 1 ]; then
    info "Dry-run mode. Validating configuration..."

    if [ ! -f "${CONFIG}" ]; then
        error "Config not found: ${CONFIG}"
        exit 1
    fi

    python3 -c "
import yaml
with open('${CONFIG}') as f:
    config = yaml.safe_load(f)
models = config.get('models', {})
if not models:
    print('  No models registered.')
else:
    for name, info in models.items():
        path = info.get('path', 'N/A')
        quant = info.get('quant', 'N/A')
        api = info.get('api_model', 'N/A')
        print(f'  {name}: {path} ({quant}) -> {api}')
print('')
print('Config is valid. Remove --dry-run to execute benchmarks.')
"
    exit 0
fi

# Get model list
get_models() {
    python3 -c "
import yaml, sys
with open('${CONFIG}') as f:
    config = yaml.safe_load(f)
for name, info in config.get('models', {}).items():
    print(f\"{name}|{info['path']}|{info['api_model']}\")
" 2>/dev/null || { error "Failed to parse ${CONFIG}"; exit 1; }
}

MODELS=$(get_models)

if [ -z "${MODELS}" ]; then
    error "No models found in ${CONFIG}"
    exit 1
fi

if [ -n "${FILTER_MODEL}" ]; then
    if ! echo "${MODELS}" | grep -q "^${FILTER_MODEL}|"; then
        error "Model '${FILTER_MODEL}' not found in config"
        exit 1
    fi
    MODELS=$(echo "${MODELS}" | grep "^${FILTER_MODEL}|")
fi

info "Starting full benchmark suite..."
info "Date: ${DATE_STR}"
if [ "${FAST_MODE}" -eq 1 ]; then
    info "Fast mode: enabled"
fi
if [ -n "${FILTER_MODEL}" ]; then
    info "Filtering to model: ${FILTER_MODEL}"
fi
info "Results directory: ${RESULTS_DIR}"
info "Log file: ${LOG_FILE}"
echo "" | tee "${LOG_FILE}"

# Run benchmarks in sequence
run_benchmark() {
    local script="$1"
    local label="$2"
    local extra_args="${3:-}"

    info "=== Running ${label} ==="
    echo "=== ${label} ===" | tee -a "${LOG_FILE}"

    if [ -x "${script}" ]; then
        bash "${script}" ${FILTER_MODEL} ${extra_args} 2>&1 | tee -a "${LOG_FILE}"
    else
        error "${script} not found or not executable"
        echo "FAILED: ${script} not found" | tee -a "${LOG_FILE}"
        return 1
    fi

    echo "" | tee -a "${LOG_FILE}"
    info "=== ${label} complete ==="
}

# 1. Performance
run_benchmark "${SCRIPT_DIR}/perf_bench.sh" "Performance Benchmark"

# 2. Quality
run_benchmark "${SCRIPT_DIR}/quality_bench.sh" "Quality Benchmark"

# 3. Domain
if [ "${FAST_MODE}" -eq 1 ]; then
    run_benchmark "${SCRIPT_DIR}/domain_bench.sh" "Domain Benchmark (fast)" "--fast"
else
    run_benchmark "${SCRIPT_DIR}/domain_bench.sh" "Domain Benchmark"
fi

# Generate summary
info "=== Generating summary ==="
echo "" | tee -a "${LOG_FILE}"

if [ -f "${METRICS_SCRIPT}" ]; then
    python3 "${METRICS_SCRIPT}" 2>&1 | tee -a "${LOG_FILE}"
else
    warn "metrics.py not found at ${METRICS_SCRIPT}"
fi

info "=== Benchmark suite complete ==="
info "Results saved in: ${RESULTS_DIR}/"
info "Log file: ${LOG_FILE}"

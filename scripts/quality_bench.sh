#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG="${REPO_DIR}/config/models.yaml"
RESULTS_DIR="${REPO_DIR}/results"
API_PORT=8081
SERVER_PID=""

# Auto-discover llama.cpp binaries
for candidate in \
    "${REPO_DIR}/../llama.cpp/build/bin" \
    "${HOME}/llama.cpp/build/bin" \
    "${HOME}/git/llama.cpp/build/bin" \
    "/usr/local/bin" \
; do
    if [ -x "${candidate}/llama-bench" ] && [ -x "${candidate}/llama-server" ]; then
        export PATH="${candidate}:${PATH}"
        break
    fi
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[QUAL]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[QUAL]${NC}  $*"; }
error() { echo -e "${RED}[QUAL]${NC} $*"; }

cleanup() {
    if [ -n "${SERVER_PID}" ] && kill -0 "${SERVER_PID}" 2>/dev/null; then
        info "Stopping llama-server (PID ${SERVER_PID})..."
        kill "${SERVER_PID}" 2>/dev/null || true
        wait "${SERVER_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

get_models() {
    python3 -c "
import yaml, sys
with open('${CONFIG}') as f:
    config = yaml.safe_load(f)
for name, info in config.get('models', {}).items():
    print(f\"{name}|{info['path']}|{info['api_model']}\")
" 2>/dev/null || { error "Failed to parse ${CONFIG}"; exit 1; }
}

ensure_server() {
    if curl -s "http://127.0.0.1:${API_PORT}/health" &>/dev/null; then
        info "llama-server already running on port ${API_PORT}"
        return 0
    fi

    local model_path="$1"
    model_path="${model_path/#\~/$HOME}"

    if [ ! -f "${model_path}" ]; then
        warn "Model file not found: ${model_path}"
        return 1
    fi

    info "Starting llama-server for quality benchmarks..."
    llama-server \
        -m "${model_path}" \
        -c 8192 \
        --port "${API_PORT}" \
        --ngl 99 \
        --host 127.0.0.1 \
        --host 0.0.0.0 \
        &>/dev/null &
    SERVER_PID=$!

    local retries=30
    while [ $retries -gt 0 ]; do
        if curl -s "http://127.0.0.1:${API_PORT}/health" &>/dev/null; then
            info "Server ready (PID ${SERVER_PID})"
            return 0
        fi
        sleep 1
        retries=$((retries - 1))
    done

    error "Server failed to start"
    return 1
}

run_quality_bench() {
    local model_name="$1"
    local date_str
    date_str=$(date +%Y%m%d_%H%M%S)
    local output_json="${RESULTS_DIR}/quality_${model_name}_${date_str}.json"
    local output_csv="${RESULTS_DIR}/quality_${model_name}_${date_str}.csv"

    info "Running quality benchmarks for ${model_name}..."

    # Run lm-eval for general benchmarks
    info "Running lm-eval (humaneval, gsm8k, hellaswag)..."
    lm_eval \
        --model vllm \
        --model_args pretrained=http://127.0.0.1:${API_PORT}/v1 \
        --tasks humaneval,gsm8k,hellaswag \
        --limit 50 \
        --batch auto \
        --output_path "${RESULTS_DIR}/lm_eval_${model_name}_${date_str}" \
        --log_samples \
        --verbosity WARNING 2>&1 | tee "${RESULTS_DIR}/lm_eval_${model_name}_${date_str}.log"

    # Collect results
    local eval_results="${RESULTS_DIR}/lm_eval_${model_name}_${date_str}_results.json"
    if [ -f "${eval_results}" ]; then
        cp "${eval_results}" "${output_json}"
    else
        # Create a minimal results file if lm-eval output is in a different format
        echo "{}" > "${output_json}"
    fi

    # Run bigcode-eval for HumanEval+
    info "Running bigcode-eval (humaneval+)..."
    bigcode_eval \
        --model gpt2 \
        --tasks humanevalplus \
        --limit 50 \
        --max_length_generation 2048 \
        --temperature 0.2 \
        --batch_size 1 \
        --save_generations \
        --generation_output_path "${RESULTS_DIR}/bigcode_${model_name}_${date_str}" 2>&1 | tee "${RESULTS_DIR}/bigcode_${model_name}_${date_str}.log" || warn "bigcode-eval failed (may need additional setup)"

    # Generate summary
    info "Generating summary for ${model_name}..."
    python3 -c "
import json, os, glob

results = {}

# Parse lm-eval results
for f in glob.glob('${RESULTS_DIR}/lm_eval_${model_name}_*_results.json'):
    with open(f) as fh:
        data = json.load(fh)
        if isinstance(data, dict):
            for task, scores in data.get('results', {}).items():
                for metric, value in scores.items():
                    if isinstance(value, (int, float)):
                        key = f'{task}.{metric}'
                        results[key] = value

# Parse bigcode-eval results
for f in glob.glob('${RESULTS_DIR}/bigcode_${model_name}_*_results.json'):
    with open(f) as fh:
        data = json.load(fh)
        if isinstance(data, dict):
            for k, v in data.items():
                if isinstance(v, (int, float)):
                    results[k] = v

# Write combined results
with open('${output_json}', 'w') as f:
    json.dump(results, f, indent=2)

# Print summary
print('')
print('  Quality Summary for ${model_name}:')
for k, v in sorted(results.items()):
    if isinstance(v, float):
        print(f'    {k}: {v:.4f}')
    else:
        print(f'    {k}: {v}')
"

    info "Results saved to ${output_json}"
}

main() {
    mkdir -p "${RESULTS_DIR}"

    local filter_model="${1:-}"

    local models
    models=$(get_models)

    if [ -z "${models}" ]; then
        error "No models found in ${CONFIG}"
        exit 1
    fi

    while IFS='|' read -r name path api_model; do
        if [ -n "${filter_model}" ] && [ "${name}" != "${filter_model}" ]; then
            continue
        fi

        if ensure_server "${path}"; then
            run_quality_bench "${name}" || true
            # Keep server running for next model if any
        fi
    done <<< "${models}"

    info "Quality benchmarks complete. Results in ${RESULTS_DIR}/"
}

main "$@"

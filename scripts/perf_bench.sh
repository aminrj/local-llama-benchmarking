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

info()  { echo -e "${GREEN}[PERF]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[PERF]${NC}  $*"; }
error() { echo -e "${RED}[PERF]${NC} $*"; }

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

server_is_running() {
    curl -s "http://127.0.0.1:${API_PORT}/health" &>/dev/null
}

start_server() {
    local model_path="$1"
    # Expand ~ in path
    model_path="${model_path/#\~/$HOME}"

    if [ ! -f "${model_path}" ]; then
        warn "Model file not found: ${model_path}. Skipping."
        return 1
    fi

    info "Starting llama-server for ${model_path}..."
    llama-server \
        -m "${model_path}" \
        -c 8192 \
        --port "${API_PORT}" \
        --ngl 99 \
        --host 127.0.0.1 \
        --host 0.0.0.0 \
        &>/dev/null &
    SERVER_PID=$!

    # Wait for server to be ready
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

run_perf_bench() {
    local model_name="$1"
    local model_path="$2"
    local date_str
    date_str=$(date +%Y%m%d_%H%M%S)
    local output_file="${RESULTS_DIR}/perf_${model_name}_${date_str}.csv"

    # Expand ~ in path
    model_path="${model_path/#\~/$HOME}"

    if [ ! -f "${model_path}" ]; then
        warn "Model file not found: ${model_path}. Skipping ${model_name}."
        return 1
    fi

    info "Running performance benchmark for ${model_name}..."
    info "Model: ${model_path}"

    llama-bench \
        -m "${model_path}" \
        -p "512,4096" \
        -n 128 \
        -r 3 \
        -fa 1 \
        -ngl 99 \
        -ot csv \
        -of "${output_file}" 2>&1

    if [ ! -f "${output_file}" ] || [ ! -s "${output_file}" ]; then
        warn "No output generated for ${model_name}. Checking for stderr output..."
        # Try without -of flag, parse stderr
        llama-bench \
            -m "${model_path}" \
            -p "512,4096" \
            -n 128 \
            -r 3 \
            -fa 1 \
            -ngl 99 2>&1 | tee "${output_file}"
    fi

    # Print summary
    if command -v jq &>/dev/null && [ -f "${output_file}" ]; then
        info "Summary for ${model_name}:"
        # Try to parse CSV output
        if head -1 "${output_file}" | grep -q "context"; then
            echo ""
            echo "  Context | PP TPS | TG TPS"
            echo  "  --------|--------|--------"
            tail -n +2 "${output_file}" | while IFS=',' read -r ctx pp tg rest; do
                printf "  %-7s | %6s | %6s\n" "${ctx}" "${pp}" "${tg}"
            done
        else
            echo "  (raw output saved to ${output_file})"
        fi
    else
        echo "  (results saved to ${output_file})"
    fi
    echo ""
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

    # Check if a server is already running (e.g. from 'codemode')
    local server_was_preexisting=false
    if server_is_running; then
        info "llama-server already running on port ${API_PORT} — reusing it."
        server_was_preexisting=true
    fi

    while IFS='|' read -r name path api_model; do
        if [ -n "${filter_model}" ] && [ "${name}" != "${filter_model}" ]; then
            continue
        fi

        if [ "${server_was_preexisting}" = true ]; then
            # Reuse existing server — only run the benchmark
            run_perf_bench "${name}" "${path}" || true
        else
            # Start our own server, bench, then clean up
            if start_server "${path}"; then
                run_perf_bench "${name}" "${path}" || true
                if [ -n "${SERVER_PID}" ] && kill -0 "${SERVER_PID}" 2>/dev/null; then
                    kill "${SERVER_PID}" 2>/dev/null || true
                    wait "${SERVER_PID}" 2>/dev/null || true
                    SERVER_PID=""
                fi
                sleep 1
            fi
        fi
    done <<< "${models}"

    info "Performance benchmarks complete. Results in ${RESULTS_DIR}/"
}

main "$@"

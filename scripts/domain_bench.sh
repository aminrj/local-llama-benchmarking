#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG="${REPO_DIR}/config/models.yaml"
PROMPTS_JSON="${REPO_DIR}/config/prompts.json"
RESULTS_DIR="${REPO_DIR}/results"
API_PORT=8081
SERVER_PID=""
FAST_MODE=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[DOMA]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[DOMA]${NC}  $*"; }
error() { echo -e "${RED}[DOMA]${NC} $*"; }

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

    info "Starting llama-server for domain benchmarks..."
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

PROMPT_LABELS=(simple_python security_tool context_math vuln_spotting owasp_mapping)
NUM_PROMPTS=5

send_prompt() {
    local prompt_idx="$1"
    local prompt
    prompt=$(jq -r ".[$prompt_idx]" "${PROMPTS_JSON}")
    local label="${PROMPT_LABELS[$prompt_idx]}"
    local start_time end_time duration tokens tok_s
    local payload_file
    payload_file=$(mktemp)

    start_time=$(date +%s%N)

    # Build JSON payload via jq to avoid escaping issues with prompt content
    jq -n \
        --arg model "${API_MODEL:-default}" \
        --arg content "${prompt}" \
        '{model: $model, messages: [{role: "user", content: $content}], max_tokens: 2048, temperature: 0.7}' \
        > "${payload_file}"

    local response
    response=$(curl -s -w "\n%{http_code}" \
        -X POST "http://127.0.0.1:${API_PORT}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d @"${payload_file}")

    rm -f "${payload_file}"

    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 ))  # milliseconds

    local http_code
    http_code=$(echo "${response}" | tail -1)
    local body
    body=$(echo "${response}" | sed '$d')

    if [ "${http_code}" != "200" ]; then
        warn "Request failed with HTTP ${http_code}"
        echo "0,0,0"
        return 1
    fi

    # Extract token count and content length
    tokens=$(echo "${body}" | jq -r '.usage.total_tokens // 0' 2>/dev/null || echo "0")
    local completion_tokens
    completion_tokens=$(echo "${body}" | jq -r '.usage.completion_tokens // 0' 2>/dev/null || echo "0")

    if [ "${completion_tokens}" != "0" ] && [ "${duration}" -gt 0 ]; then
        tok_s=$(python3 -c "print(round(${completion_tokens} / (${duration} / 1000), 2))")
    else
        tok_s="0"
    fi

    echo "${duration},${tokens},${tok_s}"
}

run_domain_bench() {
    local model_name="$1"
    local date_str
    date_str=$(date +%Y%m%d_%H%M%S)
    local output_file="${RESULTS_DIR}/domain_${model_name}_${date_str}.csv"

    info "Running domain benchmarks for ${model_name}..."
    info "Sending ${NUM_PROMPTS} prompts..."

    # Write CSV header
    echo "prompt,latency_ms,tokens,tok_s" > "${output_file}"

    local i=0
    for prompt_label in "${PROMPT_LABELS[@]}"; do
        if [ "${FAST_MODE}" -eq 1 ] && [ $i -gt 2 ]; then
            info "Skipping prompt ${i} in fast mode"
            i=$((i + 1))
            continue
        fi

        info "Prompt ${i}: ${prompt_label}..."
        local result
        result=$(send_prompt "${i}")

        echo "${prompt_label},${result}" >> "${output_file}"
        i=$((i + 1))
    done

    # Print summary
    info "Summary for ${model_name}:"
    echo ""
    echo "  Prompt            | Latency (ms) | Tokens | tok/s"
    echo "  ------------------|-------------|--------|------"
    tail -n +2 "${output_file}" | while IFS=',' read -r label latency tokens tok_s; do
        printf "  %-16s | %12s | %6s | %6s\n" "${label}" "${latency}" "${tokens}" "${tok_s}"
    done
    echo ""
    info "Results saved to ${output_file}"
}

main() {
    mkdir -p "${RESULTS_DIR}"

    local filter_model="${1:-}"

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --fast) FAST_MODE=1; shift ;;
            --model) filter_model="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

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

        API_MODEL="${api_model}"

        if ensure_server "${path}"; then
            run_domain_bench "${name}" || true
            # Stop server after each model
            if [ -n "${SERVER_PID}" ] && kill -0 "${SERVER_PID}" 2>/dev/null; then
                kill "${SERVER_PID}" 2>/dev/null || true
                wait "${SERVER_PID}" 2>/dev/null || true
                SERVER_PID=""
            fi
            sleep 1
        fi
    done <<< "${models}"

    info "Domain benchmarks complete. Results in ${RESULTS_DIR}/"
}

main "$@"

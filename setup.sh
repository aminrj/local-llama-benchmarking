#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/results"
REQUIREMENTS="${SCRIPT_DIR}/requirements.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Check prerequisites ---
check_cmd() {
    if ! command -v "$1" &>/dev/null; then
        error "'$1' not found. Please install it."
        exit 1
    fi
    info "'$1' found: $(command -v "$1")"
}

info "Checking prerequisites..."
check_cmd python3
check_cmd pip
check_cmd curl
check_cmd jq

# --- Check llama.cpp tools ---
install_llama_cpp() {
    local llama_cpp_dir="${LLAMA_CPP_DIR:-${SCRIPT_DIR}/../llama.cpp}"

    # Check known build locations first
    for candidate in \
        "${llama_cpp_dir}/build/bin" \
        "${llama_cpp_dir}/bin" \
        "${llama_cpp_dir}" \
    ; do
        if [ -x "${candidate}/llama-bench" ] && [ -x "${candidate}/llama-server" ]; then
            export PATH="${candidate}:${PATH}"
            info "llama.cpp tools found at ${candidate}"
            return 0
        fi
    done

    # Check PATH
    if command -v llama-bench &>/dev/null && command -v llama-server &>/dev/null; then
        info "llama.cpp tools found in PATH"
        return 0
    fi

    # Try to build from source
    if [ -d "${llama_cpp_dir}" ]; then
        info "Found llama.cpp at ${llama_cpp_dir}, building with CMake..."
        (cd "${llama_cpp_dir}" && cmake -B build -DLLAMA_CUDA=ON -DLLAMA_CURL=ON && cmake --build build -j"$(nproc)")
        if [ -x "${llama_cpp_dir}/build/bin/llama-bench" ]; then
            export PATH="${llama_cpp_dir}/build/bin:${PATH}"
            info "llama.cpp tools built successfully"
            return 0
        fi
    fi

    error "llama.cpp tools (llama-bench, llama-server) not available."
    error "Please set LLAMA_CPP_DIR to your llama.cpp build location."
    exit 1
}

install_llama_cpp

# --- Create results directory ---
mkdir -p "${RESULTS_DIR}"
info "Results directory: ${RESULTS_DIR}"

# --- Install Python dependencies ---
if [ -f "${REQUIREMENTS}" ]; then
    info "Installing Python dependencies from ${REQUIREMENTS}..."
    pip install --quiet --upgrade -r "${REQUIREMENTS}"
    info "Python dependencies installed"
else
    error "requirements.txt not found at ${REQUIREMENTS}"
    exit 1
fi

# --- Validate models.yaml ---
MODELS_YAML="${SCRIPT_DIR}/config/models.yaml"
if [ -f "${MODELS_YAML}" ]; then
    if python3 -c "import yaml; yaml.safe_load(open('${MODELS_YAML}'))" 2>/dev/null; then
        info "config/models.yaml is valid YAML"
    else
        error "config/models.yaml is not valid YAML"
        exit 1
    fi
else
    warn "config/models.yaml not found. Benchmarks will use whatever is in the config."
fi

info "Setup complete. Run './scripts/run_all.sh --fast' to benchmark."

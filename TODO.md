# TODO

## Goal
Build a self-contained local LLM benchmarking toolkit with performance, quality, and domain-specific benchmarks, runnable via a single command.

## Tasks

### 1. Project scaffolding
- [x] Create directory structure: `config/`, `scripts/`, `utils/`, `results/`
- [x] Create `requirements.txt` with `lm-eval>=0.4.0`, `bigcode-eval>=0.3.0`, `pandas>=2.0.0`, `pyyaml>=6.0`, `rich>=13.0.0`

### 2. Configuration & documentation
- [x] Create `config/models.yaml` with template entries for qwen3.6-35b and qwen2.5-coder-7b
- [x] Create `README.md` with quick-start, model registry instructions, benchmark descriptions, troubleshooting, and MIT license

### 3. Setup & Makefile
- [x] Create `setup.sh` — checks python3/pip/curl/jq, installs deps, creates `results/`, verifies llama.cpp tools, exits with clear error if missing
- [x] Create `Makefile` with targets: `setup`, `perf`, `quality`, `domain`, `all`, `clean`

### 4. Utility script
- [x] Create `utils/metrics.py` — reads CSV/JSON from `results/`, prints formatted table with bottleneck highlighting, uses pandas + rich

### 5. Performance benchmark
- [x] Create `scripts/perf_bench.sh` — reads models.yaml, runs llama-bench with specified params, outputs CSV per model, prints summary table, manages server lifecycle

### 6. Quality benchmark
- [x] Create `scripts/quality_bench.sh` — starts llama-server if needed, runs lm-eval + bigcode-eval with --limit 50, outputs JSON/CSV, parses pass@1 scores, prints summary

### 7. Domain benchmark
- [x] Create `scripts/domain_bench.sh` — sends 5 curated prompts via curl, measures latency/tokens/tok/s, outputs CSV, supports --fast flag

### 8. Orchestrator
- [x] Create `scripts/run_all.sh` — accepts --model <name> and --fast, runs perf → quality → domain in sequence, calls metrics.py for summary, saves combined log to results/

### 9. Finalization
- [x] Make all shell scripts executable (chmod +x)
- [x] Verify all scripts use set -e, relative paths, and no hardcoded absolute paths

### 10. Testing
- [x] Create `tests/test_setup.sh` — verifies directory structure, file permissions, requirements.txt contents, models.yaml parseability
- [x] Create `tests/test_metrics.py` — tests metrics.py parsing logic with mock CSV/JSON data
- [x] Create `tests/test_scripts.sh` — validates each script has set -e, is executable, and run_all.sh orchestrator accepts --model and --fast flags
- [x] Run all tests and confirm they pass (76 passed, 0 failed)

## Notes
- Default runtime target: under 15 minutes on RTX 3090 / M-series
- llama-server and llama-bench installed by setup.sh (from llama.cpp)
- All output must be parseable (CSV/JSON) plus human-readable terminal summary
- Cache lm-eval results on re-runs of the same model

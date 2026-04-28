# 📦 TASK: Build a Fast Local LLM Benchmarking Repo

## 🎯 Objective

Create a minimal, self-contained GitHub-style repository that lets me quickly evaluate local LLMs on my hardware. The repo should include:

- Performance benchmarking (speed/tok/s)
- Quality benchmarking (coding, reasoning, domain tasks)
- Custom domain prompts (security/agent workflow)
- One-command execution with fast defaults
- Auto-generated summary metrics

## 📁 Target Repository Structure

```
llm-benchmarks/
├── README.md
├── requirements.txt
├── setup.sh
├── config/
│   └── models.yaml
├── scripts/
│   ├── perf_bench.sh
│   ├── quality_bench.sh
│   ├── domain_bench.sh
│   └── run_all.sh
├── utils/
│   └── metrics.py
└── results/          (auto-created on run)
```

---

## 📄 File Specifications

### 1. `setup.sh`

- Checks for `python3`, `pip`, `curl`, `jq`, `llama-bench`
- Creates `results/` directory
- Installs Python dependencies from `requirements.txt`
- Exits with clear error if `llama-bench` is missing

### 2. `requirements.txt`

```text
lm-eval>=0.4.0
bigcode-eval>=0.3.0
pandas>=2.0.0
pyyaml>=6.0
```

### 3. `config/models.yaml`

Simple model registry. Agent should generate this template:

```yaml
models:
  qwen3.6-35b:
    path: "~/models/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf"
    api_model: "qwen3.6-35b-a3b-gpu:latest"
    quant: "Q4_K_XL"
  qwen2.5-coder-7b:
    path: "~/models/Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf"
    api_model: "qwen2.5-coder-7b-gpu:latest"
    quant: "Q4_K_M"
```

### 4. `scripts/perf_bench.sh`

- Stops `llama-server` if running
- Runs `llama-bench` with `-p 512,4096 -n 128 -r 3 -fa 1 -ngl 99`
- Reads `config/models.yaml` to test each model
- Outputs CSV to `results/perf_<model>_<date>.csv`
- Prints summary table (pp512, pp4096, tg128 in tok/s)
- Restarts server automatically

### 5. `scripts/quality_bench.sh`

- Starts `llama-server` if not running
- Runs `lm-eval` and `bigcode-eval` with `--limit 50` (fast mode)
- Tasks: `humanevalplus,gsm8k,hellaswag`
- Outputs JSON/CSV to `results/quality_<model>_<date>.`
- Parses `pass@1` scores and prints quick summary
- Uses `http://127.0.0.1:8081/v1/chat/completions` as backend

### 6. `scripts/domain_bench.sh`

- Sends 5 curated prompts via `curl` to the API:
  1. Simple Python function
  2. Security-relevant code (FastMCP tool)
  3. Context window math
  4. Code vulnerability spotting
  5. OWASP/Agentic security mapping
- Measures latency, token count, tok/s
- Outputs CSV to `results/domain_<model>_<date>.csv`
- Includes `--fast` flag to skip verbose output

### 7. `scripts/run_all.sh`

- Orchestrator script
- Accepts optional `--model <name>` or `--fast`
- Runs perf → quality → domain in sequence
- Calls `utils/metrics.py` to print final summary table
- Saves combined log to `results/run_<date>.log`

### 8. `utils/metrics.py`

- Reads CSV/JSON from `results/`
- Prints formatted table: `Model | Q4/Q6 | pp512 | tg128 | humaneval | domain_score`
- Highlights bottlenecks (<50 tok/s, <60% pass@1)
- Uses `pandas` + `rich` for clean terminal output

### 9. `README.md`

- Quick start: `./setup.sh && ./scripts/run_all.sh --fast`
- How to add models to `config/models.yaml`
- What each benchmark measures
- Troubleshooting: VRAM limits, context scaling, quantization notes
- License: MIT

---

## 🚀 Execution Rules for Agent

1. Generate all files exactly as specified
2. Use relative paths from repo root
3. Default to `--limit 50` and 3 repeats for speed
4. Add `set -e` and basic error handling to all bash scripts
5. Make all scripts executable (`chmod +x`)
6. Include a `Makefile` or alias in README for common commands
7. Do not hardcode absolute paths; use `~` or env vars where possible
8. Output must be parseable (CSV/JSON) + human-readable terminal summary

---

## 📝 Agent Output Expectation

After execution, I should be able to:

```bash
cd llm-benchmarks
./setup.sh
./scripts/run_all.sh --fast
```

And get:

- ✅ Speed metrics (tok/s across contexts)
- ✅ Quality scores (humaneval, gsm8k, hellaswag)
- ✅ Domain performance (latency, accuracy proxy)
- ✅ One-line summary table
- ✅ Raw results in `results/` for later comparison

---

## 🔧 Notes for Implementation

- Use `jq` for JSON parsing in bash to avoid Python overhead
- Cache `lm-eval` results if re-running same model
- Add `--dry-run` flag to verify config without executing
- Keep total runtime under 15 mins on RTX 3090 / M-series
- All scripts should exit cleanly and restore server state

---

Paste this `task.md` directly into your Pi agent. It’s engineered for speed, minimal dependencies, and clear output. Let me know if you want the agent to also generate a `Makefile` or add automatic result visualization (e.g., `plot_results.py`).

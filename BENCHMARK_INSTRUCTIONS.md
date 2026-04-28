# Benchmark Instructions

## Prerequisites

1. **llama.cpp built** — `llama-bench` and `llama-server` should be available at one of:
   - `~/llama.cpp/build/bin/`
   - `~/git/llama.cpp/build/bin/`
   - `../llama.cpp/build/bin/` (relative to this repo)
   - `/usr/local/bin/`

2. **Model configured** — edit `config/models.yaml` to point to your model(s).

3. **Server running** — start with:
   ```bash
   codemode
   ```
   This starts the Qwen3.6-35B-A3B server on port 8081. Wait for ` READY` before running benchmarks.

---

## Running Benchmarks

All scripts auto-detect the llama.cpp binaries. Run from the repo root:

### 1. Domain Benchmark (speed by prompt type)
Measures tokens/sec across different prompt categories (coding, math, security, etc.).
```bash
./scripts/domain_bench.sh
```
- Reuses any existing server on port 8081 (safe to run alongside `codemode`)
- Results → `results/domain_<model>_<timestamp>.csv`

### 2. Performance Benchmark (hardware-level)
Measures GPU memory, power, context-length scaling using `llama-bench`.
```bash
./scripts/perf_bench.sh
```
- **Safe mode**: if a server is already running on port 8081, it reuses it without killing it
- If no server is running, starts one for the benchmark and cleans up after
- Results → `results/perf_<model>_<timestamp>.csv`

### 3. Quality Benchmark (intelligence/accuracy)
Runs standard benchmarks: HumanEval (coding), GSM8K (math), HellaSwag (reasoning).
```bash
./scripts/quality_bench.sh
```
- Reuses any existing server on port 8081 (safe to run alongside `codemode`)
- Results → `results/quality_<model>_<timestamp>.json`

### Run All
```bash
./scripts/run_all.sh
```

---

## Results

All results are saved in `results/` with timestamps in filenames.

| File Pattern | What it measures |
|---|---|
| `domain_*.csv` | Speed (tok/s) per prompt category |
| `perf_*.csv` | GPU hardware metrics (memory, power, context scaling) |
| `quality_*.json` | Accuracy scores on standard benchmarks |

---

## Safety Notes

- **`domain_bench.sh`** and **`quality_bench.sh`**: Safe to run while `codemode` server is running. They detect an existing server and reuse it.
- **`perf_bench.sh`**: Now safe too — no longer kills pre-existing servers. Previously it would kill anything on port 8081.
- The `cleanup` trap in all scripts only kills servers that the script itself started (tracked via `SERVER_PID`). Pre-existing servers are never touched.

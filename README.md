# Local LLM Benchmarking Toolkit

A minimal, self-contained toolkit for quickly evaluating local LLMs on your hardware.

## Quick Start

```bash
./setup.sh
./scripts/run_all.sh --fast
```

Or use the Makefile:

```bash
make setup
make all
make all FAST=1
```

## Directory Structure

```
llm-benchmarks/
├── README.md
├── requirements.txt
├── setup.sh
├── Makefile
├── config/
│   └── models.yaml          # Model registry
├── scripts/
│   ├── perf_bench.sh        # Performance (tokens/sec)
│   ├── quality_bench.sh     # Quality (code, reasoning)
│   ├── domain_bench.sh      # Domain-specific prompts
│   └── run_all.sh           # Orchestrator
├── utils/
│   └── metrics.py           # Summary table generator
├── tests/
│   ├── test_setup.sh
│   ├── test_metrics.py
│   └── test_scripts.sh
└── results/                 # Auto-created on run
```

## Adding Models

Edit `config/models.yaml` and add entries under `models:`:

```yaml
models:
  my-model:
    path: "~/models/my-model-Q4_K_M.gguf"
    api_model: "my-model:latest"
    quant: "Q4_K_M"
```

- **path**: local path to the GGUF file (tilde expansion supported)
- **api_model**: model identifier passed to llama-server
- **quant**: quantization format label

## Benchmarks

| Script | What it measures |
|---|---|
| `perf_bench.sh` | Performance: prompt processing (pp) at 512/4096 context, token generation (tg) at 128 tok/s. Uses `llama-bench`. |
| `quality_bench.sh` | Quality: HumanEval+ (code generation), GSM8K (math reasoning), HellaSwag (common-sense). Uses `lm-eval` and `bigcode-eval`. |
| `domain_bench.sh` | Domain: 5 curated prompts (Python coding, security tooling, context math, vulnerability spotting, OWASP mapping). Measures latency and token throughput. |

## Makefile Targets

| Target | Description |
|---|---|
| `make setup` | Install dependencies and verify tools |
| `make perf` | Run performance benchmark |
| `make quality` | Run quality benchmark |
| `make domain` | Run domain benchmark |
| `make all` | Run all benchmarks |
| `make clean` | Remove results directory |

## Usage

```bash
# Run everything (fast mode, default)
./scripts/run_all.sh --fast

# Run everything (full mode)
./scripts/run_all.sh

# Benchmark a single model
./scripts/run_all.sh --model qwen2.5-coder-7b

# Dry-run: verify config without executing
./scripts/run_all.sh --dry-run
```

## Troubleshooting

### VRAM limits
- If `llama-server` OOMs, try a lower quantization (Q3_K_M or Q2_K) or a smaller model.
- RTX 3090 (24 GB): comfortably handles 7B Q4, 13B Q4, 30-35B Q3.
- M-series (Apple Silicon): Metal backend (`-ngl 99`) offloads all layers to unified memory.

### Context scaling
- Prompt processing (pp) is measured at 512 and 4096 tokens.
- If 4096 context is too large for your GPU, the benchmark will still run but may be slower.

### Quantization notes
- Q4_K_M: good quality/size balance for most models.
- Q4_K_XL: slightly higher quality, larger file.
- Q3_K_M: smaller, more VRAM-friendly, slight quality loss.

### llama.cpp tools missing
If `setup.sh` reports missing `llama-bench` or `llama-server`, build from source:

```bash
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
make -j
```

Then ensure `llama-bench` and `llama-server` are in your PATH, or adjust `LLAMA_CPP_DIR` in `setup.sh`.

## License

MIT

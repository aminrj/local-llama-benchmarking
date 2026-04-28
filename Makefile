SHELL := /bin/bash
.PHONY: setup perf quality domain all clean

setup:
	@bash setup.sh

perf:
	@bash scripts/perf_bench.sh $(MODEL)

quality:
	@bash scripts/quality_bench.sh $(MODEL)

domain:
	@bash scripts/domain_bench.sh $(MODEL)

all:
	@if [ "$(FAST)" = "1" ]; then \
		bash scripts/run_all.sh --model $(MODEL) --fast; \
	else \
		bash scripts/run_all.sh --model $(MODEL); \
	fi

clean:
	@rm -rf results/
	@echo "Results directory removed."

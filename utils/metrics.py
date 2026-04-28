#!/usr/bin/env python3
"""Read benchmark results from results/ and print a formatted summary table."""

import csv
import glob
import json
import os
import sys
from pathlib import Path

try:
    from rich.console import Console
    from rich.table import Table
    HAS_RICH = True
except ImportError:
    HAS_RICH = False

console = Console() if HAS_RICH else None

RESULTS_DIR = Path(__file__).resolve().parent.parent / "results"


def read_perf_csv(filepath: str) -> dict | None:
    """Parse a perf_bench CSV and return summary metrics."""
    try:
        with open(filepath, newline="") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
        if not rows:
            return None
        # Assume columns include model, context, and metrics like pp_tps, tg_tps
        summary = {}
        for row in rows:
            context = row.get("context", row.get("ctx_size", ""))
            pp = row.get("pp_tps", row.get("prompt_processing", ""))
            tg = row.get("tg_tps", row.get("token_generation", ""))
            if context:
                summary[f"pp{context}"] = float(pp) if pp else None
                summary[f"tg{context}"] = float(tg) if tg else None
        if "pp512" not in summary and "pp4096" not in summary:
            # Fallback: try to extract from keys
            for k, v in summary.items():
                pass  # already populated
        return summary
    except Exception:
        return None


def read_quality_json(filepath: str) -> dict | None:
    """Parse a quality_bench JSON and return pass@1 scores."""
    try:
        with open(filepath) as f:
            data = json.load(f)
        scores = {}

        def extract_scores(obj):
            if isinstance(obj, dict):
                for k, v in obj.items():
                    if isinstance(v, (int, float)):
                        scores[k] = v
                    elif isinstance(v, dict):
                        extract_scores(v)

        # Handle nested lm-eval results
        if isinstance(data, dict):
            # Check for 'results' wrapper (common lm-eval output)
            if "results" in data and isinstance(data["results"], dict):
                extract_scores(data["results"])
            # Also check top-level
            extract_scores(data)
        return scores
    except Exception:
        return None


def read_domain_csv(filepath: str) -> dict | None:
    """Parse a domain_bench CSV and return average metrics."""
    try:
        with open(filepath, newline="") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
        if not rows:
            return None
        latencies = []
        toks = []
        for row in rows:
            lat = row.get("latency_s", row.get("latency", ""))
            tok = row.get("toks", row.get("tokens", ""))
            if lat:
                latencies.append(float(lat))
            if tok:
                toks.append(float(tok))
        return {
            "avg_latency_s": sum(latencies) / len(latencies) if latencies else None,
            "avg_tok_s": sum(toks) / len(toks) if toks else None,
        }
    except Exception:
        return None


def read_all_results() -> list[dict]:
    """Scan results/ and aggregate data per model."""
    models = {}
    for filepath in sorted(RESULTS_DIR.glob("*")):
        name = filepath.stem
        # Extract model name from filename patterns like perf_<model>_<date>
        parts = name.split("_")
        model_name = None
        if len(parts) >= 3:
            # Skip prefix (perf, quality, domain, run) and suffix (date)
            model_name = "_".join(parts[1:-1]) if len(parts) > 3 else parts[1]
        elif len(parts) == 2:
            model_name = parts[1]
        if not model_name:
            model_name = name

        if model_name not in models:
            models[model_name] = {}

        prefix = parts[0] if parts else ""
        if prefix == "perf" and filepath.suffix == ".csv":
            models[model_name]["perf"] = read_perf_csv(str(filepath))
        elif prefix == "quality" and filepath.suffix in (".json", ".csv"):
            models[model_name]["quality"] = read_quality_json(str(filepath))
        elif prefix == "domain" and filepath.suffix == ".csv":
            models[model_name]["domain"] = read_domain_csv(str(filepath))

    return [
        {
            "model": m,
            **data,
        }
        for m, data in models.items()
    ]


def print_summary(results: list[dict]):
    """Print a formatted summary table."""
    if not results:
        console.print("[yellow]No results found in results/[/yellow]") if HAS_RICH else print("No results found in results/")
        return

    table = Table(title="LLM Benchmark Summary")
    table.add_column("Model", style="cyan")
    table.add_column("Quant", style="dim")
    table.add_column("pp512", justify="right")
    table.add_column("pp4096", justify="right")
    table.add_column("tg128", justify="right")
    table.add_column("humaneval", justify="right")
    table.add_column("gsm8k", justify="right")
    table.add_column("domain_tok/s", justify="right")

    # Try to load model info from config
    config_path = Path(__file__).resolve().parent.parent / "config" / "models.yaml"
    model_quant = {}
    try:
        import yaml
        with open(config_path) as f:
            config = yaml.safe_load(f)
        for mname, minfo in config.get("models", {}).items():
            model_quant[mname] = minfo.get("quant", "unknown")
    except Exception:
        pass

    for r in results:
        model = r["model"]
        quant = model_quant.get(model, "?")

        perf = r.get("perf") or {}
        pp512 = perf.get("pp512")
        pp4096 = perf.get("pp4096")
        tg128 = perf.get("tg128") or perf.get("tg512")

        quality = r.get("quality") or {}
        humaneval = quality.get("humaneval", quality.get("humaneval+", quality.get("HumanEval", "")))
        gsm8k = quality.get("gsm8k", quality.get("GSM8K", ""))

        # Extract pass@1 scores
        if isinstance(humaneval, dict):
            for k, v in humaneval.items():
                if "pass" in k.lower():
                    humaneval = v
                    break
        if isinstance(gsm8k, dict):
            for k, v in gsm8k.items():
                if "acc" in k.lower() or "score" in k.lower():
                    gsm8k = v
                    break

        domain = r.get("domain") or {}
        domain_tok_s = domain.get("avg_tok_s")

        def fmt(v, threshold=None):
            if v is None:
                return "-"
            v = float(v)
            label = f"{v:.1f}"
            if threshold is not None and v < threshold:
                return f"[red]{label}[/red]" if HAS_RICH else f"RED:{label}"
            return label

        table.add_row(
            model,
            quant,
            fmt(pp512, 50),
            fmt(pp4096, 50),
            fmt(tg128, 50),
            fmt(humaneval, 60),
            fmt(gsm8k, 60),
            fmt(domain_tok_s, 50),
        )

    if HAS_RICH:
        console.print(table)
    else:
        table.print()


def main():
    results = read_all_results()
    print_summary(results)


if __name__ == "__main__":
    main()

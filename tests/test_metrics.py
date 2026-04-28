#!/usr/bin/env python3
"""Test metrics.py parsing logic with mock CSV/JSON data."""

import csv
import json
import os
import sys
import tempfile
from pathlib import Path

# Add parent dir to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "utils"))

from metrics import read_perf_csv, read_quality_json, read_domain_csv, read_all_results, print_summary


def test_read_perf_csv():
    """Test parsing performance benchmark CSV."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as f:
        writer = csv.writer(f)
        writer.writerow(["context", "pp_tps", "tg_tps", "batch_size"])
        writer.writerow(["512", "1234.5", "567.8", "1"])
        writer.writerow(["4096", "987.6", "432.1", "1"])
        f.flush()

        result = read_perf_csv(f.name)
        assert result is not None, "Should return non-None for valid CSV"
        assert result.get("pp512") == 1234.5, f"Expected pp512=1234.5, got {result.get('pp512')}"
        assert result.get("tg512") == 567.8, f"Expected tg512=567.8, got {result.get('tg512')}"
        assert result.get("pp4096") == 987.6, f"Expected pp4096=987.6, got {result.get('pp4096')}"
        assert result.get("tg4096") == 432.1, f"Expected tg4096=432.1, got {result.get('tg4096')}"

    os.unlink(f.name)
    print("  ✓ test_read_perf_csv")


def test_read_perf_csv_empty():
    """Test parsing empty CSV."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as f:
        f.write("")
        f.flush()

        result = read_perf_csv(f.name)
        assert result is None, "Should return None for empty CSV"

    os.unlink(f.name)
    print("  ✓ test_read_perf_csv_empty")


def test_read_quality_json():
    """Test parsing quality benchmark JSON."""
    data = {
        "results": {
            "humaneval": {
                "exact": 0.75,
                "match": 0.72
            },
            "gsm8k": {
                "exact": 0.68,
                "match": 0.65
            },
            "hellaswag": {
                "acc,all": 0.82
            }
        }
    }

    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(data, f)
        f.flush()

        result = read_quality_json(f.name)
        assert result is not None, "Should return non-None for valid JSON"
        # Should have extracted at least some scores
        assert len(result) > 0, "Should have extracted some scores"

    os.unlink(f.name)
    print("  ✓ test_read_quality_json")


def test_read_quality_json_empty():
    """Test parsing empty JSON."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump({}, f)
        f.flush()

        result = read_quality_json(f.name)
        assert result is not None, "Should return non-None (empty dict) for empty JSON"
        assert len(result) == 0, "Should return empty dict"

    os.unlink(f.name)
    print("  ✓ test_read_quality_json_empty")


def test_read_domain_csv():
    """Test parsing domain benchmark CSV."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as f:
        writer = csv.writer(f)
        writer.writerow(["prompt", "latency_s", "tokens"])
        writer.writerow(["simple_python", "1.2", "150"])
        writer.writerow(["security_tool", "3.5", "420"])
        writer.writerow(["context_math", "0.8", "80"])
        f.flush()

        result = read_domain_csv(f.name)
        assert result is not None, "Should return non-None for valid CSV"
        assert abs(result["avg_latency_s"] - 1.833) < 0.01, f"Expected avg_latency ~1.833, got {result['avg_latency_s']}"
        assert abs(result["avg_tok_s"] - 216.67) < 0.1, f"Expected avg_tok_s ~216.67, got {result['avg_tok_s']}"

    os.unlink(f.name)
    print("  ✓ test_read_domain_csv")


def test_read_domain_csv_empty():
    """Test parsing empty domain CSV."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as f:
        f.write("")
        f.flush()

        result = read_domain_csv(f.name)
        assert result is None, "Should return None for empty CSV"

    os.unlink(f.name)
    print("  ✓ test_read_domain_csv_empty")


def test_read_all_results():
    """Test aggregating results from multiple files."""
    with tempfile.TemporaryDirectory() as tmpdir:
        # Create mock results
        perf_csv = Path(tmpdir) / "perf_qwen2.5-coder-7b_20240101.csv"
        with open(perf_csv, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(["context", "pp_tps", "tg_tps"])
            writer.writerow(["512", "1000.0", "500.0"])

        quality_json = Path(tmpdir) / "quality_qwen2.5-coder-7b_20240101.json"
        with open(quality_json, 'w') as f:
            json.dump({"results": {"humaneval": {"exact": 0.75}}}, f)

        domain_csv = Path(tmpdir) / "domain_qwen2.5-coder-7b_20240101.csv"
        with open(domain_csv, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(["prompt", "latency_s", "tokens"])
            writer.writerow(["simple_python", "1.0", "100"])

        # Temporarily override RESULTS_DIR
        import metrics
        original_dir = metrics.RESULTS_DIR
        metrics.RESULTS_DIR = Path(tmpdir)

        try:
            results = read_all_results()
            assert len(results) == 1, f"Expected 1 result, got {len(results)}"
            assert results[0]["model"] == "qwen2.5-coder-7b"
            assert results[0].get("perf") is not None
            assert results[0].get("quality") is not None
            assert results[0].get("domain") is not None
        finally:
            metrics.RESULTS_DIR = original_dir

    print("  ✓ test_read_all_results")


def test_print_summary_empty():
    """Test summary printing with no results."""
    import metrics
    original_dir = metrics.RESULTS_DIR
    with tempfile.TemporaryDirectory() as tmpdir:
        metrics.RESULTS_DIR = Path(tmpdir)
        try:
            # Should not crash
            print_summary([])
        except Exception as e:
            assert False, f"print_summary([]) should not raise: {e}"
        finally:
            metrics.RESULTS_DIR = original_dir
    print("  ✓ test_print_summary_empty")


def run_all_tests():
    """Run all tests and report results."""
    tests = [
        test_read_perf_csv,
        test_read_perf_csv_empty,
        test_read_quality_json,
        test_read_quality_json_empty,
        test_read_domain_csv,
        test_read_domain_csv_empty,
        test_read_all_results,
        test_print_summary_empty,
    ]

    passed = 0
    failed = 0

    for test in tests:
        try:
            test()
            passed += 1
        except Exception as e:
            print(f"  ✗ {test.__name__}: {e}")
            failed += 1

    print("")
    print(f"==============================")
    print(f"Results: {passed} passed, {failed} failed")
    print(f"==============================")

    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    run_all_tests()

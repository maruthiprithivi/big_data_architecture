"""Portable E2E: run inside the app container, including real local inference."""
import argparse
import json
import os
from pathlib import Path
import time
import urllib.error
import urllib.request

from app import CLICKHOUSE, dashboard, query_for, validate_plan

BASE = os.environ.get("LAB_URL", "http://127.0.0.1:8090")


def call(path, payload=None):
    request = urllib.request.Request(BASE + path, data=None if payload is None else json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=320) as response:
        return json.load(response)


def self_checks():
    valid = {"action": "query", "metric": "starts", "group_by": "title", "threshold_seconds": 1200, "dashboard_title": "Test"}
    for key, value in (("metric", "starts; DROP TABLE sessions"), ("group_by", "url('https://example.com')"), ("threshold_seconds", True), ("threshold_seconds", 999), ("dashboard_title", "")):
        try:
            validate_plan({**valid, key: value})
        except (ValueError, TypeError):
            pass
        else:
            raise AssertionError(f"Unsafe plan accepted: {key}")
    assert "ORDER BY starts DESC" in query_for(valid)
    artifact = dashboard({**valid, "dashboard_title": "<script>alert(1)</script>"}, [{"segment": "<img onerror=alert(1)>", "starts": 1, "engaged_sessions": 0, "engagement_pct": 0}], "SELECT '<script>'", {key: "<script>" for key in ("observation", "limitation", "next_test")})
    assert "<script>" not in artifact and "<img " not in artifact and "&lt;script&gt;" in artifact
    rate_artifact = dashboard({**valid, "metric": "engagement_pct"}, [{"segment": "Example", "starts": 100, "engaged_sessions": 90, "engagement_pct": 90}], "SELECT 1", {key: "Test" for key in ("observation", "limitation", "next_test")})
    assert 'width:90.000%' in rate_artifact


def wait_ready():
    deadline = time.monotonic() + 600
    while True:
        try:
            health = call("/health")
            if health["ready"]:
                print("PASS readiness: local model and one-million-session ClickHouse table ready.", flush=True)
                return health
        except (urllib.error.URLError, TimeoutError):
            pass
        if time.monotonic() > deadline:
            raise RuntimeError("Services did not become ready in 10 minutes. Check docker compose logs --tail 30.")
        time.sleep(2)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ready", action="store_true", help="Wait for model/database readiness without running investigations.")
    arguments = parser.parse_args()
    health = wait_ready()
    if arguments.ready:
        raise SystemExit(0)
    self_checks()
    try:
        urllib.request.urlopen(urllib.request.Request(CLICKHOUSE + "/?user=lab_reader", data=b"DROP TABLE campusstream.sessions"))
    except urllib.error.HTTPError as error:
        assert b"ACCESS_DENIED" in error.read(), "Database did not explicitly deny the write"
    else:
        raise AssertionError("Reader account accepted a destructive query")
    receipt = {"ready": health, "tests": []}
    cases = [
        ("Compare starts by title and build a dashboard.", "starts", "title", 1200, "The Matrix", 500000),
        ("Rank titles by engaged sessions using a 20-minute threshold. Build a dashboard.", "engaged_sessions", "title", 1200, "Apollo 13", 240000),
        ("Which title has the highest engagement rate? Use a 20-minute threshold and build a decision dashboard.", "engagement_pct", "title", 1200, "Cloud Atlas", 90),
        ("Compare engagement rate by device, using a 40-minute threshold. Build a dashboard.", "engagement_pct", "device", 2400, "mobile", 0),
    ]
    for prompt, metric, group, threshold, winner, value in cases:
        result = call("/api/run", {"prompt": prompt})
        plan = result["plan"]
        assert (plan["metric"], plan["group_by"], plan["threshold_seconds"]) == (metric, group, threshold), plan
        assert result["rows"][0]["segment"] == winner, result["rows"]
        assert result["rows"][0][metric] == value, result["rows"]
        assert winner in result["note"]["observation"] and str(value) in result["note"]["observation"].replace(",", "")
        assert sum(row["starts"] for row in result["rows"]) == 1000000
        assert all(row["engaged_sessions"] <= row["starts"] for row in result["rows"])
        assert result["sql"] in result["trace"][2]["detail"]["sql"]
        assert "Executed SQL" in result["dashboard_html"] and winner in result["dashboard_html"]
        assert "<script" not in result["dashboard_html"]
        receipt["tests"].append({"prompt": prompt, "plan": plan, "winner": winner, "value": value, "seconds": result["elapsed_seconds"], "note": result["note"]})
        print(f"PASS {metric}/{group}/{threshold}: {winner}={value} ({result['elapsed_seconds']}s)", flush=True)
    for payload in ({"prompt": ""}, {"prompt": 42}, {"prompt": "x" * 1201}):
        try:
            call("/api/run", payload)
        except urllib.error.HTTPError as error:
            assert error.code == 400
        else:
            raise AssertionError("Invalid prompt accepted")
    request = urllib.request.Request(BASE + "/api/run", data=b'{"prompt":"test"}', headers={"Content-Type": "application/json", "Origin": "https://example.com"})
    try:
        urllib.request.urlopen(request)
    except urllib.error.HTTPError as error:
        assert error.code == 403
    else:
        raise AssertionError("Cross-origin request accepted")
    receipt["checks"] = ["plan validation", "prompt validation", "read-only database", "cross-origin denial", "escaped HTML", "actual local inference", "actual ClickHouse"]
    Path("/tmp/campusstream-e2e.json").write_text(json.dumps(receipt, indent=2))
    Path("/tmp/campusstream-dashboard.html").write_text(result["dashboard_html"])
    print("PASS validation, database write denial, cross-origin denial, escaped artifact, real model plans, real ClickHouse, dashboard export. Receipt: /tmp/campusstream-e2e.json", flush=True)

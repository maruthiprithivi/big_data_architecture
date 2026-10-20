"""The visible pipeline must follow completed tool boundaries, including help/failure."""
import sys
from pathlib import Path
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app

class ProgressTests(unittest.TestCase):
    def test_progress_and_evidence(self):
        plan = dict(action="query", metric="starts", group_by="title", threshold_seconds=1200, dashboard_title="Test")
        rows = [dict(segment="Example", starts=10, engaged_sessions=5, engagement_pct=50)]
        events = []
        def query(sql):
            self.assertEqual(events, ["plan", "query"])
            return {"data": rows}
        with patch.object(app, "infer", side_effect=[plan, dict(limitation="Synthetic", next_test="Experiment")]), patch.object(app, "query_clickhouse", side_effect=query):
            result = app.run_agent("Compare starts", events.append)
        self.assertEqual(events, ["plan", "query", "interpret", "build"])
        self.assertEqual(result["rows"], rows)
        self.assertIn("Executed SQL", result["dashboard_html"])

    def test_help_never_claims_a_query(self):
        plan = dict(action="help", metric="starts", group_by="title", threshold_seconds=1200, dashboard_title="Help")
        events = []
        with patch.object(app, "infer", return_value=plan), patch.object(app, "query_clickhouse") as query:
            self.assertIn("help", app.run_agent("Delete data", events.append))
        query.assert_not_called()
        self.assertEqual(events, ["plan"])

if __name__ == "__main__":
    unittest.main()

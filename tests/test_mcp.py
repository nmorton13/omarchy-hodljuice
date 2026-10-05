import contextlib
import http.server
import io
import json
import os
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

from test_cli import MODULE, ROOT


class McpDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.environment = mock.patch.dict(os.environ, {
            "XDG_RUNTIME_DIR": self.temp.name,
            "XDG_STATE_HOME": self.temp.name,
        })
        self.environment.start()
        self.requests = []
        self.tool_result = {
            "structuredContent": {
                "id": "episode-id",
                "title": "Why Bitcoin Matters",
                "podcast": "Test Podcast",
                "published": "2026-10-03",
                "audio_url": "https://media.example.test/episode.mp3",
                "play_url": "https://hodljuice.app/e/episode-id",
                "artwork_url": "/podcast-artwork/example",
            },
            "isError": False,
        }
        self.expire_session = False
        self.tool_status = 200
        self.raw_body = None
        self.declared_length = None
        self.redirect = None
        self.html = (ROOT / "tests/fixtures/episode.html").read_text()
        owner = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                message = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                owner.requests.append((message, dict(self.headers)))
                method = message["method"]
                if method == "initialize":
                    self.reply(200, {"jsonrpc": "2.0", "id": message["id"], "result": {
                        "protocolVersion": "2025-03-26", "capabilities": {"tools": {}},
                    }}, session="test-session")
                elif method == "notifications/initialized":
                    self.reply(202, None)
                elif owner.expire_session:
                    owner.expire_session = False
                    self.reply(404, {"error": "expired session"})
                elif owner.redirect:
                    self.send_response(307)
                    self.send_header("Location", owner.redirect)
                    self.end_headers()
                else:
                    self.reply(owner.tool_status, {
                        "jsonrpc": "2.0", "id": message["id"], "result": owner.tool_result,
                    }, raw=owner.raw_body)

            def do_GET(self):
                owner.requests.append((self.path, dict(self.headers)))
                self.send_response(200)
                self.end_headers()
                self.wfile.write(owner.html.encode())

            def reply(self, status, value, session=None, raw=None):
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                if raw is not None and owner.declared_length is not None:
                    self.send_header("Content-Length", str(owner.declared_length))
                if session:
                    self.send_header("Mcp-Session-Id", session)
                self.end_headers()
                body = raw if raw is not None else json.dumps(value).encode() if value is not None else b""
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        self.server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.origin = mock.patch.object(MODULE, "BASE_URL", f"http://127.0.0.1:{self.server.server_port}")
        self.origin.start()

    def tearDown(self):
        self.origin.stop()
        self.server.shutdown()
        self.thread.join(timeout=5)
        self.server.server_close()
        self.environment.stop()
        self.temp.cleanup()

    def discover(self, *args):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(MODULE.main(["discover", "--json", *args]), 0)
        return json.loads(output.getvalue())

    def methods(self):
        return [message["method"] if isinstance(message, dict) else "GET" for message, _ in self.requests]

    def test_mcp_metadata_matches_existing_cli_and_history_contract(self):
        value = self.discover()
        self.assertEqual(value, {
            "guid": "episode-id", "title": "Why Bitcoin Matters", "podcast": "Test Podcast",
            "artist": "", "publishedAt": "2026-10-03",
            "audioUrl": "https://media.example.test/episode.mp3", "podcastUrl": "",
            "sourceUrl": "https://hodljuice.app/e/episode-id",
            "artworkUrl": MODULE.BASE_URL + "/podcast-artwork/example",
        })
        history = MODULE.read_json_file(Path(self.temp.name) / "hodljuice/history.json", [])
        self.assertEqual(history[0]["audioUrl"], value["audioUrl"])
        self.assertEqual(self.methods(), ["initialize", "notifications/initialized", "tools/call"])
        version = json.loads((ROOT / "manifest.json").read_text())["version"]
        self.assertEqual(self.requests[0][0]["params"]["clientInfo"]["version"], version)
        message, headers = self.requests[-1]
        self.assertEqual(message["params"], {"name": "random_episode", "arguments": {}})
        self.assertEqual(headers["Mcp-Session-Id"], "test-session")
        self.assertEqual(headers["Mcp-Protocol-Version"], "2025-03-26")

    def test_recent_and_year_filters_are_sent_to_mcp(self):
        for range_value, arguments in [("7", {"days": 7}), ("30", {"days": 30}), ("2025", {"year": 2025})]:
            self.discover("--range", range_value)
            self.assertEqual(self.requests[-1][0]["params"]["arguments"], arguments)

    def test_session_is_reused_across_cli_invocations(self):
        self.discover()
        previous_ids = {message["id"] for message, _ in self.requests if "id" in message}
        self.requests.clear()
        self.discover()
        self.assertEqual(self.methods(), ["tools/call"])
        self.assertNotIn(self.requests[0][0]["id"], previous_ids)
        self.assertEqual((Path(self.temp.name) / "hodljuice/mcp-session.json").stat().st_mode & 0o777, 0o600)

    def test_expired_session_is_reinitialized_once(self):
        self.discover()
        self.requests.clear()
        self.expire_session = True
        value = self.discover()
        self.assertEqual(value["guid"], "episode-id")
        self.assertEqual(self.methods(), ["tools/call", "initialize", "notifications/initialized", "tools/call"])

    def test_json_text_result_is_supported(self):
        self.tool_result = {"content": [{"type": "text", "text": json.dumps(self.tool_result["structuredContent"])}]}
        self.assertEqual(self.discover()["guid"], "episode-id")

    def test_tool_error_falls_back_to_html_with_same_filter(self):
        self.tool_result = {"isError": True, "content": [{"type": "text", "text": "Server error"}]}
        value = self.discover("--range", "30")
        self.assertEqual(value["guid"], "episode-21")
        self.assertEqual(self.requests[-1][0], "/?year=30")
        self.assertEqual(self.methods(), ["initialize", "notifications/initialized", "tools/call", "GET"])

    def test_transport_failure_falls_back_to_html(self):
        self.tool_status = 503
        self.assertEqual(self.discover()["guid"], "episode-21")
        self.assertEqual(self.methods()[-1], "GET")

    def test_invalid_json_falls_back_to_html(self):
        self.raw_body = b"not JSON"
        self.assertEqual(self.discover()["guid"], "episode-21")

    def test_truncated_mcp_response_falls_back_to_html(self):
        self.raw_body = b"{"
        self.declared_length = 100
        self.assertEqual(self.discover()["guid"], "episode-21")

    def test_both_sources_failing_reports_error_without_recording_history(self):
        self.tool_result = {"isError": True}
        self.html = "<html>No episode</html>"
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            self.assertEqual(MODULE.main(["discover", "--json"]), 1)
        self.assertEqual(output.getvalue(), "")
        self.assertIn("no valid audio URL", errors.getvalue())
        self.assertFalse((Path(self.temp.name) / "hodljuice/history.json").exists())

    def test_oversized_mcp_response_falls_back_to_html(self):
        self.raw_body = b"x" * (MODULE.MAX_RESPONSE_BYTES + 1)
        self.assertEqual(self.discover()["guid"], "episode-21")

    def test_invalid_metadata_falls_back_to_html(self):
        original = dict(self.tool_result["structuredContent"])
        for bad in [{"audio_url": "file:///tmp/audio"}, {"audio_url": "https://[invalid"}, {"title": []}, {"podcast": None}]:
            with self.subTest(bad=bad):
                self.tool_result["structuredContent"] = {**original, **bad}
                self.requests.clear()
                self.assertEqual(self.discover()["guid"], "episode-21")
                self.assertIn("tools/call", self.methods())

    def test_invalid_rpc_envelopes_fall_back_to_html(self):
        for envelope in [[], {"jsonrpc": "2.0", "id": 2, "error": {"code": -32603}},
                         {"jsonrpc": "2.0", "id": 99, "result": self.tool_result}]:
            with self.subTest(envelope=envelope):
                self.raw_body = json.dumps(envelope).encode()
                self.assertEqual(self.discover()["guid"], "episode-21")

    def test_mcp_timeout_budget_falls_back_to_html(self):
        with mock.patch.object(MODULE, "MCP_TIMEOUT", 0):
            self.assertEqual(self.discover("--range", "7")["guid"], "episode-21")
        self.assertEqual(self.requests[-1][0], "/?year=7")

    def test_corrupt_session_cache_is_not_sent_as_a_header(self):
        cache = MODULE.runtime_dir() / "mcp-session.json"
        for bad in [[], {"session": ["wrong type"]}, {"session": "invalid\r\nheader"}]:
            with self.subTest(bad=bad):
                MODULE.atomic_json_write(cache, bad)
                self.requests.clear()
                self.assertEqual(self.discover()["guid"], "episode-id")
                self.assertEqual(self.methods()[0], "initialize")

    def test_mcp_redirect_to_another_origin_is_not_followed(self):
        self.redirect = "https://evil.example/mcp"
        self.assertEqual(self.discover()["guid"], "episode-21")
        self.assertEqual(self.methods()[-1], "GET")

    def test_category_and_specific_date_stay_on_html(self):
        self.discover("--band", "money")
        self.assertEqual(self.requests[-1][0], "/money")
        self.discover("--date", "2026-09-01")
        self.assertEqual(self.requests[-1][0], "/custom_date_filter?date=2026-09-01")
        self.assertEqual(self.methods(), ["GET", "GET"])

    def search(self, query="Lyn Alden", *args):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(MODULE.main(["search", "--query", query, "--json", *args]), 0)
        return json.loads(output.getvalue())

    def search_result(self):
        episode = dict(self.tool_result["structuredContent"])
        self.tool_result = {"structuredContent": {"count": 1, "episodes": [episode]}}

    def test_search_returns_playable_results_without_changing_local_history(self):
        self.search_result()
        values = self.search(" Lyn Alden ", "--range", "7", "--limit", "10")
        self.assertEqual(values[0]["title"], "Why Bitcoin Matters")
        self.assertEqual(values[0]["audioUrl"], "https://media.example.test/episode.mp3")
        self.assertEqual(self.requests[-1][0]["params"], {
            "name": "search_episodes", "arguments": {"query": "Lyn Alden", "days": 7, "limit": 10},
        })
        self.assertFalse((Path(self.temp.name) / "hodljuice/history.json").exists())
        self.assertFalse((Path(self.temp.name) / "hodljuice/current.json").exists())

    def test_search_all_time_omits_days_and_reuses_discovery_session(self):
        self.discover()
        self.requests.clear()
        self.search_result()
        self.search()
        self.assertEqual(self.methods(), ["tools/call"])
        self.assertEqual(self.requests[-1][0]["params"]["arguments"], {"query": "Lyn Alden", "limit": 25})

    def test_search_specific_year_sends_year_instead_of_days(self):
        self.search_result()
        self.search("bitcoin", "--range", "2025")
        self.assertEqual(self.requests[-1][0]["params"]["arguments"], {
            "query": "bitcoin", "year": 2025, "limit": 25,
        })

    def test_search_rejects_invalid_years_without_network_access(self):
        for range_value in ["2010", "2101", "20x5", "2025.0", "٢٠٢٥"]:
            with self.subTest(range_value=range_value):
                output, errors = io.StringIO(), io.StringIO()
                with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                    self.assertEqual(MODULE.main(["search", "--query", "bitcoin", "--range", range_value, "--json"]), 1)
                self.assertEqual(output.getvalue(), "")
                self.assertTrue(errors.getvalue().strip())
                self.assertEqual(self.requests, [])

    def test_year_discovery_fallback_preserves_year(self):
        self.tool_result = {"isError": True}
        self.assertEqual(self.discover("--range", "2025")["guid"], "episode-21")
        self.assertEqual(self.requests[-1][0], "/?year=2025")

    def test_search_no_matches_is_an_empty_success(self):
        self.tool_result = {"structuredContent": {"count": 0, "episodes": []}}
        self.assertEqual(self.search(), [])

    def test_search_skips_unplayable_results_and_caps_output(self):
        good = dict(self.tool_result["structuredContent"])
        self.tool_result = {"structuredContent": {"episodes": [
            {**good, "audio_url": "file:///tmp/private"}, None, {**good, "title": ""}, good, good,
        ]}}
        values = self.search("bitcoin", "--limit", "1")
        self.assertEqual(len(values), 1)
        self.assertEqual(values[0]["title"], "Why Bitcoin Matters")

    def test_search_invalid_query_does_not_send_a_request(self):
        for query in [" ", "x" * 201]:
            with self.subTest(query=query):
                output, errors = io.StringIO(), io.StringIO()
                with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                    self.assertEqual(MODULE.main(["search", "--query", query, "--json"]), 1)
                self.assertEqual(output.getvalue(), "")
                self.assertIn("Search", errors.getvalue())
                self.assertEqual(self.requests, [])

    def test_search_errors_do_not_fall_back_to_random_discovery(self):
        for failure in ["tool", "http", "metadata"]:
            with self.subTest(failure=failure):
                self.tool_result = {"isError": True} if failure == "tool" else {"structuredContent": {"episodes": "bad"}}
                self.tool_status = 503 if failure == "http" else 200
                output, errors = io.StringIO(), io.StringIO()
                with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                    self.assertEqual(MODULE.main(["search", "--query", "bitcoin", "--json"]), 1)
                self.assertEqual(output.getvalue(), "")
                self.assertTrue(errors.getvalue().strip())
                self.assertNotIn("GET", self.methods())

    def test_url_only_does_not_contact_mcp(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(MODULE.main(["discover", "--range", "7", "--url-only"]), 0)
        self.assertEqual(output.getvalue().strip(), MODULE.BASE_URL + "/?year=7")
        self.assertEqual(self.requests, [])


if __name__ == "__main__":
    unittest.main()

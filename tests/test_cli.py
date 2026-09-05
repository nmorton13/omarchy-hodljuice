import contextlib
import importlib.machinery
import importlib.util
import io
import json
import math
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
LOADER = importlib.machinery.SourceFileLoader("hodljuice_cli", str(ROOT / "bin" / "hodljuice"))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[LOADER.name] = MODULE
LOADER.exec_module(MODULE)


class DiscoveryUrlTests(unittest.TestCase):
    def test_all_any_uses_empty_year_filter(self):
        self.assertEqual(
            MODULE.build_discovery_url("all", "any"),
            "https://hodljuice.app/?year=",
        )

    def test_all_with_recent_range(self):
        self.assertEqual(
            MODULE.build_discovery_url("all", "30"),
            "https://hodljuice.app/?year=30",
        )

    def test_category(self):
        self.assertEqual(
            MODULE.build_discovery_url("money", "any"),
            "https://hodljuice.app/money",
        )

    def test_person_is_encoded(self):
        self.assertEqual(
            MODULE.build_discovery_url("people", "any", "Lyn Alden"),
            "https://hodljuice.app/person/Lyn_Alden",
        )

    def test_people_requires_person(self):
        with self.assertRaises(MODULE.HodlJuiceError):
            MODULE.build_discovery_url("people")

    def test_category_and_range_are_not_silently_combined(self):
        with self.assertRaises(MODULE.HodlJuiceError):
            MODULE.build_discovery_url("money", "30")

    def test_custom_date_uses_date_route(self):
        self.assertEqual(
            MODULE.build_discovery_url("all", date="2026-08-29"),
            "https://hodljuice.app/custom_date_filter?date=2026-08-29",
        )


class PersistenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.previous = os.environ.get("XDG_STATE_HOME")
        os.environ["XDG_STATE_HOME"] = self.temp.name

    def tearDown(self):
        if self.previous is None:
            os.environ.pop("XDG_STATE_HOME", None)
        else:
            os.environ["XDG_STATE_HOME"] = self.previous
        self.temp.cleanup()

    def episode(self, title="Episode"):
        return MODULE.Episode("guid", "Podcast", "Artist", title, "https://media.example/e.mp3", "", "", "2026-01-01", "https://hodljuice.app/")

    def test_history_deduplicates_by_audio_url(self):
        MODULE.record_history(self.episode("First"))
        MODULE.record_history(self.episode("Updated"))
        values = MODULE.read_json_file(MODULE.xdg_state_dir() / "history.json", [])
        self.assertEqual(len(values), 1)
        self.assertEqual(values[0]["title"], "Updated")

    def test_save_and_remove(self):
        value = MODULE.episode_record(self.episode())
        MODULE.save_episode(value)
        saved = MODULE.read_json_file(MODULE.xdg_state_dir() / "saved.json", [])
        self.assertEqual(saved[0]["title"], "Episode")
        MODULE.remove_saved_episode(value["audioUrl"])
        self.assertEqual(MODULE.read_json_file(MODULE.xdg_state_dir() / "saved.json", []), [])

    def test_resume_position_round_trip_and_near_start_clear(self):
        url = "https://media.example/e.mp3"
        MODULE.remember_position(url, 123.4567)
        self.assertEqual(MODULE.resume_position(url), 123.457)
        MODULE.remember_position(url, 3)
        self.assertEqual(MODULE.resume_position(url), 0)

    def test_positions_prune_entries_older_than_max_age(self):
        url = "https://media.example/e.mp3"
        old_url = "https://media.example/old.mp3"
        now = int(time.time())
        MODULE.remember_position(url, 100)
        path = MODULE.xdg_state_dir() / "positions.json"
        values = MODULE.read_json_file(path, {})
        values[old_url] = {"seconds": 50, "updatedAt": now - MODULE.POSITIONS_MAX_AGE_SECONDS - 1}
        MODULE.atomic_json_write(path, values)
        MODULE.remember_position(url, 200)
        values = MODULE.read_json_file(path, {})
        self.assertNotIn(old_url, values)
        self.assertIn(url, values)

    def test_positions_cap_total_entries(self):
        now = int(time.time())
        path = MODULE.xdg_state_dir() / "positions.json"
        values = {}
        for index in range(MODULE.POSITIONS_LIMIT + 50):
            values[f"https://media.example/e{index}.mp3"] = {"seconds": 10 + index, "updatedAt": now - index}
        MODULE.atomic_json_write(path, values)
        MODULE.remember_position("https://media.example/new.mp3", 100)
        values = MODULE.read_json_file(path, {})
        self.assertLessEqual(len(values), MODULE.POSITIONS_LIMIT)
        self.assertIn("https://media.example/new.mp3", values)

    def test_state_files_are_private(self):
        path = MODULE.xdg_state_dir() / "private.json"
        MODULE.atomic_json_write(path, {"ok": True})
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(MODULE.read_json_file(path, {}), {"ok": True})

    def test_corrupt_timestamps_are_tolerated(self):
        value = MODULE.episode_record({"savedAt": "bad", "discoveredAt": object()})
        self.assertEqual(value["savedAt"], 0)
        self.assertEqual(value["discoveredAt"], 0)


class PlaybackTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.previous = os.environ.get("XDG_STATE_HOME")
        os.environ["XDG_STATE_HOME"] = self.temp.name

    def tearDown(self):
        if self.previous is None:
            os.environ.pop("XDG_STATE_HOME", None)
        else:
            os.environ["XDG_STATE_HOME"] = self.previous
        self.temp.cleanup()

    def test_reused_mpv_refreshes_title_before_loading(self):
        socket_path = Path(self.temp.name) / "mpv.sock"
        socket_path.touch()
        commands = []

        with mock.patch.object(MODULE, "public_playback_url", side_effect=lambda value: value), mock.patch.object(
            MODULE, "mpv_socket_path", return_value=socket_path
        ), mock.patch.object(MODULE, "mpv_command", side_effect=lambda command: commands.append(command)), mock.patch.object(
            MODULE, "wait_for_media_ready"
        ) as ready:
            MODULE.start_playback("https://media.example/next.mp3", "Next episode", "Podcast", 12)

        ready.assert_called_once_with("https://media.example/next.mp3", 12)

        self.assertEqual(commands[:2], [
            ["set_property", "force-media-title", "Next episode"],
            ["loadfile", "https://media.example/next.mp3", "replace"],
        ])

    def test_public_playback_url_accepts_only_globally_routable_addresses(self):
        address = (MODULE.socket.AF_INET, MODULE.socket.SOCK_STREAM, 6, "", ("93.184.216.34", 443))
        with mock.patch.object(MODULE.socket, "getaddrinfo", return_value=[address]):
            self.assertEqual(
                MODULE.public_playback_url("https://media.example/episode.mp3"),
                "https://media.example/episode.mp3",
            )

    def test_public_playback_url_rejects_private_and_link_local_addresses(self):
        for host in ("127.0.0.1", "192.168.1.10", "169.254.169.254", "::1"):
            family = MODULE.socket.AF_INET6 if ":" in host else MODULE.socket.AF_INET
            address = (family, MODULE.socket.SOCK_STREAM, 6, "", (host, 443))
            with self.subTest(host=host), mock.patch.object(MODULE.socket, "getaddrinfo", return_value=[address]):
                with self.assertRaises(MODULE.HodlJuiceError):
                    MODULE.public_playback_url(f"https://[{host}]/episode.mp3" if ":" in host else f"https://{host}/episode.mp3")

    def test_shutdown_sends_quit_and_waits_for_socket_removal(self):
        socket_path = Path(self.temp.name) / "mpv.sock"
        socket_path.touch()

        client = mock.MagicMock()
        client.__enter__.return_value = client
        client.sendall.side_effect = lambda payload: socket_path.unlink()
        with mock.patch.object(MODULE, "mpv_socket_path", return_value=socket_path), mock.patch.object(
            MODULE.socket, "socket", return_value=client
        ):
            MODULE.shutdown_playback()

        command = json.loads(client.sendall.call_args.args[0])
        self.assertEqual(command, {"command": ["quit"]})

    def test_shutdown_cleans_up_stale_socket_left_by_exited_mpv(self):
        socket_path = Path(self.temp.name) / "mpv.sock"
        socket_path.touch()

        client = mock.MagicMock()
        client.__enter__.return_value = client
        client.sendall.side_effect = lambda payload: None
        # First connect (quit) succeeds; the wait-loop probe connect hits a
        # stale socket and is refused, as mpv does after exiting.
        client.connect.side_effect = [None, ConnectionRefusedError]
        with mock.patch.object(MODULE, "mpv_socket_path", return_value=socket_path), mock.patch.object(
            MODULE.socket, "socket", return_value=client
        ):
            MODULE.shutdown_playback()

        self.assertFalse(socket_path.exists())

    def test_wait_for_media_retries_resume_seek_until_load_is_ready(self):
        seek_attempts = 0
        unpaused = False

        def command(args):
            nonlocal seek_attempts, unpaused
            if args == ["get_property", "path"]:
                return "https://media.example/next.mp3"
            if args == ["get_property", "idle-active"]:
                return False
            if args[0] == "seek":
                seek_attempts += 1
                if seek_attempts == 1:
                    raise MODULE.HodlJuiceError("not ready")
                return None
            if args == ["set_property", "pause", False]:
                unpaused = True
                return None
            raise AssertionError(args)

        with mock.patch.object(MODULE, "mpv_command", side_effect=command), mock.patch.object(MODULE.time, "sleep"):
            MODULE.wait_for_media_ready("https://media.example/next.mp3", 12, timeout=1)

        self.assertEqual(seek_attempts, 2)
        self.assertTrue(unpaused)

    def test_mpv_command_skips_async_events(self):
        socket_path = Path(self.temp.name) / "mpv.sock"
        socket_path.touch()
        client = mock.MagicMock()
        client.__enter__.return_value = client
        client.recv.return_value = (
            b'{"event":"start-file"}\n'
            b'{"request_id":1,"error":"success","data":42}\n'
        )

        with mock.patch.object(MODULE, "mpv_socket_path", return_value=socket_path), mock.patch.object(
            MODULE.socket, "socket", return_value=client
        ):
            self.assertEqual(MODULE.mpv_command(["get_property", "time-pos"]), 42)

    @staticmethod
    def refused_error(command):
        try:
            raise ConnectionRefusedError(111, "Connection refused")
        except ConnectionRefusedError as error:
            raise MODULE.HodlJuiceError(f"Unable to control playback: {error}") from error

    def test_status_reports_stopped_for_stale_socket(self):
        socket_path = Path(self.temp.name) / "mpv.sock"
        socket_path.touch()
        with mock.patch.object(MODULE, "mpv_socket_path", return_value=socket_path), mock.patch.object(
            MODULE, "mpv_command", side_effect=self.refused_error
        ):
            status = MODULE.playback_status()
        self.assertEqual(status, {"schemaVersion": 1, "playback": "stopped"})
        self.assertFalse(socket_path.exists())

    def test_status_propagates_other_mpv_errors(self):
        socket_path = Path(self.temp.name) / "mpv.sock"
        socket_path.touch()
        with mock.patch.object(MODULE, "mpv_socket_path", return_value=socket_path), mock.patch.object(
            MODULE, "mpv_command", side_effect=MODULE.HodlJuiceError("mpv command failed: property not found")
        ):
            with self.assertRaises(MODULE.HodlJuiceError):
                MODULE.playback_status()
        self.assertTrue(socket_path.exists())

    def test_watch_reports_stopped_without_socket(self):
        socket_path = Path(self.temp.name) / "mpv.sock"
        with mock.patch.object(MODULE, "mpv_socket_path", return_value=socket_path):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                MODULE.watch_status()
        self.assertEqual(json.loads(output.getvalue()), {"schemaVersion": 1, "playback": "stopped"})

    def test_watch_unlinks_stale_socket_and_reports_stopped(self):
        socket_path = Path(self.temp.name) / "mpv.sock"
        socket_path.touch()

        class RefusedSocket:
            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def connect(self, path):
                raise ConnectionRefusedError(111, "Connection refused")

        with mock.patch.object(MODULE, "mpv_socket_path", return_value=socket_path), mock.patch.object(
            MODULE.socket, "socket", return_value=RefusedSocket()
        ):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                MODULE.watch_status()
        self.assertFalse(socket_path.exists())
        self.assertEqual(json.loads(output.getvalue()), {"schemaVersion": 1, "playback": "stopped"})

    def test_watch_streams_property_changes(self):
        socket_path = Path(self.temp.name) / "mpv.sock"
        socket_path.touch()

        class FakeSocket:
            def __init__(self, chunks):
                self.chunks = list(chunks)
                self.sent = []

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def connect(self, path):
                pass

            def sendall(self, data):
                self.sent.append(data)

            def recv(self, size):
                if not self.chunks:
                    return b""
                return self.chunks.pop(0)

        chunks = [
            b'{"event":"property-change","id":1,"name":"pause","data":false}\n'
            b'{"event":"property-change","id":2,"name":"time-pos","data":12.5}\n'
            b'{"event":"property-change","id":3,"name":"duration","data":60.0}\n'
            b'{"event":"property-change","id":4,"name":"volume","data":70}\n'
            b'{"event":"property-change","id":5,"name":"idle-active","data":false}\n'
            b'{"event":"property-change","id":1,"name":"pause","data":true}\n',
            b"",
        ]
        with mock.patch.object(MODULE, "mpv_socket_path", return_value=socket_path), mock.patch.object(
            MODULE.socket, "socket", return_value=FakeSocket(chunks)
        ):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                MODULE.watch_status()
        lines = [json.loads(line) for line in output.getvalue().strip().splitlines()]
        self.assertEqual(lines[0]["playback"], "playing")
        self.assertEqual(lines[0]["position"], 12.5)
        self.assertEqual(lines[0]["duration"], 60.0)
        self.assertEqual(lines[1]["playback"], "paused")
        self.assertEqual(lines[-1]["playback"], "stopped")


class PeopleParserTests(unittest.TestCase):
    def test_extracts_people_options(self):
        parser = MODULE.PeopleParser()
        parser.feed((ROOT / "tests" / "fixtures" / "people.html").read_text())
        self.assertEqual(parser.people, [
            {"value": "Adam_Back", "label": "Adam Back"},
            {"value": "Lyn_Alden", "label": "Lyn Alden"},
            {"value": "niftynei", "label": "niftynei"},
        ])


class SpectrumTests(unittest.TestCase):
    def test_analyzer_returns_21_bounded_bands(self):
        samples = [
            int(16000 * math.sin(2 * math.pi * 1000 * index / MODULE.SPECTRUM_RATE))
            for index in range(MODULE.SPECTRUM_WINDOW)
        ]
        bands = MODULE.analyze_spectrum(samples)
        self.assertEqual(len(bands), 21)
        self.assertTrue(all(0 <= value <= 1 for value in bands))
        self.assertGreater(max(bands), 0.5)
        center = min(range(len(MODULE.spectrum_centers())), key=lambda index: abs(MODULE.spectrum_centers()[index] - 1000))
        self.assertLessEqual(abs(bands.index(max(bands)) - center), 1)

    def test_silence_decays(self):
        loud = [0.8] * MODULE.SPECTRUM_BANDS
        quiet = MODULE.analyze_spectrum([0] * MODULE.SPECTRUM_WINDOW, loud)
        self.assertTrue(all(0 <= value < 0.8 for value in quiet))


class EpisodeParserTests(unittest.TestCase):
    def test_extracts_hidden_metadata(self):
        document = (ROOT / "tests" / "fixtures" / "episode.html").read_text()
        episode = MODULE.parse_episode(document, "https://hodljuice.app/?next=True")
        self.assertEqual(episode.guid, "episode-21")
        self.assertEqual(episode.title, "Why 21 Million Matters & What Comes Next")
        self.assertEqual(episode.podcast, "Signal & Noise")
        self.assertEqual(episode.audioUrl, "https://media.example.test/episode.mp3")
        self.assertEqual(episode.artworkUrl, "https://hodljuice.app/podcast-artwork/example")

    def test_extracts_legacy_category_markup(self):
        document = (ROOT / "tests" / "fixtures" / "category-episode.html").read_text()
        episode = MODULE.parse_episode(document, "https://hodljuice.app/money?next=True")
        self.assertEqual(episode.podcast, "Citizen Bitcoin")
        self.assertEqual(episode.artist, "Brady Swenson")
        self.assertEqual(episode.title, "Understanding Time, Money and Bitcoin from First Principles")
        self.assertEqual(episode.publishedAt, "2020-01-07")
        self.assertEqual(episode.audioUrl, "https://media.example.test/category.mp3")

    def test_rejects_missing_metadata(self):
        with self.assertRaises(MODULE.HodlJuiceError):
            MODULE.parse_episode("<html></html>", "https://hodljuice.app/")

    def test_rejects_unsafe_audio_url(self):
        document = '<div class="episode-info-mappapi" data-title="x" data-podcast-name="y" data-audio-url="file:///tmp/x"></div>'
        with self.assertRaises(MODULE.HodlJuiceError):
            MODULE.parse_episode(document, "https://hodljuice.app/")

    def test_date_span_inside_paragraph_does_not_hijack_capture(self):
        document = (
            '<div class="episode-info-mappapi" data-title="T" data-podcast-name="P" data-audio-url="https://media.example.test/a.mp3"></div>'
            '<div class="podcast-info-container"><p>by: Artist <span class="episode-date-text">2020-01-07</span> more</p></div>'
        )
        episode = MODULE.parse_episode(document, "https://hodljuice.app/")
        self.assertEqual(episode.artist, "Artist 2020-01-07 more")
        self.assertEqual(episode.publishedAt, "")


class FetchDocumentTests(unittest.TestCase):
    def test_hodljuice_redirect_requires_https_on_the_same_origin(self):
        self.assertTrue(MODULE._same_origin("https://hodljuice.app/next"))
        self.assertFalse(MODULE._same_origin("http://hodljuice.app/next"))
        self.assertFalse(MODULE._same_origin("https://hodljuice.app:444/next"))
        self.assertFalse(MODULE._same_origin("https://evil.example/next"))

    def test_redirect_to_foreign_host_is_rejected(self):
        import http.server
        import threading

        class RedirectHandler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(302)
                self.send_header("Location", "https://evil.example/steal")
                self.end_headers()

            def log_message(self, *args):
                pass

        server = http.server.HTTPServer(("127.0.0.1", 0), RedirectHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            port = server.server_address[1]
            with self.assertRaises(MODULE.HodlJuiceError) as context:
                MODULE.fetch_document(f"http://127.0.0.1:{port}/", timeout=5)
            self.assertIn("redirected", str(context.exception))
        finally:
            server.shutdown()
            thread.join(timeout=5)
            server.server_close()


if __name__ == "__main__":
    unittest.main()

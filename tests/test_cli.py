import importlib.machinery
import importlib.util
import math
import os
import sys
import tempfile
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

        with mock.patch.object(MODULE, "mpv_socket_path", return_value=socket_path), mock.patch.object(
            MODULE, "mpv_command", side_effect=lambda command: commands.append(command)
        ):
            MODULE.start_playback("https://media.example/next.mp3", "Next episode", "Podcast")

        self.assertEqual(commands[:2], [
            ["set_property", "force-media-title", "Next episode"],
            ["loadfile", "https://media.example/next.mp3", "replace"],
        ])

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


if __name__ == "__main__":
    unittest.main()

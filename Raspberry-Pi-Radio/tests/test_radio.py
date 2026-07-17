import importlib.util
import json
import tempfile
import threading
import unittest
import urllib.request
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "app" / "radio.py"
SPEC = importlib.util.spec_from_file_location("greylock_radio", MODULE_PATH)
assert SPEC and SPEC.loader
radio = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(radio)


class RadioTestCase(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.media = self.root / "media"
        (self.media / "music" / "A").mkdir(parents=True)
        (self.media / "music" / "B").mkdir(parents=True)
        (self.media / "announcements").mkdir(parents=True)
        for relative in ("music/A/a1.mp3", "music/A/a2.wav", "music/B/b1.ogg"):
            (self.media / relative).write_bytes(b"test")
        (self.media / "announcements" / "notice.mp3").write_bytes(b"test")
        self.config_path = self.root / "config.json"
        self.config_path.write_text(json.dumps({
            "media_root": str(self.media),
            "autostart": False,
            "shuffle_within_folders": False,
        }), encoding="utf-8")
        self.controller = radio.RadioController(self.config_path)

    def tearDown(self):
        self.controller.close()
        self.temp.cleanup()

    def test_library_scan_and_folder_rotation(self):
        library = self.controller.library_state()
        self.assertEqual(library["song_count"], 3)
        self.assertEqual([folder["name"] for folder in library["folders"]], ["A", "B"])
        with self.controller.lock:
            picks = [self.controller._next_song_locked().name for _ in range(4)]
        self.assertEqual(picks, ["a1.mp3", "b1.ogg", "a2.wav", "b1.ogg"])

    def test_announcement_is_queued_and_path_is_contained(self):
        self.controller.enqueue_announcement("announcements/notice.mp3")
        with self.controller.lock:
            path, kind = self.controller._choose_next_locked()
        self.assertEqual(kind, "announcement")
        self.assertEqual(path.name, "notice.mp3")
        with self.assertRaises(ValueError):
            self.controller.enqueue_announcement("music/A/a1.mp3")

    def test_config_update_is_normalized_and_saved(self):
        self.controller.update_config({
            "station_name": "  Test Radio  ",
            "music_volume": 999,
            "announcement_every_songs": -3,
        })
        saved = json.loads(self.config_path.read_text(encoding="utf-8"))
        self.assertEqual(saved["station_name"], "Test Radio")
        self.assertEqual(saved["music_volume"], 130)
        self.assertEqual(saved["announcement_every_songs"], 0)

    def test_http_state_and_static_page(self):
        server = radio.RadioHTTPServer(("127.0.0.1", 0), self.controller)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{server.server_address[1]}"
        try:
            with urllib.request.urlopen(base + "/api/state", timeout=3) as response:
                state = json.load(response)
            self.assertEqual(state["library"]["songs"], 3)
            with urllib.request.urlopen(base + "/", timeout=3) as response:
                page = response.read().decode("utf-8")
            self.assertIn("Greylock Automatic Radio", page)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main()

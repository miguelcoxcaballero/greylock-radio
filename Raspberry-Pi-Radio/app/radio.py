#!/usr/bin/env python3
"""Greylock automatic radio server.

The application intentionally uses only the Python standard library. mpv handles
file playback; arecord/aplay handle a microphone physically connected to the Pi.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import random
import signal
import subprocess
import threading
import time
from collections import deque
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse


APP_DIR = Path(__file__).resolve().parent
PROJECT_DIR = APP_DIR.parent
STATIC_DIR = APP_DIR / "static"
DEFAULT_CONFIG_PATH = PROJECT_DIR / "config" / "config.json"
AUDIO_EXTENSIONS = {".mp3", ".wav", ".ogg", ".flac", ".m4a", ".aac", ".opus"}

DEFAULT_CONFIG: dict[str, Any] = {
    "station_name": "Greylock Radio",
    "host": "0.0.0.0",
    "port": 8080,
    "media_root": str(PROJECT_DIR / "media"),
    "music_directory": "music",
    "announcements_directory": "announcements",
    "autostart": True,
    "shuffle_within_folders": True,
    "announcement_every_songs": 4,
    "music_volume": 85,
    "announcement_volume": 100,
    "mpv_audio_device": "auto",
    "alsa_capture_device": "default",
    "alsa_playback_device": "default",
    "live_sample_rate": 48000,
    "live_channels": 1,
    "scheduled_announcements": [],
}


def normalize_config(value: dict[str, Any]) -> dict[str, Any]:
    config = dict(DEFAULT_CONFIG)
    config.update(value)
    config["port"] = int(config["port"])
    if not 1 <= config["port"] <= 65535:
        raise ValueError("port must be between 1 and 65535")
    config["announcement_every_songs"] = max(0, int(config["announcement_every_songs"]))
    config["music_volume"] = max(0, min(130, int(config["music_volume"])))
    config["announcement_volume"] = max(0, min(130, int(config["announcement_volume"])))
    config["live_sample_rate"] = max(8000, min(192000, int(config["live_sample_rate"])))
    config["live_channels"] = max(1, min(2, int(config["live_channels"])))
    config["station_name"] = str(config["station_name"]).strip() or "Greylock Radio"
    config["host"] = str(config["host"]).strip() or "0.0.0.0"
    for key in ("music_directory", "announcements_directory"):
        config[key] = str(config[key]).strip()
        if not config[key]:
            raise ValueError(f"{key} cannot be empty")
    if not isinstance(config.get("scheduled_announcements"), list):
        raise ValueError("scheduled_announcements must be a list")
    return config


def load_config(path: Path) -> dict[str, Any]:
    loaded: dict[str, Any] = {}
    if path.exists():
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
        if not isinstance(value, dict):
            raise ValueError("config.json must contain a JSON object")
        loaded = value
    return normalize_config(loaded)


def atomic_write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    temporary.replace(path)


class RadioController:
    def __init__(self, config_path: Path):
        self.config_path = config_path
        self.config = load_config(config_path)
        self.media_root = Path(self.config["media_root"]).expanduser().resolve()
        self.music_root = self.media_root / str(self.config["music_directory"])
        self.announcements_root = self.media_root / str(self.config["announcements_directory"])
        self.music_root.mkdir(parents=True, exist_ok=True)
        self.announcements_root.mkdir(parents=True, exist_ok=True)

        self.lock = threading.RLock()
        self.condition = threading.Condition(self.lock)
        self.shutdown_event = threading.Event()
        self.running = bool(self.config["autostart"])
        self.paused = False
        self.live = False
        self.current: dict[str, Any] | None = None
        self.player: subprocess.Popen[bytes] | None = None
        self.live_capture: subprocess.Popen[bytes] | None = None
        self.live_playback: subprocess.Popen[bytes] | None = None
        self.manual_announcements: deque[Path] = deque()
        self.songs_since_announcement = 0
        self.last_error = ""
        self.updated_at = time.time()
        self._interrupt_current = False
        self._scheduled_keys: set[str] = set()
        self._folder_order: list[str] = []
        self._folder_decks: dict[str, list[Path]] = {}
        self._folder_positions: dict[str, int] = {}
        self._folder_cursor = 0
        self.announcements: list[Path] = []
        self.rescan()

        self.worker = threading.Thread(target=self._worker_loop, name="radio-player", daemon=True)
        self.worker.start()

    def _touch_locked(self) -> None:
        self.updated_at = time.time()

    def _relative(self, path: Path) -> str:
        try:
            return path.resolve().relative_to(self.media_root).as_posix()
        except ValueError:
            return path.name

    def _track_info(self, path: Path, kind: str) -> dict[str, Any]:
        return {"name": path.stem, "file": self._relative(path), "kind": kind}

    def _scan_files(self, root: Path) -> list[Path]:
        if not root.exists():
            return []
        return sorted(
            (path for path in root.rglob("*") if path.is_file() and path.suffix.lower() in AUDIO_EXTENSIONS),
            key=lambda path: path.as_posix().lower(),
        )

    def rescan(self) -> dict[str, Any]:
        songs = self._scan_files(self.music_root)
        grouped: dict[str, list[Path]] = {}
        for song in songs:
            folder = song.parent.relative_to(self.music_root).as_posix()
            if folder == ".":
                folder = "General"
            grouped.setdefault(folder, []).append(song)

        with self.condition:
            self._folder_order = sorted(grouped, key=str.lower)
            self._folder_decks = {}
            self._folder_positions = {}
            for folder in self._folder_order:
                deck = list(grouped[folder])
                if self.config["shuffle_within_folders"]:
                    random.shuffle(deck)
                self._folder_decks[folder] = deck
                self._folder_positions[folder] = 0
            self._folder_cursor = 0
            self.announcements = self._scan_files(self.announcements_root)
            self.last_error = ""
            self._touch_locked()
            self.condition.notify_all()
            return self.library_state_locked()

    def library_state_locked(self) -> dict[str, Any]:
        folders = []
        for folder in self._folder_order:
            files = self._folder_decks.get(folder, [])
            folders.append(
                {
                    "name": folder,
                    "count": len(files),
                    "tracks": [self._track_info(path, "song") for path in sorted(files, key=lambda p: p.name.lower())],
                }
            )
        return {
            "folders": folders,
            "song_count": sum(item["count"] for item in folders),
            "announcements": [self._track_info(path, "announcement") for path in self.announcements],
        }

    def library_state(self) -> dict[str, Any]:
        with self.lock:
            return self.library_state_locked()

    def _next_song_locked(self) -> Path | None:
        if not self._folder_order:
            return None
        attempts = len(self._folder_order)
        while attempts:
            folder = self._folder_order[self._folder_cursor % len(self._folder_order)]
            self._folder_cursor = (self._folder_cursor + 1) % len(self._folder_order)
            attempts -= 1
            deck = self._folder_decks.get(folder, [])
            if not deck:
                continue
            position = self._folder_positions.get(folder, 0)
            if position >= len(deck):
                if self.config["shuffle_within_folders"]:
                    random.shuffle(deck)
                position = 0
            song = deck[position]
            self._folder_positions[folder] = position + 1
            return song
        return None

    def _resolve_announcement(self, relative_path: str) -> Path:
        candidate = (self.media_root / relative_path).resolve()
        if self.announcements_root.resolve() not in candidate.parents:
            raise ValueError("Announcement must be inside the announcements directory")
        if not candidate.is_file() or candidate.suffix.lower() not in AUDIO_EXTENSIONS:
            raise ValueError("Announcement file does not exist or is not supported")
        return candidate

    def enqueue_announcement(self, relative_path: str) -> None:
        announcement = self._resolve_announcement(relative_path)
        with self.condition:
            self.manual_announcements.append(announcement)
            if self.player and self.current and self.current.get("kind") == "song":
                self._terminate_player_locked(interrupted=True)
            self._touch_locked()
            self.condition.notify_all()

    def start(self) -> None:
        with self.condition:
            self.running = True
            self.paused = False
            self.last_error = ""
            self._touch_locked()
            self.condition.notify_all()

    def stop(self) -> None:
        with self.condition:
            self.running = False
            self.paused = False
            self._terminate_player_locked(interrupted=True)
            self.current = None
            self._touch_locked()
            self.condition.notify_all()

    def pause(self) -> None:
        with self.condition:
            if self.player and self.player.poll() is None and not self.paused:
                os.kill(self.player.pid, signal.SIGSTOP)
                self.paused = True
                self._touch_locked()

    def resume(self) -> None:
        with self.condition:
            if self.player and self.player.poll() is None and self.paused:
                os.kill(self.player.pid, signal.SIGCONT)
            self.paused = False
            self.running = True
            self._touch_locked()
            self.condition.notify_all()

    def next(self) -> None:
        with self.condition:
            self._terminate_player_locked(interrupted=True)
            self.paused = False
            self._touch_locked()
            self.condition.notify_all()

    def _terminate_player_locked(self, interrupted: bool) -> None:
        process = self.player
        if not process:
            return
        self._interrupt_current = interrupted
        if self.paused and process.poll() is None:
            try:
                os.kill(process.pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=1.5)
            except subprocess.TimeoutExpired:
                process.kill()
        self.paused = False

    def _mpv_command(self, path: Path, kind: str) -> list[str]:
        volume = self.config["announcement_volume"] if kind == "announcement" else self.config["music_volume"]
        command = [
            "mpv",
            "--no-config",
            "--no-video",
            "--audio-display=no",
            "--terminal=no",
            "--really-quiet",
            f"--volume={volume}",
        ]
        audio_device = str(self.config.get("mpv_audio_device", "auto")).strip()
        if audio_device:
            command.append(f"--audio-device={audio_device}")
        command.append(str(path))
        return command

    def _begin_track_locked(self, path: Path, kind: str) -> None:
        try:
            self.player = subprocess.Popen(self._mpv_command(path, kind), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.current = self._track_info(path, kind)
            self.current["started_at"] = time.time()
            self._interrupt_current = False
            self.last_error = ""
        except OSError as exc:
            self.player = None
            self.current = None
            self.last_error = f"Could not start mpv: {exc}"
        self._touch_locked()

    def _choose_next_locked(self) -> tuple[Path, str] | None:
        if self.manual_announcements:
            self.songs_since_announcement = 0
            return self.manual_announcements.popleft(), "announcement"
        every = int(self.config["announcement_every_songs"])
        if every and self.songs_since_announcement >= every and self.announcements:
            self.songs_since_announcement = 0
            return random.choice(self.announcements), "announcement"
        song = self._next_song_locked()
        if song:
            return song, "song"
        if self.announcements:
            return random.choice(self.announcements), "announcement"
        return None

    def _queue_scheduled_locked(self) -> None:
        now = datetime.now()
        today_prefix = now.strftime("%Y-%m-%d")
        self._scheduled_keys = {key for key in self._scheduled_keys if key.startswith(today_prefix)}
        for item in self.config.get("scheduled_announcements", []):
            if not isinstance(item, dict) or not item.get("enabled", True):
                continue
            if str(item.get("time", "")) != now.strftime("%H:%M"):
                continue
            days = item.get("days")
            try:
                if days and now.weekday() not in [int(day) for day in days]:
                    continue
            except (TypeError, ValueError):
                self.last_error = "A scheduled announcement has an invalid days list."
                continue
            filename = str(item.get("file", ""))
            key = f"{today_prefix}|{item.get('time')}|{filename}"
            if key in self._scheduled_keys:
                continue
            try:
                path = self._resolve_announcement(filename)
            except ValueError as exc:
                self.last_error = str(exc)
                continue
            self.manual_announcements.append(path)
            self._scheduled_keys.add(key)
            if self.player and self.current and self.current.get("kind") == "song":
                self._terminate_player_locked(interrupted=True)

    def _live_processes_alive_locked(self) -> bool:
        return bool(
            self.live_capture
            and self.live_playback
            and self.live_capture.poll() is None
            and self.live_playback.poll() is None
        )

    def start_live(self) -> None:
        with self.condition:
            if self.live:
                return
            self._terminate_player_locked(interrupted=True)
            rate = str(int(self.config["live_sample_rate"]))
            channels = str(int(self.config["live_channels"]))
            capture_command = [
                "arecord", "-q", "-D", str(self.config["alsa_capture_device"]),
                "-t", "raw", "-f", "S16_LE", "-r", rate, "-c", channels,
            ]
            playback_command = [
                "aplay", "-q", "-D", str(self.config["alsa_playback_device"]),
                "-t", "raw", "-f", "S16_LE", "-r", rate, "-c", channels,
            ]
            try:
                self.live_capture = subprocess.Popen(capture_command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                assert self.live_capture.stdout is not None
                self.live_playback = subprocess.Popen(playback_command, stdin=self.live_capture.stdout, stderr=subprocess.DEVNULL)
                self.live_capture.stdout.close()
                self.live = True
                self.current = {"name": "Live microphone", "file": "", "kind": "live", "started_at": time.time()}
                self.last_error = ""
            except (OSError, AssertionError) as exc:
                self._stop_live_locked()
                self.last_error = f"Could not start the live microphone: {exc}"
                raise RuntimeError(self.last_error) from exc
            self._touch_locked()
            self.condition.notify_all()

    def _stop_live_locked(self) -> None:
        for process in (self.live_capture, self.live_playback):
            if process and process.poll() is None:
                process.terminate()
        for process in (self.live_capture, self.live_playback):
            if process:
                try:
                    process.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    process.kill()
        self.live_capture = None
        self.live_playback = None
        self.live = False
        if self.current and self.current.get("kind") == "live":
            self.current = None

    def stop_live(self) -> None:
        with self.condition:
            self._stop_live_locked()
            self._touch_locked()
            self.condition.notify_all()

    def update_config(self, changes: dict[str, Any]) -> None:
        allowed = {
            "station_name", "announcement_every_songs", "music_volume", "announcement_volume",
            "mpv_audio_device", "alsa_capture_device", "alsa_playback_device",
            "live_sample_rate", "live_channels", "scheduled_announcements", "shuffle_within_folders",
        }
        unknown = set(changes) - allowed
        if unknown:
            raise ValueError("Unsupported settings: " + ", ".join(sorted(unknown)))
        with self.condition:
            self.config.update(changes)
            self.config = load_config_from_value(self.config)
            atomic_write_json(self.config_path, self.config)
            self._touch_locked()
        if "shuffle_within_folders" in changes:
            self.rescan()

    def public_config(self) -> dict[str, Any]:
        with self.lock:
            return {key: self.config[key] for key in DEFAULT_CONFIG if key not in {"host", "port", "media_root"}}

    def state_snapshot(self) -> dict[str, Any]:
        with self.condition:
            if self.live and not self._live_processes_alive_locked():
                self._stop_live_locked()
                self.last_error = "The live audio process stopped unexpectedly. Check the ALSA device names."
            return {
                "station_name": self.config["station_name"],
                "running": self.running,
                "paused": self.paused,
                "live": self.live,
                "now_playing": self.current,
                "queued_announcements": len(self.manual_announcements),
                "songs_since_announcement": self.songs_since_announcement,
                "last_error": self.last_error,
                "updated_at": self.updated_at,
                "library": {
                    "songs": sum(len(deck) for deck in self._folder_decks.values()),
                    "folders": len(self._folder_order),
                    "announcements": len(self.announcements),
                },
            }

    def _worker_loop(self) -> None:
        while not self.shutdown_event.is_set():
            with self.condition:
                self._queue_scheduled_locked()
                if self.live:
                    self.condition.wait(timeout=0.5)
                    continue

                if self.player:
                    return_code = self.player.poll()
                    if return_code is None:
                        self.condition.wait(timeout=0.35)
                        continue
                    previous_kind = self.current.get("kind") if self.current else ""
                    interrupted = self._interrupt_current
                    self.player = None
                    self.current = None
                    self._interrupt_current = False
                    if not interrupted and previous_kind == "song":
                        self.songs_since_announcement += 1
                    self._touch_locked()

                if not self.running or self.paused:
                    self.condition.wait(timeout=0.5)
                    continue

                selection = self._choose_next_locked()
                if not selection:
                    self.last_error = "No playable audio found. Add files and press Rescan library."
                    self.condition.wait(timeout=2)
                    continue
                path, kind = selection
                self._begin_track_locked(path, kind)
            time.sleep(0.05)

    def close(self) -> None:
        self.shutdown_event.set()
        with self.condition:
            self._terminate_player_locked(interrupted=True)
            self._stop_live_locked()
            self.condition.notify_all()
        self.worker.join(timeout=2)


def load_config_from_value(value: dict[str, Any]) -> dict[str, Any]:
    return normalize_config(value)


class RadioRequestHandler(BaseHTTPRequestHandler):
    server_version = "GreylockRadio/1.0"

    @property
    def controller(self) -> RadioController:
        return self.server.controller  # type: ignore[attr-defined]

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"{self.address_string()} - {fmt % args}")

    def _json(self, value: Any, status: int = HTTPStatus.OK) -> None:
        payload = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        if length > 1_000_000:
            raise ValueError("Request is too large")
        if not length:
            return {}
        value = json.loads(self.rfile.read(length).decode("utf-8"))
        if not isinstance(value, dict):
            raise ValueError("JSON body must be an object")
        return value

    def _serve_static(self, request_path: str) -> None:
        if request_path in {"", "/"}:
            relative = "index.html"
        else:
            relative = unquote(request_path.lstrip("/"))
        candidate = (STATIC_DIR / relative).resolve()
        if STATIC_DIR.resolve() not in candidate.parents and candidate != STATIC_DIR.resolve():
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        if not candidate.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        content = candidate.read_bytes()
        content_type = mimetypes.guess_type(candidate.name)[0] or "application/octet-stream"
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        if path == "/api/health":
            self._json({"ok": True})
        elif path == "/api/state":
            self._json(self.controller.state_snapshot())
        elif path == "/api/library":
            self._json(self.controller.library_state())
        elif path == "/api/config":
            self._json(self.controller.public_config())
        elif path.startswith("/api/"):
            self._json({"error": "Not found"}, HTTPStatus.NOT_FOUND)
        else:
            self._serve_static(path)

    def do_POST(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        try:
            body = self._read_json()
            if path == "/api/control/start":
                self.controller.start()
            elif path == "/api/control/stop":
                self.controller.stop()
            elif path == "/api/control/pause":
                self.controller.pause()
            elif path == "/api/control/resume":
                self.controller.resume()
            elif path == "/api/control/next":
                self.controller.next()
            elif path == "/api/library/rescan":
                self._json({"ok": True, "library": self.controller.rescan()})
                return
            elif path == "/api/announcement/play":
                self.controller.enqueue_announcement(str(body.get("file", "")))
            elif path == "/api/live/start":
                self.controller.start_live()
            elif path == "/api/live/stop":
                self.controller.stop_live()
            elif path == "/api/config":
                self.controller.update_config(body)
            else:
                self._json({"error": "Not found"}, HTTPStatus.NOT_FOUND)
                return
            self._json({"ok": True, "state": self.controller.state_snapshot()})
        except (ValueError, json.JSONDecodeError) as exc:
            self._json({"error": str(exc)}, HTTPStatus.BAD_REQUEST)
        except RuntimeError as exc:
            self._json({"error": str(exc)}, HTTPStatus.CONFLICT)
        except Exception as exc:  # Keep the control panel alive and expose a useful error.
            self._json({"error": f"Unexpected server error: {exc}"}, HTTPStatus.INTERNAL_SERVER_ERROR)


class RadioHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], controller: RadioController):
        super().__init__(address, RadioRequestHandler)
        self.controller = controller


def main() -> int:
    parser = argparse.ArgumentParser(description="Greylock automatic radio")
    parser.add_argument("--config", type=Path, default=Path(os.environ.get("GREYLOCK_RADIO_CONFIG", DEFAULT_CONFIG_PATH)))
    parser.add_argument("--check", action="store_true", help="Validate configuration and media paths, then exit")
    args = parser.parse_args()

    controller = RadioController(args.config.resolve())
    if args.check:
        print(json.dumps({"config": controller.public_config(), "library": controller.library_state()}, indent=2))
        controller.close()
        return 0

    server = RadioHTTPServer((str(controller.config["host"]), int(controller.config["port"])), controller)
    print(f"Greylock Radio listening on http://{controller.config['host']}:{controller.config['port']}")
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        controller.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

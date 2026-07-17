const $ = (id) => document.getElementById(id);

const els = {
  connectionDot: $("connectionDot"),
  connectionText: $("connectionText"),
  modeLabel: $("modeLabel"),
  trackName: $("trackName"),
  trackFile: $("trackFile"),
  progressPulse: $("progressPulse"),
  summary: $("summary"),
  errorBox: $("errorBox"),
  startBtn: $("startBtn"),
  pauseBtn: $("pauseBtn"),
  nextBtn: $("nextBtn"),
  stopBtn: $("stopBtn"),
  liveStrip: $("liveStrip"),
  liveBtn: $("liveBtn"),
  rescanBtn: $("rescanBtn"),
  folderList: $("folderList"),
  announcementCount: $("announcementCount"),
  announcementList: $("announcementList"),
  settingsForm: $("settingsForm"),
  settingsStatus: $("settingsStatus"),
  stationName: $("stationName"),
  announcementEvery: $("announcementEvery"),
  musicVolume: $("musicVolume"),
  announcementVolume: $("announcementVolume"),
  mpvDevice: $("mpvDevice"),
  captureDevice: $("captureDevice"),
  playbackDevice: $("playbackDevice"),
};

let currentState = null;
let library = null;
let settingsLoaded = false;
let busy = false;

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
    ...options,
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || `Request failed (${response.status})`);
  return data;
}

function setConnected(online) {
  els.connectionDot.classList.toggle("online", online);
  els.connectionText.textContent = online ? "Radio connected" : "Connection lost";
}

function setBusy(value) {
  busy = value;
  document.querySelectorAll("button").forEach((button) => { button.disabled = value; });
}

function showError(message) {
  els.errorBox.textContent = message || "";
  els.errorBox.classList.toggle("hidden", !message);
}

function renderState(state) {
  currentState = state;
  const playing = state.now_playing;
  els.modeLabel.textContent = state.live ? "LIVE" : playing ? (playing.kind === "announcement" ? "ANNOUNCEMENT" : "ON AIR") : "OFF AIR";
  els.trackName.textContent = playing ? playing.name : (state.running ? "Waiting for audio" : "Radio stopped");
  els.trackFile.textContent = playing ? (playing.file || "Microphone connected to this Pi") : "Press Start radio when the audio system is ready.";
  els.progressPulse.classList.toggle("moving", Boolean(playing && !state.paused));
  els.pauseBtn.textContent = state.paused ? "\u25b6" : "\u2161";
  els.pauseBtn.title = state.paused ? "Resume" : "Pause";
  els.pauseBtn.setAttribute("aria-label", state.paused ? "Resume" : "Pause");
  els.liveStrip.classList.toggle("active", state.live);
  els.liveBtn.textContent = state.live ? "End live announcement" : "Start live announcement";
  els.summary.textContent = `${state.library.songs} songs in ${state.library.folders} folders \u00b7 ${state.library.announcements} recorded announcements \u00b7 ${state.queued_announcements} queued`;
  showError(state.last_error);
  document.title = `${state.station_name} \u00b7 ${playing ? playing.name : "Off air"}`;
}

function emptyMessage(text) {
  const node = document.createElement("div");
  node.className = "empty-state";
  node.textContent = text;
  return node;
}

function renderLibrary(data) {
  library = data;
  els.folderList.replaceChildren();
  if (!data.folders.length) {
    els.folderList.append(emptyMessage("No songs found. Copy audio into media/music, using subfolders for each rotation category, then press Rescan."));
  } else {
    data.folders.forEach((folder) => {
      const row = document.createElement("article");
      row.className = "folder-row";
      const tracks = folder.tracks.slice(0, 6).map((track) => `<li title="${escapeHtml(track.file)}">${escapeHtml(track.name)}</li>`).join("");
      const more = folder.tracks.length > 6 ? `<li>+ ${folder.tracks.length - 6} more</li>` : "";
      row.innerHTML = `<div class="folder-head"><span class="folder-name">${escapeHtml(folder.name)}</span><span class="folder-count">${folder.count} tracks</span></div><ul class="track-list">${tracks}${more}</ul>`;
      els.folderList.append(row);
    });
  }

  els.announcementCount.textContent = data.announcements.length;
  els.announcementList.replaceChildren();
  if (!data.announcements.length) {
    els.announcementList.append(emptyMessage("No announcements found. Copy audio into media/announcements and press Rescan."));
  } else {
    data.announcements.forEach((announcement) => {
      const row = document.createElement("article");
      row.className = "announcement-row";
      row.innerHTML = `<div><div class="announcement-name">${escapeHtml(announcement.name)}</div><div class="announcement-file">${escapeHtml(announcement.file)}</div></div><button class="play-announcement" type="button" data-announcement="${escapeAttribute(announcement.file)}">Play now</button>`;
      els.announcementList.append(row);
    });
  }
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char]));
}

function escapeAttribute(value) {
  return escapeHtml(value);
}

async function refreshState() {
  try {
    const state = await api("/api/state");
    setConnected(true);
    renderState(state);
  } catch (error) {
    setConnected(false);
    showError(error.message);
  }
}

async function refreshLibrary() {
  const data = await api("/api/library");
  renderLibrary(data);
}

async function loadSettings() {
  const config = await api("/api/config");
  els.stationName.value = config.station_name;
  els.announcementEvery.value = config.announcement_every_songs;
  els.musicVolume.value = config.music_volume;
  els.announcementVolume.value = config.announcement_volume;
  els.mpvDevice.value = config.mpv_audio_device;
  els.captureDevice.value = config.alsa_capture_device;
  els.playbackDevice.value = config.alsa_playback_device;
  settingsLoaded = true;
}

async function command(path, body = {}) {
  if (busy) return;
  setBusy(true);
  try {
    const result = await api(path, { method: "POST", body: JSON.stringify(body) });
    if (result.state) renderState(result.state);
  } catch (error) {
    showError(error.message);
  } finally {
    setBusy(false);
    await refreshState();
  }
}

els.startBtn.addEventListener("click", () => command("/api/control/start"));
els.pauseBtn.addEventListener("click", () => command(currentState && currentState.paused ? "/api/control/resume" : "/api/control/pause"));
els.nextBtn.addEventListener("click", () => command("/api/control/next"));
els.stopBtn.addEventListener("click", () => command("/api/control/stop"));
els.liveBtn.addEventListener("click", () => command(currentState && currentState.live ? "/api/live/stop" : "/api/live/start"));

els.rescanBtn.addEventListener("click", async () => {
  if (busy) return;
  setBusy(true);
  try {
    const result = await api("/api/library/rescan", { method: "POST", body: "{}" });
    renderLibrary(result.library);
    await refreshState();
  } catch (error) {
    showError(error.message);
  } finally {
    setBusy(false);
  }
});

els.announcementList.addEventListener("click", (event) => {
  const button = event.target.closest("[data-announcement]");
  if (button) command("/api/announcement/play", { file: button.dataset.announcement });
});

els.settingsForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (!settingsLoaded || busy) return;
  setBusy(true);
  els.settingsStatus.textContent = "Saving...";
  try {
    await api("/api/config", {
      method: "POST",
      body: JSON.stringify({
        station_name: els.stationName.value.trim(),
        announcement_every_songs: Number(els.announcementEvery.value),
        music_volume: Number(els.musicVolume.value),
        announcement_volume: Number(els.announcementVolume.value),
        mpv_audio_device: els.mpvDevice.value.trim() || "auto",
        alsa_capture_device: els.captureDevice.value.trim() || "default",
        alsa_playback_device: els.playbackDevice.value.trim() || "default",
      }),
    });
    els.settingsStatus.textContent = "Saved";
    await refreshState();
  } catch (error) {
    els.settingsStatus.textContent = error.message;
  } finally {
    setBusy(false);
  }
});

async function boot() {
  try {
    await Promise.all([refreshState(), refreshLibrary(), loadSettings()]);
  } catch (error) {
    setConnected(false);
    showError(error.message);
  }
  window.setInterval(refreshState, 1000);
  window.setInterval(refreshLibrary, 15000);
}

boot();

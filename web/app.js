// Guitar Tab Player — versão web
// Lê os dados de GuitarTabPlayer/Resources/tab-*.json (embutidos em songs-data.js) e toca
// cada tab de verdade via Web Audio, com mixer por faixa, transporte e tablatura sincronizada.

(function () {
  "use strict";

  const NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
  const TRACK_COLORS = ["#5cc8ff", "#ff7a5c", "#5cff9d", "#e0b3ff", "#ffd35c", "#ff5c8a"];
  const DRUM_LANES = ["kick", "snare", "tomLow", "tomMid", "hiHatClosed", "ride"];
  const SCHEDULE_LEAD = 0.12; // s, margem antes de começar a tocar

  const ctx = new (window.AudioContext || window.webkitAudioContext)();
  const masterGain = ctx.createGain();
  masterGain.gain.value = 0.9;
  masterGain.connect(ctx.destination);
  // ponto de captação usado por recording.js para gravar o áudio do player junto com o mic.
  const recordingDestination = ctx.createMediaStreamDestination();
  masterGain.connect(recordingDestination);
  window.__playerRecordingDestination = recordingDestination;

  let noiseBuffer = null;
  function getNoiseBuffer() {
    if (noiseBuffer) return noiseBuffer;
    const len = ctx.sampleRate * 1;
    const buf = ctx.createBuffer(1, len, ctx.sampleRate);
    const data = buf.getChannelData(0);
    for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
    noiseBuffer = buf;
    return buf;
  }

  function midiToFreq(midi) {
    return 440 * Math.pow(2, (midi - 69) / 12);
  }

  // ---- Estado ----
  const state = {
    song: null,
    tracks: [],          // { def, gainNode, pannerNode, muted, solo, volume, pan }
    selectedTrackId: null,
    isPlaying: false,
    startCtxTime: 0,      // ctx.currentTime em que o beat 0-relativo começou a soar
    startBeat: 0,         // beat de onde a reprodução partiu
    secondsPerBeat: 0.5,
    speed: 1,
    transpose: 0,
    metronomeOn: false,
    countInOn: true,
    liveNodes: [],         // nós agendados, para poder parar tudo
    rafId: null,
    songEndBeat: 0,
  };

  // ---- Carregar biblioteca ----
  const songListEl = document.getElementById("song-list-items");
  (window.SONGS || []).forEach((song) => {
    const btn = document.createElement("button");
    btn.className = "song-item";
    btn.innerHTML = `${escapeHtml(song.title)}<small>${escapeHtml(song.artist || "")} · ${song.tempo} BPM</small>`;
    btn.addEventListener("click", () => loadSong(song, btn));
    songListEl.appendChild(btn);
  });

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  }

  function instrumentVoice(instrument) {
    switch (instrument) {
      case "leadGuitar": return { wave: "sawtooth", cutoff: 2200, attack: 0.004, decay: 0.16, sustain: 0.5, release: 0.14, gain: 0.5 };
      case "rhythmGuitar": return { wave: "triangle", cutoff: 1800, attack: 0.004, decay: 0.2, sustain: 0.38, release: 0.16, gain: 0.42 };
      case "acousticGuitar": return { wave: "triangle", cutoff: 2600, attack: 0.003, decay: 0.28, sustain: 0.3, release: 0.22, gain: 0.42 };
      case "bass": return { wave: "sine", cutoff: 900, attack: 0.008, decay: 0.22, sustain: 0.65, release: 0.2, gain: 0.6 };
      case "piano": return { wave: "triangle", cutoff: 3600, attack: 0.002, decay: 0.4, sustain: 0.22, release: 0.3, gain: 0.4 };
      default: return { wave: "triangle", cutoff: 2000, attack: 0.005, decay: 0.2, sustain: 0.4, release: 0.16, gain: 0.45 };
    }
  }

  function loadSong(song, btnEl) {
    stopPlayback();
    state.song = song;
    state.startBeat = 0;
    state.transpose = 0;
    document.getElementById("transpose-label").textContent = "0";

    [...songListEl.children].forEach((el) => el.classList.remove("active"));
    if (btnEl) btnEl.classList.add("active");

    // (re)cria os nós persistentes de cada faixa
    state.tracks.forEach((t) => { t.gainNode.disconnect(); t.pannerNode.disconnect(); });
    state.tracks = song.tracks.map((def, i) => {
      const gainNode = ctx.createGain();
      const pannerNode = ctx.createStereoPanner();
      gainNode.connect(pannerNode).connect(masterGain);
      pannerNode.pan.value = def.pan || 0;
      const volume = def.volume != null ? def.volume : 0.85;
      gainNode.gain.value = volume;
      return {
        def, color: TRACK_COLORS[i % TRACK_COLORS.length],
        gainNode, pannerNode,
        muted: !!def.isMuted, solo: !!def.isSolo, volume, pan: def.pan || 0,
      };
    });
    state.selectedTrackId = state.tracks[0] ? state.tracks[0].def.id : null;
    applyMixToGains();

    state.songEndBeat = Math.max(0, ...song.tracks.flatMap((t) => t.events.map((e) => e.startBeat + e.durationBeats)));

    document.getElementById("empty-state").hidden = true;
    document.getElementById("player-content").hidden = false;
    document.getElementById("song-title").textContent = song.title;
    const keyName = NOTE_NAMES[(song.key && song.key.root) || 0] + " " + ((song.key && song.key.mode) || "");
    document.getElementById("song-meta").textContent =
      `${song.artist || ""} — ${song.tempo} BPM — ${keyName} — ${song.timeSignature.beatsPerBar}/${song.timeSignature.beatUnit}`;

    renderMixer();
    renderTrackTabs();
    updateTimeLabel(0);
    document.getElementById("scrubber").value = 0;
    drawTab();
  }

  // ---- Mixer ----
  function applyMixToGains() {
    const anySolo = state.tracks.some((t) => t.solo);
    state.tracks.forEach((t) => {
      const audible = anySolo ? t.solo : !t.muted;
      t.gainNode.gain.setTargetAtTime(audible ? t.volume : 0, ctx.currentTime, 0.01);
      t.pannerNode.pan.setTargetAtTime(t.pan, ctx.currentTime, 0.01);
    });
  }

  function renderMixer() {
    const el = document.getElementById("mixer");
    el.innerHTML = "";
    state.tracks.forEach((t) => {
      const row = document.createElement("div");
      row.className = "track-row" + (t.def.id === state.selectedTrackId ? " selected" : "");

      const swatch = document.createElement("div");
      swatch.className = "swatch";
      swatch.style.background = t.color;

      const name = document.createElement("div");
      name.className = "name";
      name.innerHTML = `${escapeHtml(t.def.name)}<small>${t.def.instrument}${t.def.tuning ? " · " + t.def.tuning.name : ""}</small>`;
      name.addEventListener("click", () => { state.selectedTrackId = t.def.id; renderMixer(); renderTrackTabs(); drawTab(); });

      const soloBtn = document.createElement("button");
      soloBtn.className = "mini-btn" + (t.solo ? " on-solo" : "");
      soloBtn.textContent = "S";
      soloBtn.title = "Solo";
      soloBtn.addEventListener("click", () => { t.solo = !t.solo; applyMixToGains(); renderMixer(); });

      const muteBtn = document.createElement("button");
      muteBtn.className = "mini-btn" + (t.muted ? " on-mute" : "");
      muteBtn.textContent = "M";
      muteBtn.title = "Mute";
      muteBtn.addEventListener("click", () => { t.muted = !t.muted; applyMixToGains(); renderMixer(); });

      const vol = document.createElement("input");
      vol.type = "range"; vol.min = 0; vol.max = 1; vol.step = 0.01; vol.value = t.volume;
      vol.addEventListener("input", () => { t.volume = parseFloat(vol.value); applyMixToGains(); });

      row.append(swatch, name, soloBtn, muteBtn, vol);
      el.appendChild(row);
    });
  }

  // ---- Síntese ----
  function scheduleEnvelope(gainParam, t0, attack, decay, sustainLevel, noteEnd, release, peak) {
    gainParam.cancelScheduledValues(t0);
    gainParam.setValueAtTime(0.0001, t0);
    gainParam.linearRampToValueAtTime(peak, t0 + attack);
    gainParam.exponentialRampToValueAtTime(Math.max(0.0001, peak * sustainLevel), t0 + attack + decay);
    gainParam.setValueAtTime(Math.max(0.0001, peak * sustainLevel), Math.max(t0 + attack + decay, noteEnd));
    gainParam.exponentialRampToValueAtTime(0.0001, noteEnd + release);
  }

  function pitchForNote(track, note, transposeSemis) {
    const strings = track.def.tuning.strings;
    const open = strings[note.string];
    const capo = track.def.capo || 0;
    return open + note.fret + capo + transposeSemis;
  }

  function playPitchedNote(track, note, t0, durSec, transposeSemis, targetGain) {
    const voice = instrumentVoice(track.def.instrument);
    const midi = pitchForNote(track, note, transposeSemis);
    let freq = midiToFreq(midi);

    const osc = ctx.createOscillator();
    osc.type = voice.wave;
    const filter = ctx.createBiquadFilter();
    filter.type = "lowpass";
    const technique = note.technique || "none";
    filter.frequency.value = technique === "palmMute" ? voice.cutoff * 0.35 : voice.cutoff;

    const gainNode = ctx.createGain();
    osc.connect(filter).connect(gainNode).connect(targetGain);

    const vel = note.velocity != null ? note.velocity : 0.8;
    const peak = voice.gain * vel;

    let noteEnd = t0 + durSec;
    let release = voice.release;
    let decay = voice.decay;
    let sustain = voice.sustain;
    if (technique === "palmMute") { decay = Math.min(decay, 0.08); sustain *= 0.5; release = 0.05; noteEnd = Math.min(noteEnd, t0 + Math.max(durSec * 0.6, 0.05)); }

    if (note.type === "bend") {
      const targetMidi = midi + (note.semitones || 0);
      const targetFreq = midiToFreq(targetMidi);
      const riseAt = t0 + Math.max(0.01, (note.riseFraction || 0.3) * durSec);
      osc.frequency.setValueAtTime(freq, t0);
      osc.frequency.linearRampToValueAtTime(targetFreq, riseAt);
      osc.frequency.setValueAtTime(targetFreq, noteEnd);
    } else if (note.type === "slide") {
      const targetMidi = pitchForFret(track, note, transposeSemis, note.targetFret);
      const targetFreq = midiToFreq(targetMidi);
      osc.frequency.setValueAtTime(freq, t0);
      osc.frequency.linearRampToValueAtTime(targetFreq, noteEnd);
    } else {
      osc.frequency.setValueAtTime(freq, t0);
    }

    if (technique === "vibrato") {
      const lfo = ctx.createOscillator();
      lfo.frequency.value = 6;
      const lfoGain = ctx.createGain();
      lfoGain.gain.value = freq * 0.02;
      lfo.connect(lfoGain).connect(osc.frequency);
      lfo.start(t0);
      lfo.stop(noteEnd + release + 0.05);
      state.liveNodes.push(lfo);
    }

    scheduleEnvelope(gainNode.gain, t0, voice.attack, decay, sustain, noteEnd, release, peak);
    osc.start(t0);
    osc.stop(noteEnd + release + 0.05);
    state.liveNodes.push(osc);
  }

  function pitchForFret(track, note, transposeSemis, fret) {
    const strings = track.def.tuning.strings;
    const open = strings[note.string];
    const capo = track.def.capo || 0;
    return open + fret + capo + transposeSemis;
  }

  function playDrum(piece, t0, durSec, velocity, targetGain) {
    const vel = velocity != null ? velocity : 0.8;
    const g = ctx.createGain();
    g.connect(targetGain);

    function noiseHit(hp, lp, dur, peak) {
      const src = ctx.createBufferSource();
      src.buffer = getNoiseBuffer();
      const filt1 = ctx.createBiquadFilter();
      filt1.type = "highpass"; filt1.frequency.value = hp;
      const filt2 = ctx.createBiquadFilter();
      filt2.type = "lowpass"; filt2.frequency.value = lp;
      const gg = ctx.createGain();
      src.connect(filt1).connect(filt2).connect(gg).connect(g);
      gg.gain.setValueAtTime(peak, t0);
      gg.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
      src.start(t0);
      src.stop(t0 + dur + 0.02);
      state.liveNodes.push(src);
    }
    function tone(freqStart, freqEnd, dur, peak) {
      const osc = ctx.createOscillator();
      osc.type = "sine";
      osc.frequency.setValueAtTime(freqStart, t0);
      osc.frequency.exponentialRampToValueAtTime(Math.max(20, freqEnd), t0 + dur);
      const gg = ctx.createGain();
      osc.connect(gg).connect(g);
      gg.gain.setValueAtTime(peak, t0);
      gg.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
      osc.start(t0);
      osc.stop(t0 + dur + 0.02);
      state.liveNodes.push(osc);
    }

    switch (piece) {
      case "kick": tone(150, 45, 0.16, 0.9 * vel); break;
      case "snare": noiseHit(1200, 6000, 0.14, 0.7 * vel); tone(200, 120, 0.08, 0.35 * vel); break;
      case "hiHatClosed": noiseHit(7000, 16000, 0.045, 0.35 * vel); break;
      case "ride": noiseHit(5000, 12000, 0.28, 0.28 * vel); break;
      case "tomMid": tone(220, 150, 0.22, 0.6 * vel); break;
      case "tomLow": tone(150, 95, 0.26, 0.65 * vel); break;
      default: noiseHit(2000, 8000, 0.1, 0.4 * vel);
    }
  }

  function scheduleEvent(track, event, t0, secondsPerBeat, transposeSemis) {
    const durSec = Math.max(0.03, event.durationBeats * secondsPerBeat);
    if (event.type === "note" || event.type === "bend" || event.type === "slide") {
      playPitchedNote(track, event, t0, durSec, transposeSemis, track.gainNode);
    } else if (event.type === "chord") {
      const spread = event.strumSpreadBeats || 0;
      event.notes.forEach((n, i) => {
        const nt0 = t0 + i * spread * secondsPerBeat;
        const ndur = Math.max(0.03, n.durationBeats * secondsPerBeat);
        playPitchedNote(track, n, nt0, ndur, transposeSemis, track.gainNode);
      });
    } else if (event.type === "drum") {
      playDrum(event.piece, t0, durSec, event.velocity, track.gainNode);
    } else if (event.type === "rest") {
      // silêncio: nada a agendar
    }
  }

  // ---- Metrônomo ----
  function scheduleMetronome(fromBeat, toBeat, secondsPerBeat, t0AtFromBeat) {
    if (!state.metronomeOn) return;
    const beatsPerBar = state.song.timeSignature.beatsPerBar;
    const firstBeat = Math.ceil(fromBeat);
    for (let b = firstBeat; b <= toBeat; b++) {
      const t = t0AtFromBeat + (b - fromBeat) * secondsPerBeat;
      const accent = ((b % beatsPerBar) + beatsPerBar) % beatsPerBar === 0;
      const osc = ctx.createOscillator();
      osc.type = "square";
      osc.frequency.value = accent ? 1500 : 1000;
      const gg = ctx.createGain();
      osc.connect(gg).connect(masterGain);
      gg.gain.setValueAtTime(accent ? 0.18 : 0.11, t);
      gg.gain.exponentialRampToValueAtTime(0.0001, t + 0.05);
      osc.start(t);
      osc.stop(t + 0.06);
      state.liveNodes.push(osc);
    }
  }

  // ---- Transporte ----
  function stopAllNodes() {
    state.liveNodes.forEach((n) => { try { n.stop(); } catch (e) { /* já parado */ } });
    state.liveNodes = [];
  }

  function currentBeat() {
    if (!state.isPlaying) return state.startBeat;
    const elapsed = ctx.currentTime - state.startCtxTime;
    return state.startBeat + Math.max(0, elapsed) / state.secondsPerBeat;
  }

  function play() {
    if (!state.song || state.isPlaying) return;
    if (ctx.state === "suspended") ctx.resume();
    state.isPlaying = true;
    state.speed = parseFloat(document.getElementById("speed-select").value) || 1;
    state.secondsPerBeat = 60 / (state.song.tempo * state.speed);

    const fromBeat = state.startBeat;
    let leadIn = SCHEDULE_LEAD;
    if (state.countInOn) {
      const countBeats = 3;
      const countSecondsPerBeat = 60 / state.song.tempo;
      for (let i = 0; i < countBeats; i++) {
        const t = ctx.currentTime + leadIn + i * countSecondsPerBeat;
        const osc = ctx.createOscillator();
        osc.type = "square";
        osc.frequency.value = 1400;
        const gg = ctx.createGain();
        osc.connect(gg).connect(masterGain);
        gg.gain.setValueAtTime(0.2, t);
        gg.gain.exponentialRampToValueAtTime(0.0001, t + 0.06);
        osc.start(t); osc.stop(t + 0.07);
        state.liveNodes.push(osc);
      }
      leadIn += countBeats * countSecondsPerBeat;
    }

    const t0 = ctx.currentTime + leadIn;
    state.startCtxTime = t0;

    state.tracks.forEach((track) => {
      track.def.events.forEach((event) => {
        if (event.startBeat < fromBeat) return; // notas já em andamento no ponto de seek não são retomadas
        const t = t0 + (event.startBeat - fromBeat) * state.secondsPerBeat;
        scheduleEvent(track, event, t, state.secondsPerBeat, state.transpose);
      });
    });
    scheduleMetronome(fromBeat, state.songEndBeat, state.secondsPerBeat, t0);

    document.getElementById("btn-play").textContent = "⏸ Pausar";
    tick();
  }

  function pause() {
    if (!state.isPlaying) return;
    state.startBeat = currentBeat();
    state.isPlaying = false;
    stopAllNodes();
    document.getElementById("btn-play").textContent = "▶ Tocar";
    if (state.rafId) cancelAnimationFrame(state.rafId);
  }

  function stopPlayback() {
    state.isPlaying = false;
    stopAllNodes();
    state.startBeat = 0;
    document.getElementById("btn-play") && (document.getElementById("btn-play").textContent = "▶ Tocar");
    if (state.rafId) cancelAnimationFrame(state.rafId);
    if (state.song) { updateTimeLabel(0); document.getElementById("scrubber").value = 0; drawTab(); }
  }

  function seekToBeat(beat) {
    const wasPlaying = state.isPlaying;
    if (wasPlaying) { stopAllNodes(); state.isPlaying = false; }
    state.startBeat = Math.max(0, Math.min(beat, state.songEndBeat));
    updateTimeLabel(state.startBeat);
    drawTab();
    if (wasPlaying) play();
  }

  function beatsToClock(beat) {
    const seconds = beat * state.secondsPerBeat;
    const m = Math.floor(seconds / 60);
    const s = Math.floor(seconds % 60);
    return `${m}:${String(s).padStart(2, "0")}`;
  }

  function updateTimeLabel(beat) {
    document.getElementById("time-label").textContent = `${beatsToClock(beat)} / ${beatsToClock(state.songEndBeat)}`;
  }

  function tick() {
    if (!state.isPlaying) return;
    const beat = currentBeat();
    if (beat >= state.songEndBeat) { stopPlayback(); return; }
    updateTimeLabel(beat);
    document.getElementById("scrubber").value = String(Math.round((beat / Math.max(1, state.songEndBeat)) * 1000));
    drawTab(beat);
    state.rafId = requestAnimationFrame(tick);
  }

  // ---- Tablatura (canvas) ----
  const PX_PER_BEAT = 26;
  const LANE_HEIGHT = 20;

  function renderTrackTabs() {
    const el = document.getElementById("tab-track-tabs");
    el.innerHTML = "";
    state.tracks.forEach((t) => {
      const b = document.createElement("button");
      b.className = "tab-tab-btn" + (t.def.id === state.selectedTrackId ? " active" : "");
      b.textContent = t.def.name;
      b.addEventListener("click", () => { state.selectedTrackId = t.def.id; renderTrackTabs(); renderMixer(); drawTab(); });
      el.appendChild(b);
    });
  }

  function drawTab(playheadBeat) {
    const canvas = document.getElementById("tab-canvas");
    if (!state.song) return;
    const track = state.tracks.find((t) => t.def.id === state.selectedTrackId);
    if (!track) return;

    const isDrums = track.def.instrument === "drums";
    const lanes = isDrums ? DRUM_LANES : track.def.tuning.strings.map((_, i) => i).reverse();
    const width = Math.max(canvas.parentElement.clientWidth, PX_PER_BEAT * state.songEndBeat + 40);
    const height = lanes.length * LANE_HEIGHT + 20;
    canvas.width = width;
    canvas.height = height;
    const g = canvas.getContext("2d");
    g.clearRect(0, 0, width, height);

    g.strokeStyle = "#2c303c";
    g.fillStyle = "#9096a6";
    g.font = "10px monospace";
    lanes.forEach((lane, row) => {
      const y = 12 + row * LANE_HEIGHT;
      g.beginPath(); g.moveTo(4, y); g.lineTo(width - 4, y); g.stroke();
      const label = isDrums ? lane : String(track.def.tuning.strings[lane]);
      g.fillText(isDrums ? label.slice(0, 4) : "", 4, y - 4);
    });

    function laneRow(event) {
      if (isDrums) return DRUM_LANES.indexOf(event.piece);
      return lanes.indexOf(event.string);
    }

    track.def.events.forEach((event) => {
      const x = 8 + event.startBeat * PX_PER_BEAT;
      if (event.type === "chord") {
        event.notes.forEach((n) => drawNoteGlyph(g, x, laneRow(n), n.fret, track.color));
      } else if (event.type === "drum") {
        const row = laneRow(event);
        if (row < 0) return;
        const y = 12 + row * LANE_HEIGHT;
        g.fillStyle = track.color;
        g.beginPath(); g.arc(x, y, 3, 0, Math.PI * 2); g.fill();
      } else {
        const row = laneRow(event);
        if (row < 0) return;
        drawNoteGlyph(g, x, row, event.fret, track.color, event.type);
      }
    });

    if (playheadBeat != null) {
      const px = 8 + playheadBeat * PX_PER_BEAT;
      g.strokeStyle = "#5cc8ff";
      g.lineWidth = 2;
      g.beginPath(); g.moveTo(px, 0); g.lineTo(px, height); g.stroke();
      g.lineWidth = 1;
      const wrap = canvas.parentElement;
      const margin = 120;
      if (px < wrap.scrollLeft + margin || px > wrap.scrollLeft + wrap.clientWidth - margin) {
        wrap.scrollLeft = Math.max(0, px - wrap.clientWidth / 2);
      }
    }
  }

  function drawNoteGlyph(g, x, row, fret, color, type) {
    if (row < 0) return;
    const y = 12 + row * LANE_HEIGHT;
    g.fillStyle = "#0e1015";
    g.fillRect(x - 7, y - 7, 14, 12);
    g.fillStyle = type === "bend" || type === "slide" ? "#ff7a5c" : color;
    g.font = "10px monospace";
    g.textAlign = "center";
    g.fillText(String(fret), x, y + 2);
    g.textAlign = "left";
  }

  document.getElementById("tab-canvas").addEventListener("click", (ev) => {
    if (!state.song) return;
    const rect = ev.target.getBoundingClientRect();
    const x = ev.clientX - rect.left;
    const beat = Math.max(0, (x - 8) / PX_PER_BEAT);
    seekToBeat(beat);
  });

  window.addEventListener("resize", () => drawTab(state.isPlaying ? currentBeat() : undefined));

  // ---- Ligações de UI ----
  document.getElementById("btn-play").addEventListener("click", () => { state.isPlaying ? pause() : play(); });
  document.getElementById("btn-stop").addEventListener("click", stopPlayback);
  document.getElementById("chk-metronome").addEventListener("change", (e) => { state.metronomeOn = e.target.checked; });
  document.getElementById("chk-countin").addEventListener("change", (e) => { state.countInOn = e.target.checked; });
  document.getElementById("speed-select").addEventListener("change", () => {
    if (state.isPlaying) { const b = currentBeat(); pause(); state.startBeat = b; play(); }
  });
  document.getElementById("btn-transpose-up").addEventListener("click", () => {
    state.transpose = Math.min(12, state.transpose + 1);
    document.getElementById("transpose-label").textContent = (state.transpose > 0 ? "+" : "") + state.transpose;
    if (state.isPlaying) { const b = currentBeat(); pause(); state.startBeat = b; play(); }
  });
  document.getElementById("btn-transpose-down").addEventListener("click", () => {
    state.transpose = Math.max(-12, state.transpose - 1);
    document.getElementById("transpose-label").textContent = (state.transpose > 0 ? "+" : "") + state.transpose;
    if (state.isPlaying) { const b = currentBeat(); pause(); state.startBeat = b; play(); }
  });
  document.getElementById("scrubber").addEventListener("input", (e) => {
    if (!state.song) return;
    const beat = (parseInt(e.target.value, 10) / 1000) * state.songEndBeat;
    seekToBeat(beat);
  });

  window.__player = { getContext: () => ctx, getState: () => state };
})();

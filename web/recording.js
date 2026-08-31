// Grava o áudio do player (e, se autorizado, o microfone) enquanto você toca junto.
(function () {
  "use strict";

  let recorder = null;
  let chunks = [];
  let micStream = null;

  async function startRecording() {
    const playerDest = window.__playerRecordingDestination;
    if (!playerDest) return;

    const combined = new MediaStream();
    playerDest.stream.getAudioTracks().forEach((t) => combined.addTrack(t));

    try {
      micStream = await navigator.mediaDevices.getUserMedia({ audio: true });
      micStream.getAudioTracks().forEach((t) => combined.addTrack(t));
    } catch (err) {
      console.warn("Microfone não autorizado, gravando só o áudio do player.", err);
      micStream = null;
    }

    const mimeType = ["audio/webm;codecs=opus", "audio/webm", "audio/ogg;codecs=opus"]
      .find((m) => window.MediaRecorder && MediaRecorder.isTypeSupported(m)) || "";

    chunks = [];
    recorder = mimeType ? new MediaRecorder(combined, { mimeType }) : new MediaRecorder(combined);
    recorder.ondataavailable = (e) => { if (e.data && e.data.size > 0) chunks.push(e.data); };
    recorder.onstop = () => {
      const blob = new Blob(chunks, { type: recorder.mimeType || "audio/webm" });
      const url = URL.createObjectURL(blob);
      const song = window.__player ? window.__player.getState().song : null;
      const name = (song ? song.title.replace(/[^a-z0-9]+/gi, "-").toLowerCase() : "gravacao") + ".webm";

      const a = document.createElement("a");
      a.href = url;
      a.download = name;
      a.textContent = `Baixar gravação (${name})`;
      a.style.cssText = "display:block;margin-top:10px;color:var(--accent,#5cc8ff);";
      const card = document.getElementById("btn-record").closest(".card");
      const old = card.querySelector(".recording-download");
      if (old) old.remove();
      a.className = "recording-download";
      card.appendChild(a);

      if (micStream) micStream.getTracks().forEach((t) => t.stop());
    };
    recorder.start();
  }

  function stopRecording() {
    if (recorder && recorder.state !== "inactive") recorder.stop();
    recorder = null;
  }

  document.getElementById("btn-record").addEventListener("click", async (e) => {
    const btn = e.currentTarget;
    const isRecording = btn.classList.contains("recording");
    if (isRecording) {
      stopRecording();
      btn.classList.remove("recording");
      btn.textContent = "⏺ Gravar";
    } else {
      await startRecording();
      btn.classList.add("recording");
      btn.textContent = "⏹ Gravando…";
    }
  });
})();

import Foundation

/// Installs and runs a local Chatterbox TTS server (Resemble AI's open-source
/// model). Mirrors `KokoroServer` but lives under `~/.narrateify/chatterbox`:
///   • `venv/`               — a Python virtualenv with `chatterbox-tts`
///   • `chatterbox_server.py`— a tiny stdlib HTTP wrapper (written by this class)
///   • `.installed`          — marker written after a successful pip install
///
/// Chatterbox is multilingual (23 languages) and heavier than Kokoro: the
/// install pulls PyTorch + several GB of weights, and the model load on first
/// start takes longer, so the health budget is generous.
@MainActor
final class ChatterboxServer: ObservableObject {

    enum Status: Equatable {
        case notInstalled
        case installing
        case stopped
        case starting
        case running
        case failed(String)
    }

    @Published private(set) var status: Status
    @Published private(set) var log: String = ""
    /// Bytes currently used on disk by this model (venv + weights). Refreshed
    /// on demand via `refreshDiskUsage()`.
    @Published private(set) var diskUsage: Int64 = 0

    /// Roughly how much the install downloads, and how it performs — surfaced
    /// in Settings so the user knows what they're getting into.
    static let estimatedDownload = "~6 GB"
    static let performanceNote =
        "Compute-heavy (0.5B params). Best on Apple-silicon GPU (MPS); noticeably "
        + "slower on CPU and uses several GB of RAM. Higher quality, expressive, "
        + "and multilingual (23 languages)."

    let port = 8766
    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    private let baseDir: URL
    private var venvPython: URL { baseDir.appendingPathComponent("venv/bin/python3") }
    private var serverScript: URL { baseDir.appendingPathComponent("chatterbox_server.py") }
    private var marker: URL { baseDir.appendingPathComponent(".installed") }
    private var process: Process?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        baseDir = home.appendingPathComponent(".narrateify/chatterbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        status = FileManager.default.fileExists(atPath: baseDir.appendingPathComponent(".installed").path)
            ? .stopped : .notInstalled
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: marker.path)
    }

    // MARK: Install

    /// Creates the venv and pip-installs `chatterbox-tts`. Downloads PyTorch +
    /// model weights (several GB), so this can take a while on first run.
    func install() {
        guard status != .installing else { return }
        status = .installing
        log = ""
        appendLog("Installing Chatterbox… this downloads PyTorch + model weights and can take several minutes.\n")

        do {
            try Self.serverScriptSource.write(to: serverScript, atomically: true, encoding: .utf8)
        } catch {
            fail("Couldn't write server script: \(error.localizedDescription)")
            return
        }

        // PIP_USER=0 / PYTHONNOUSERSITE neutralize Anaconda/global pip configs
        // that force `--user`, which is illegal inside a virtualenv.
        // Chatterbox was developed on Python 3.11; prefer it when available.
        let script = """
        set -e
        export PIP_USER=0
        export PYTHONNOUSERSITE=1
        export PIP_REQUIRE_VIRTUALENV=0
        export HF_HOME="\(baseDir.path)/hf"
        export TORCH_HOME="\(baseDir.path)/torch"
        cd "\(baseDir.path)"
        PY="$(command -v python3.11 || command -v python3 || true)"
        if [ -z "$PY" ]; then echo "ERROR: python3 not found on PATH"; exit 1; fi
        echo "Using $($PY --version) at $PY"
        "$PY" -m venv venv
        ./venv/bin/python -m pip install --upgrade pip
        ./venv/bin/python -m pip install chatterbox-tts soundfile
        # Chatterbox's `perth` watermarker imports `pkg_resources`, which was
        # removed from setuptools 81+. Pin an older setuptools so it's available.
        ./venv/bin/python -m pip install "setuptools<81"
        echo "INSTALL_OK"
        """

        runShell(script) { [weak self] ok in
            guard let self else { return }
            if ok {
                FileManager.default.createFile(atPath: self.marker.path, contents: Data())
                self.appendLog("\n✅ Chatterbox installed. You can now start the server.\n")
                self.status = .stopped
            } else {
                self.fail("Installation failed — see the log above.")
            }
        }
    }

    // MARK: Start / stop

    func start() {
        guard isInstalled else { fail("Chatterbox isn't installed yet."); return }
        guard process == nil else { return }
        status = .starting
        appendLog("Starting Chatterbox server on port \(port)… (first start loads the model — give it a minute)\n")

        // Refresh the embedded server script so improvements ship without a
        // full reinstall.
        try? Self.serverScriptSource.write(to: serverScript, atomically: true, encoding: .utf8)

        // Clear any orphan from a previous run that may still hold the port.
        LocalServerSupport.killProcesses(onPort: port)

        let p = Process()
        p.executableURL = venvPython
        p.arguments = [serverScript.path, "--port", "\(port)"]
        var env = ProcessInfo.processInfo.environment
        env["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"   // Apple-silicon GPU fallback
        // Keep all downloaded weights under ~/.narrateify so disk accounting is
        // exact and uninstall is complete.
        env["HF_HOME"] = baseDir.appendingPathComponent("hf").path
        env["TORCH_HOME"] = baseDir.appendingPathComponent("torch").path
        // Neutralize Anaconda/global configs that force `--user`, in case any
        // dependency lazily pip-installs something at runtime.
        env["PIP_USER"] = "0"
        env["PYTHONNOUSERSITE"] = "1"
        env["PIP_REQUIRE_VIRTUALENV"] = "0"
        // Avoid HF tokenizers fork warnings/deadlocks in the threaded server.
        env["TOKENIZERS_PARALLELISM"] = "false"
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.appendLog(text) }
        }
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.process = nil
                // Don't clobber a load-failure status with a plain "stopped".
                if case .failed = self.status {} else { self.status = .stopped }
                self.appendLog("Chatterbox server stopped.\n")
            }
        }

        do {
            try p.run()
            process = p
            Task { await waitForHealth() }
        } catch {
            fail("Couldn't launch server: \(error.localizedDescription)")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        status = .stopped
    }

    // MARK: Uninstall / disk usage

    /// Stops the server and deletes the venv + downloaded weights, reclaiming
    /// all disk space. Returns the model to the "not installed" state.
    func uninstall() {
        stop()
        LocalServerSupport.killProcesses(onPort: port)
        try? FileManager.default.removeItem(at: baseDir)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        log = ""
        diskUsage = 0
        status = .notInstalled
        appendLog("Removed local files — Chatterbox uninstalled.\n")
    }

    /// Recomputes `diskUsage` off the main thread.
    func refreshDiskUsage() {
        let dir = baseDir
        Task.detached(priority: .utility) {
            let size = LocalServerSupport.directorySize(at: dir)
            await MainActor.run { self.diskUsage = size }
        }
    }

    /// Poll `/health` until the model has loaded. Chatterbox's first start
    /// downloads several GB and loads a large model, so budget generously.
    private func waitForHealth() async {
        let url = baseURL.appendingPathComponent("health")
        for _ in 0..<300 {                      // ~5 min budget
            if process == nil { return }
            if let (data, resp) = try? await URLSession.shared.data(from: url),
               let http = resp as? HTTPURLResponse {
                if http.statusCode == 200 {
                    status = .running
                    appendLog("✅ Chatterbox server is ready.\n")
                    return
                }
                // Server is up but reported a fatal load error — surface it
                // instead of polling forever.
                if let body = try? JSONDecoder().decode([String: String].self, from: data),
                   body["status"] == "error" {
                    let msg = body["error"] ?? "model failed to load"
                    appendLog("❌ Model load failed: \(msg)\n")
                    status = .failed(msg)
                    process?.terminate()
                    process = nil
                    return
                }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        if process != nil { appendLog("Still waiting on the server (model may still be downloading)…\n") }
    }

    // MARK: Helpers

    private func appendLog(_ text: String) {
        log += text
        if log.count > 8000 { log = String(log.suffix(8000)) }   // keep it bounded
    }

    private func fail(_ message: String) {
        appendLog("❌ \(message)\n")
        status = .failed(message)
    }

    /// Runs a bash script, streaming combined output into `log`.
    private func runShell(_ script: String, completion: @escaping (Bool) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-lc", script]

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.appendLog(text) }
        }
        p.terminationHandler = { proc in
            let ok = proc.terminationStatus == 0
            Task { @MainActor in
                pipe.fileHandleForReading.readabilityHandler = nil
                completion(ok)
            }
        }
        do {
            try p.run()
        } catch {
            fail("Couldn't start install: \(error.localizedDescription)")
            completion(false)
        }
    }

    // MARK: Embedded server

    /// A minimal stdlib HTTP server wrapping Chatterbox's multilingual model.
    /// "voice" maps to a `language_id`; `exaggeration` / `cfg_weight` are the
    /// model's expressiveness knobs. Output is 24-ish kHz WAV (model.sr).
    private static let serverScriptSource = """
    import io, json, argparse, threading
    import numpy as np
    import soundfile as sf
    import torch
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    from chatterbox.mtl_tts import ChatterboxMultilingualTTS

    LANGUAGES = [
        "en", "ar", "da", "de", "el", "es", "fi", "fr", "he", "hi", "it",
        "ja", "ko", "ms", "nl", "no", "pl", "pt", "ru", "sv", "sw", "tr", "zh",
    ]

    model = None
    model_sr = 24000
    load_error = None

    def pick_device():
        try:
            if torch.backends.mps.is_available():
                return "mps"
        except Exception:
            pass
        return "cpu"

    DEVICE = "cpu"

    def actual_device(m):
        # Report where the model's weights really live, so the log proves
        # whether the GPU (mps) is in use rather than us merely asking for it.
        for name in ("t3", "s3gen", "ve"):
            sub = getattr(m, name, None)
            if sub is None:
                continue
            try:
                return str(next(sub.parameters()).device)
            except StopIteration:
                continue
        return str(getattr(m, "device", "unknown"))

    def load_model():
        global model, model_sr, DEVICE
        if model is not None:
            return model
        dev = pick_device()
        try:
            model = ChatterboxMultilingualTTS.from_pretrained(device=dev)
        except Exception as e:
            print("load on", dev, "failed:", e, "— falling back to cpu", flush=True)
            model = ChatterboxMultilingualTTS.from_pretrained(device="cpu")
        model_sr = int(getattr(model, "sr", 24000))
        DEVICE = actual_device(model)
        print("chatterbox model loaded on %s (sr=%d)" % (DEVICE, model_sr), flush=True)
        return model

    def free_cache():
        # Chatterbox doesn't release MPS memory between generations; left alone
        # it accumulates until macOS swaps and a request balloons to minutes.
        # Reclaiming the cache after each synth keeps timings consistent.
        try:
            if torch.backends.mps.is_available():
                torch.mps.empty_cache()
        except Exception:
            pass

    def synth(text, language_id, exaggeration, cfg_weight):
        import time
        m = load_model()
        t0 = time.time()
        try:
            wav = m.generate(text, language_id=language_id,
                             exaggeration=exaggeration, cfg_weight=cfg_weight)
        except TypeError:
            # Older/newer signatures may not accept the knobs.
            wav = m.generate(text, language_id=language_id)
        audio = wav.detach().cpu().numpy().squeeze()
        dur = len(audio) / float(model_sr) if model_sr else 0.0
        elapsed = time.time() - t0
        print("synth on %s: %.1fs for %.1fs audio (%d chars)"
              % (DEVICE, elapsed, dur, len(text)), flush=True)
        buf = io.BytesIO()
        sf.write(buf, audio, model_sr, format="WAV")
        free_cache()
        return buf.getvalue()

    class Handler(BaseHTTPRequestHandler):
        def _send(self, code, body=b"", ctype="application/octet-stream"):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if body:
                self.wfile.write(body)

        def do_GET(self):
            if self.path == "/health":
                if model is not None:
                    self._send(200, b'{"status":"ok"}', "application/json")
                elif load_error is not None:
                    self._send(503, json.dumps({"status": "error", "error": load_error}).encode(),
                               "application/json")
                else:
                    self._send(503, b'{"status":"loading"}', "application/json")
            elif self.path.startswith("/v1/audio/voices") or self.path.startswith("/v1/voices"):
                self._send(200, json.dumps({"voices": LANGUAGES}).encode(), "application/json")
            else:
                self._send(404)

        def do_POST(self):
            if self.path != "/v1/audio/speech":
                self._send(404)
                return
            if model is None:
                msg = load_error or "model is still loading"
                self._send(503, json.dumps({"error": msg}).encode(), "application/json")
                return
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length) if length else b"{}"
            try:
                payload = json.loads(raw)
            except Exception:
                payload = {}
            text = payload.get("input", "")
            voice = payload.get("voice", "en") or "en"
            if voice not in LANGUAGES:
                voice = "en"
            exaggeration = float(payload.get("exaggeration", 0.5))
            cfg_weight = float(payload.get("cfg_weight", 0.5))
            try:
                wav = synth(text, voice, exaggeration, cfg_weight)
                if not wav:
                    self._send(500, b'{"error":"empty audio"}', "application/json")
                else:
                    self._send(200, wav, "audio/wav")
            except Exception as e:
                self._send(500, json.dumps({"error": str(e)}).encode(), "application/json")

        def log_message(self, *args):
            return

    def warmup():
        # Load the model in the background so /health is reachable (and can
        # report a failure) instead of the port being dead during the load.
        global load_error
        try:
            load_model()
        except Exception as e:
            load_error = str(e)
            print("model load failed:", e, flush=True)

    def main():
        parser = argparse.ArgumentParser()
        parser.add_argument("--port", type=int, default=8766)
        args = parser.parse_args()
        server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
        print("chatterbox server listening on port", args.port, flush=True)
        threading.Thread(target=warmup, daemon=True).start()
        server.serve_forever()

    if __name__ == "__main__":
        main()
    """
}

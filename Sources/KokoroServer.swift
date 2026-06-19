import Foundation

/// Installs and runs a local Kokoro TTS server. Everything lives under
/// `~/.narrateify/kokoro`:
///   • `venv/`             — a Python virtualenv with `kokoro` + `soundfile`
///   • `kokoro_server.py`  — a tiny stdlib HTTP wrapper (written by this class)
///   • `.installed`        — marker written after a successful pip install
///
/// The app never bundles Python; it shells out to the system `python3` to build
/// the venv, then launches the server as a child process.
@MainActor
final class KokoroServer: ObservableObject {

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
    static let estimatedDownload = "~2.5 GB"
    static let performanceNote =
        "Fast & lightweight (82M params). Runs smoothly on CPU; near-instant on "
        + "Apple silicon. Great default for quick, low-cost narration."

    let port = 8765
    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    private let baseDir: URL
    private var venvPython: URL { baseDir.appendingPathComponent("venv/bin/python3") }
    private var serverScript: URL { baseDir.appendingPathComponent("kokoro_server.py") }
    private var marker: URL { baseDir.appendingPathComponent(".installed") }
    private var process: Process?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        baseDir = home.appendingPathComponent(".narrateify/kokoro", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        status = FileManager.default.fileExists(atPath: baseDir.appendingPathComponent(".installed").path)
            ? .stopped : .notInstalled
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: marker.path)
    }

    // MARK: Install

    /// Creates the venv and pip-installs Kokoro. Downloads PyTorch + model
    /// weights, so this can take several minutes on first run.
    func install() {
        guard status != .installing else { return }
        status = .installing
        log = ""
        appendLog("Installing Kokoro… this downloads PyTorch and can take a few minutes.\n")

        // Write the server script up front so it's ready once deps are in place.
        do {
            try Self.serverScriptSource.write(to: serverScript, atomically: true, encoding: .utf8)
        } catch {
            fail("Couldn't write server script: \(error.localizedDescription)")
            return
        }

        // PIP_USER=0 / PYTHONNOUSERSITE neutralize Anaconda/global pip configs
        // that force `--user`, which is illegal inside a virtualenv.
        let script = """
        set -e
        export PIP_USER=0
        export PYTHONNOUSERSITE=1
        export PIP_REQUIRE_VIRTUALENV=0
        export HF_HOME="\(baseDir.path)/hf"
        export TORCH_HOME="\(baseDir.path)/torch"
        cd "\(baseDir.path)"
        PY="$(command -v python3 || true)"
        if [ -z "$PY" ]; then echo "ERROR: python3 not found on PATH"; exit 1; fi
        echo "Using $($PY --version) at $PY"
        "$PY" -m venv venv
        ./venv/bin/python -m pip install --upgrade pip
        ./venv/bin/python -m pip install "kokoro>=0.9.4" soundfile numpy
        echo "Fetching the English G2P model (en_core_web_sm)…"
        ./venv/bin/python -m spacy download en_core_web_sm || echo "(spacy model will download on first use)"
        echo "INSTALL_OK"
        """

        runShell(script) { [weak self] ok in
            guard let self else { return }
            if ok {
                FileManager.default.createFile(atPath: self.marker.path, contents: Data())
                self.appendLog("\n✅ Kokoro installed. You can now start the server.\n")
                self.status = .stopped
            } else {
                self.fail("Installation failed — see the log above.")
            }
        }
    }

    // MARK: Start / stop

    func start() {
        guard isInstalled else { fail("Kokoro isn't installed yet."); return }
        guard process == nil else { return }
        status = .starting
        appendLog("Starting Kokoro server on port \(port)…\n")

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
        // Kokoro's English G2P (misaki) may pip-install the spaCy model at
        // runtime; neutralize Anaconda/global configs that force `--user`.
        env["PIP_USER"] = "0"
        env["PYTHONNOUSERSITE"] = "1"
        env["PIP_REQUIRE_VIRTUALENV"] = "0"
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
                self?.process = nil
                self?.status = .stopped
                self?.appendLog("Kokoro server stopped.\n")
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
        appendLog("Removed local files — Kokoro uninstalled.\n")
    }

    /// Recomputes `diskUsage` off the main thread.
    func refreshDiskUsage() {
        let dir = baseDir
        Task.detached(priority: .utility) {
            let size = LocalServerSupport.directorySize(at: dir)
            await MainActor.run { self.diskUsage = size }
        }
    }

    /// Poll `/health` until the model has loaded (first launch downloads weights).
    private func waitForHealth() async {
        let url = baseURL.appendingPathComponent("health")
        for _ in 0..<90 {                       // ~90s budget
            if process == nil { return }
            if let (_, resp) = try? await URLSession.shared.data(from: url),
               (resp as? HTTPURLResponse)?.statusCode == 200 {
                status = .running
                appendLog("✅ Kokoro server is ready.\n")
                return
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

    /// A minimal stdlib HTTP server wrapping `kokoro.KPipeline`. No web
    /// framework — only the venv's `kokoro`, `soundfile`, and `numpy`.
    private static let serverScriptSource = """
    import io, json, argparse
    import numpy as np
    import soundfile as sf
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    from kokoro import KPipeline

    VOICES = [
        "af_heart", "af_bella", "af_nicole", "af_sarah", "af_sky", "af_aoede",
        "am_adam", "am_michael", "am_fenrir", "am_puck",
        "bf_emma", "bf_isabella", "bm_george", "bm_lewis",
    ]

    pipelines = {}

    def get_pipeline(lang_code):
        if lang_code not in pipelines:
            pipelines[lang_code] = KPipeline(lang_code=lang_code)
        return pipelines[lang_code]

    def synth(text, voice, speed):
        lang = voice[0] if voice else "a"
        pipe = get_pipeline(lang)
        parts = []
        for item in pipe(text, voice=voice, speed=speed):
            parts.append(item[2])
        if not parts:
            return b""
        audio = np.concatenate(parts)
        buf = io.BytesIO()
        sf.write(buf, audio, 24000, format="WAV")
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
                self._send(200, b'{"status":"ok"}', "application/json")
            elif self.path.startswith("/v1/audio/voices") or self.path.startswith("/v1/voices"):
                self._send(200, json.dumps({"voices": VOICES}).encode(), "application/json")
            else:
                self._send(404)

        def do_POST(self):
            if self.path != "/v1/audio/speech":
                self._send(404)
                return
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length) if length else b"{}"
            try:
                payload = json.loads(raw)
            except Exception:
                payload = {}
            text = payload.get("input", "")
            voice = payload.get("voice", "af_heart")
            speed = float(payload.get("speed", 1.0))
            try:
                wav = synth(text, voice, speed)
                if not wav:
                    self._send(500, b'{"error":"empty audio"}', "application/json")
                else:
                    self._send(200, wav, "audio/wav")
            except Exception as e:
                self._send(500, json.dumps({"error": str(e)}).encode(), "application/json")

        def log_message(self, *args):
            return

    def main():
        parser = argparse.ArgumentParser()
        parser.add_argument("--port", type=int, default=8765)
        args = parser.parse_args()
        try:
            get_pipeline("a")   # warm up American English
        except Exception as e:
            print("warmup failed:", e, flush=True)
        server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
        print("kokoro server ready on port", args.port, flush=True)
        server.serve_forever()

    if __name__ == "__main__":
        main()
    """
}

import Foundation

/// Shared helpers for the local TTS servers (Kokoro / Chatterbox): on-disk size
/// accounting and orphan-process cleanup.
enum LocalServerSupport {

    /// Total allocated size on disk of everything under `url`, in bytes.
    static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(at: url,
                                             includingPropertiesForKeys: Array(keys),
                                             options: [],
                                             errorHandler: nil) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Human-readable byte size, e.g. "2.4 GB".
    static func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .file
        return f.string(fromByteCount: max(0, bytes))
    }

    /// Bash snippet that sets `$PY` to a Python interpreter whose version is one
    /// of `versions` (e.g. ["3.12", "3.11", "3.10"], in order of preference).
    ///
    /// Apps launched from Finder don't inherit the user's shell PATH, so a bare
    /// `python3` usually resolves to macOS's /usr/bin/python3 (3.9) — too old
    /// for Kokoro/Chatterbox. We search the usual install locations (Homebrew,
    /// python.org, pyenv, PATH) and, if nothing compatible exists, bootstrap a
    /// standalone `uv` and a managed CPython into `baseDir`, so a brand-new Mac
    /// with no developer tools still installs cleanly and uninstall stays
    /// complete. /usr/bin/python3 is never probed: on a Mac without the Command
    /// Line Tools it pops up an "install developer tools" dialog.
    static func pythonResolverScript(baseDir: URL, versions: [String]) -> String {
        let versionList = versions.joined(separator: " ")
        let fallback = versions.first ?? "3.12"
        let allowed = versions.map { "'\($0)'" }.joined(separator: ",")
        return """
        export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.pyenv/shims:$PATH"
        BASE="\(baseDir.path)"
        py_ok() {
          [ -n "$1" ] && [ -x "$1" ] && [ "$1" != "/usr/bin/python3" ] || return 1
          "$1" -c "import sys, venv, ensurepip; sys.exit(0 if '%d.%d' % sys.version_info[:2] in (\(allowed)) else 1)" >/dev/null 2>&1
        }
        PY=""
        for v in \(versionList); do
          for c in "$(command -v python$v 2>/dev/null || true)" \\
                   "/opt/homebrew/bin/python$v" "/usr/local/bin/python$v" \\
                   "/Library/Frameworks/Python.framework/Versions/$v/bin/python$v" \\
                   $(ls -d "$HOME"/.pyenv/versions/$v*/bin/python$v 2>/dev/null || true) \\
                   $(ls -d "$BASE"/python/cpython-$v*/bin/python$v 2>/dev/null || true); do
            if py_ok "$c"; then PY="$c"; break 2; fi
          done
        done
        if [ -z "$PY" ] && py_ok "$(command -v python3 2>/dev/null || true)"; then
          PY="$(command -v python3)"
        fi
        if [ -z "$PY" ]; then
          echo "No compatible Python (\(versions.joined(separator: "/"))) found — downloading a private Python \(fallback)…"
          UV="$(command -v uv 2>/dev/null || true)"
          if [ -z "$UV" ]; then
            UV="$BASE/uv/uv"
            if [ ! -x "$UV" ]; then
              curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$BASE/uv" UV_NO_MODIFY_PATH=1 INSTALLER_NO_MODIFY_PATH=1 sh
            fi
          fi
          UV_PYTHON_INSTALL_DIR="$BASE/python" UV_PYTHON_BIN_DIR="$BASE/python/bin" "$UV" python install \(fallback)
          PY="$(ls -d "$BASE"/python/cpython-\(fallback)*/bin/python\(fallback) 2>/dev/null | head -1)"
          if ! py_ok "$PY"; then echo "ERROR: couldn't set up Python \(fallback)"; exit 1; fi
        fi
        echo "Using $("$PY" --version) at $PY"
        """
    }

    /// Best-effort kill of any process still listening on a TCP port — orphans
    /// left by a previous run that didn't shut down cleanly. Synchronous but
    /// quick; call off the main thread if you care about the few-ms cost.
    static func killProcesses(onPort port: Int) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        // Only the *listening* process: a bare `tcp:PORT` match also returns
        // clients — including this app, whose URLSession keeps keep-alive
        // connections to the local server — so we'd kill ourselves.
        let me = ProcessInfo.processInfo.processIdentifier
        p.arguments = ["-c", "lsof -ti tcp:\(port) -sTCP:LISTEN | grep -vx \(me) | xargs kill -9 2>/dev/null || true"]
        try? p.run()
        p.waitUntilExit()
    }
}

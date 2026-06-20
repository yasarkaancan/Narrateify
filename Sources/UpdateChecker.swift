import Foundation
import SwiftUI

/// Checks the project's GitHub Releases for a newer version. Compares the
/// running app's `CFBundleShortVersionString` against the latest release tag.
/// No third-party services — just the public GitHub API.
@MainActor
final class UpdateChecker: ObservableObject {

    /// The public repository, used for the API check and the "Releases" link.
    static let repo = "yasarkaancan/Narrateify"
    static var releasesURL: URL { URL(string: "https://github.com/\(repo)/releases")! }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL, download: URL?)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// True while the release DMG is downloading.
    @Published private(set) var isDownloading = false
    /// The latest release's `.dmg` asset, if any (set by `check`).
    private(set) var pendingDownload: URL?

    /// The running app's marketing version, e.g. "1.0".
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let prerelease: Bool
        let draft: Bool
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    /// Queries the latest release and updates `state`. Safe to call repeatedly.
    func check() async {
        state = .checking
        let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Narrateify", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                state = .failed("No response"); return
            }
            // 404 = the repo has no published releases yet.
            if http.statusCode == 404 {
                state = .upToDate; return
            }
            guard http.statusCode == 200 else {
                state = .failed("GitHub returned \(http.statusCode)"); return
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard !release.draft, !release.prerelease else { state = .upToDate; return }

            let latest = release.tag_name
            if Self.isNewer(latest, than: currentVersion),
               let link = URL(string: release.html_url) {
                let dmg = release.assets
                    .first { $0.name.lowercased().hasSuffix(".dmg") }
                    .flatMap { URL(string: $0.browser_download_url) }
                pendingDownload = dmg
                state = .available(version: Self.normalize(latest), url: link, download: dmg)
            } else {
                pendingDownload = nil
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Downloads the release DMG and opens it (mounting it in Finder) so the user
    /// can drag the new app into Applications. A pragmatic, transparent
    /// alternative to a silent self-updater.
    func downloadAndOpen() async {
        guard let url = pendingDownload, !isDownloading else { return }
        isDownloading = true
        defer { isDownloading = false }
        do {
            let (tmp, _) = try await URLSession.shared.download(from: url)
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            NSWorkspace.shared.open(dest)
        } catch {
            state = .failed("Download failed: \(error.localizedDescription)")
        }
    }

    /// Strips a leading "v" and surrounding whitespace from a tag.
    nonisolated static func normalize(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    /// Numeric, component-wise semver comparison ("1.10" > "1.9").
    nonisolated static func isNewer(_ tag: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            normalize(v).split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(tag), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

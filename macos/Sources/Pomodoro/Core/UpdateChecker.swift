import Foundation
import Combine

/// A release newer than the running build.
struct AvailableUpdate: Equatable {
    var version: String
    var name: String
    var pageURL: URL
    /// The platform's own asset, when the release carries one.
    var downloadURL: URL?
    /// The published checksum, so a download can be verified before it runs.
    var checksumURL: URL?
    var publishedAt: Date?
}

/// Checks GitHub for a newer release on launch.
///
/// It only ever *tells* you: downloading and installing stay a deliberate
/// click, because this app writes files the other front ends read and a
/// silent swap under a running timer is not worth the convenience.
@MainActor
final class UpdateChecker: ObservableObject {
    static let repository = "dukunuu/pomodoro"

    @Published private(set) var available: AvailableUpdate?
    @Published private(set) var checking = false
    @Published private(set) var lastError: String?

    private let defaults = UserDefaults.standard
    private let session = URLSession(configuration: .ephemeral)

    /// The build's marketing version. A source build reports 0.0.0-dev, which
    /// compares older than any release — correct, if a little eager.
    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    var enabled: Bool {
        get { defaults.object(forKey: "checkForUpdates") == nil ? true : defaults.bool(forKey: "checkForUpdates") }
        set { defaults.set(newValue, forKey: "checkForUpdates") }
    }

    private var lastCheck: Date? {
        get { defaults.object(forKey: "lastUpdateCheck") as? Date }
        set { defaults.set(newValue, forKey: "lastUpdateCheck") }
    }

    /// Called at launch. Quiet: no alert, no error surfaced unless asked.
    func checkOnLaunch() {
        guard enabled else { return }
        // Once a day is plenty for a pomodoro timer, and keeps the API's
        // unauthenticated rate limit far out of reach.
        if let last = lastCheck, Date().timeIntervalSince(last) < 86_400 { return }
        Task { await check(force: false) }
    }

    @discardableResult
    func check(force: Bool) async -> AvailableUpdate? {
        guard !checking else { return available }
        checking = true
        lastError = nil
        defer { checking = false }

        var request = URLRequest(url: URL(string:
            "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Pomodoro/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastError = "No response from GitHub."
                return nil
            }
            if http.statusCode == 404 {
                // No published release yet; not an error worth showing.
                lastCheck = Date()
                return nil
            }
            guard http.statusCode == 200 else {
                lastError = "GitHub returned HTTP \(http.statusCode)."
                return nil
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                lastError = "GitHub returned unreadable JSON."
                return nil
            }

            lastCheck = Date()
            guard (json["draft"] as? Bool) != true, (json["prerelease"] as? Bool) != true else {
                return nil
            }
            guard let tag = json["tag_name"] as? String,
                  let pageString = json["html_url"] as? String,
                  let page = URL(string: pageString) else { return nil }

            let latest = Self.normalize(tag)
            guard Self.isNewer(latest, than: Self.normalize(currentVersion)) else {
                available = nil
                return nil
            }

            // The disk image and its checksum: an update that installs itself
            // must verify what it downloaded.
            var asset: URL?
            var checksum: URL?
            for item in (json["assets"] as? [[String: Any]]) ?? [] {
                guard let name = item["name"] as? String,
                      let urlString = item["browser_download_url"] as? String,
                      let url = URL(string: urlString) else { continue }
                if name.hasSuffix(".dmg") { asset = url }
                if name.hasSuffix(".dmg.sha256") { checksum = url }
            }

            let update = AvailableUpdate(
                version: latest,
                name: (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? tag,
                pageURL: page,
                downloadURL: asset,
                checksumURL: checksum,
                publishedAt: (json["published_at"] as? String).flatMap {
                    ISO8601DateFormatter().date(from: $0)
                }
            )
            available = update
            return update
        } catch {
            lastError = force ? error.localizedDescription : nil
            return nil
        }
    }

    // MARK: - Version comparison

    /// Strips a leading "v" and any pre-release suffix: "v1.2.3-beta" → "1.2.3".
    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") { text.removeFirst() }
        if let dash = text.firstIndex(of: "-") { text = String(text[text.startIndex..<dash]) }
        return text
    }

    static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = components(candidate)
        let right = components(current)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}

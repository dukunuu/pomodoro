import Foundation
import CryptoKit
import AppKit

/// Downloads a release and installs it over the running app.
///
/// A process cannot reliably replace its own bundle while it is running, so
/// the swap is handed to a small script that waits for this process to exit
/// first. Nothing is run that has not been checked against the published
/// checksum.
@MainActor
final class UpdateInstaller: ObservableObject {
    enum Stage: Equatable {
        case idle
        case downloading(Double)
        case verifying
        case installing
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .idle, .failed: return false
            default: return true
            }
        }
    }

    @Published private(set) var stage: Stage = .idle

    private let session = URLSession(configuration: .ephemeral)

    /// True when the app can replace itself in place; otherwise the disk image
    /// is opened and the user drags it across, as they did the first time.
    static var canInstallInPlace: Bool {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else { return false }
        return FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path)
    }

    func install(_ update: AvailableUpdate) async {
        guard let source = update.downloadURL else {
            NSWorkspace.shared.open(update.pageURL)
            return
        }
        guard Self.canInstallInPlace else {
            // Read-only location (a managed /Applications, say). Hand over the
            // image rather than failing.
            stage = .failed("Pomodoro cannot replace itself here. Opening the download instead.")
            NSWorkspace.shared.open(source)
            return
        }

        do {
            stage = .downloading(0)
            let image = try await download(source)

            stage = .verifying
            if let checksum = update.checksumURL {
                try await verify(image, against: checksum)
            }

            stage = .installing
            try swap(using: image, version: update.version)
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    // MARK: - Steps

    private func download(_ source: URL) async throws -> URL {
        let (bytes, response) = try await session.bytes(from: source)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Failure("The download failed.")
        }
        let expected = response.expectedContentLength
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pomodoro-update-\(UUID().uuidString).dmg")

        FileManager.default.createFile(atPath: target.path, contents: nil)
        let handle = try FileHandle(forWritingTo: target)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(1 << 16)
        var written: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 16 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expected > 0 { stage = .downloading(Double(written) / Double(expected)) }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
        return target
    }

    private func verify(_ image: URL, against checksum: URL) async throws {
        let (data, _) = try await session.data(from: checksum)
        let published = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").first.map(String.init)?.lowercased()

        let handle = try FileHandle(forReadingFrom: image)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()

        guard let published, published == actual else {
            try? FileManager.default.removeItem(at: image)
            throw Failure("The downloaded update did not match its published checksum.")
        }
    }

    /// Mounts the image and hands the swap to a script that outlives us.
    private func swap(using image: URL, version: String) throws {
        let bundle = Bundle.main.bundleURL
        let mount = FileManager.default.temporaryDirectory
            .appendingPathComponent("pomodoro-update-\(UUID().uuidString)")

        let script = """
        #!/bin/sh
        set -e
        # Wait for Pomodoro to exit so its bundle is no longer in use.
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        hdiutil attach '\(image.path)' -nobrowse -readonly -mountpoint '\(mount.path)' -quiet
        # ditto rather than cp: it preserves the signature and extended attributes.
        ditto '\(mount.path)/Pomodoro.app' '\(bundle.path).new'
        rm -rf '\(bundle.path)'
        mv '\(bundle.path).new' '\(bundle.path)'
        hdiutil detach '\(mount.path)' -quiet || true
        rm -f '\(image.path)'
        open '\(bundle.path)'
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pomodoro-update-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        try process.run()

        // Leave promptly so the script can proceed.
        NSApp.terminate(nil)
    }

    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

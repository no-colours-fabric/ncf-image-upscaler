import Foundation
import CryptoKit

struct PortableRuntimeManifest: Codable {
    let archive: String
    let sha256: String
    let version: String

    var isValid: Bool {
        archive == "runtime.tar" && sha256.count == 64 &&
            sha256.allSatisfy { "0123456789abcdef".contains($0) } && !version.isEmpty
    }
}

/// Installs the bundled, relocatable engine without downloading or using system Python.
struct PortableRuntimeInstaller {
    let resources: URL
    let data: URL
    let manifest: PortableRuntimeManifest

    static func bundled(resources: URL?, data: URL) throws -> PortableRuntimeInstaller? {
        guard let resources else { return nil }
        let file = resources.appendingPathComponent("portable-runtime.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let manifest = try JSONDecoder().decode(PortableRuntimeManifest.self, from: Data(contentsOf: file))
        guard manifest.isValid else { throw AppFailure.message("Invalid bundled engine manifest. Download the app again.") }
        return PortableRuntimeInstaller(resources: resources, data: data, manifest: manifest)
    }

    var directory: URL {
        data.appendingPathComponent("runtime/portable", isDirectory: true)
            .appendingPathComponent(manifest.sha256, isDirectory: true)
    }
    var python: URL { directory.appendingPathComponent("bin/python3") }
    var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: python.path) &&
            (try? String(contentsOf: directory.appendingPathComponent(".payload-sha256"), encoding: .utf8)) == manifest.sha256
    }

    static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// A process-wide file lock also protects concurrent app launches and versions.
    func install() throws {
        guard manifest.isValid else { throw AppFailure.message("Invalid engine manifest.") }
        let manager = FileManager.default
        let parent = directory.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let lock = Darwin.open(parent.appendingPathComponent(".install.lock").path,
                               O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard lock >= 0 else { throw AppFailure.message("Could not lock the engine installation.") }
        defer { Darwin.close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { throw AppFailure.message("Could not lock the engine installation.") }
        defer { flock(lock, LOCK_UN) }
        if isInstalled { return }
        let archive = resources.appendingPathComponent(manifest.archive)
        guard try Self.sha256(archive) == manifest.sha256 else {
            throw AppFailure.message("The bundled engine is damaged. Download the app again.")
        }
        // Do not silently replace an unexpected existing runtime.
        guard !manager.fileExists(atPath: directory.path) else {
            throw AppFailure.message("The installed engine is incomplete. Remove this engine folder and reopen the app: \(directory.path)")
        }
        let staging = parent.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xf", archive.path, "-C", staging.path]
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppFailure.message("Could not install the bundled engine. " + (String(data: diagnostics, encoding: .utf8) ?? ""))
        }
        let extracted = staging.appendingPathComponent("runtime", isDirectory: true)
        guard manager.isExecutableFile(atPath: extracted.appendingPathComponent("bin/python3").path) else {
            throw AppFailure.message("The bundled engine is missing its Python executable.")
        }
        try manifest.sha256.write(to: extracted.appendingPathComponent(".payload-sha256"), atomically: true, encoding: .utf8)
        try manager.moveItem(at: extracted, to: directory)
    }
}

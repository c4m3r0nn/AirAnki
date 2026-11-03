import Foundation

public enum AddonInstallState: Equatable, Sendable {
    case ankiNotFound
    case notInstalled
    case installed(version: String)
    case outdated(installed: String?, bundled: String)
    case developmentLink(target: String)
}

public struct AddonInstaller {
    public static let folderName = "airanki_bridge"
    public static var defaultAddonsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Anki2/addons21")
    }
    private let bundledAddon: URL
    private let addonsDirectory: URL
    private let fileManager: FileManager
    private var destination: URL { addonsDirectory.appendingPathComponent(Self.folderName) }

    public init(bundledAddon: URL, addonsDirectory: URL = AddonInstaller.defaultAddonsDirectory,
                fileManager: FileManager = .default) {
        self.bundledAddon = bundledAddon; self.addonsDirectory = addonsDirectory; self.fileManager = fileManager
    }

    public var bundledVersion: String? { version(at: bundledAddon) }

    public func state() -> AddonInstallState {
        guard isDirectory(addonsDirectory) else { return .ankiNotFound }
        if let target = try? fileManager.destinationOfSymbolicLink(atPath: destination.path) {
            return .developmentLink(target: target)
        }
        guard fileManager.fileExists(atPath: destination.path) else { return .notInstalled }
        let installed = version(at: destination), bundled = bundledVersion
        if let installed, let bundled, isAtLeast(installed, bundled) { return .installed(version: installed) }
        return .outdated(installed: installed, bundled: bundled ?? "unknown")
    }

    public func install() throws {
        guard isDirectory(addonsDirectory) else {
            throw AnkiError.message("Anki's add-ons folder wasn't found. Open Anki once, then try again.")
        }
        try checkDevelopmentLink()
        guard let bundledVersion, components(bundledVersion) != nil, isDirectory(bundledAddon) else {
            throw AnkiError.message("The bundled Anki add-on is missing or has an invalid version. Reinstall AirAnki, then try again.")
        }
        let staging = addonsDirectory.appendingPathComponent(".airanki_bridge.tmp-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: staging) }
        try copyAddon(from: bundledAddon, to: staging)
        let metadata = destination.appendingPathComponent("meta.json")
        if fileManager.fileExists(atPath: metadata.path) {
            try fileManager.copyItem(at: metadata, to: staging.appendingPathComponent("meta.json"))
        }
        // Recheck after staging so a newly created developer link is left alone.
        try checkDevelopmentLink()
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging, options: .usingNewMetadataOnly)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
    }

    private func checkDevelopmentLink() throws {
        if (try? fileManager.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            throw AnkiError.message("A developer link is installed for the Anki add-on. Update the linked source instead.")
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    private func version(at directory: URL) -> String? {
        guard let data = fileManager.contents(atPath: directory.appendingPathComponent("manifest.json").path),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = manifest["human_version"] as? String, !version.isEmpty else { return nil }
        return version
    }

    private func components(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        return numbers
    }

    private func isAtLeast(_ installed: String, _ bundled: String) -> Bool {
        guard let left = components(installed), let right = components(bundled) else { return false }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0, b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return true
    }

    private func copyAddon(from source: URL, to target: URL) throws {
        try fileManager.createDirectory(at: target, withIntermediateDirectories: false)
        for item in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            guard !["__pycache__", "tests", ".DS_Store", "meta.json"].contains(item.lastPathComponent) else { continue }
            let output = target.appendingPathComponent(item.lastPathComponent)
            let attributes = try fileManager.attributesOfItem(atPath: item.path)
            if attributes[.type] as? FileAttributeType == .typeDirectory {
                try copyAddon(from: item, to: output)
            } else {
                try fileManager.copyItem(at: item, to: output)
            }
        }
    }
}

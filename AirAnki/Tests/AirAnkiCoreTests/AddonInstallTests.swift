import Foundation
#if AIRANKI_SELF_TEST
import AirAnkiCore
#else
import XCTest
@testable import AirAnkiCore
#endif

private struct AddonFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("airanki-install-\(UUID().uuidString)")
    var bundle: URL { root.appendingPathComponent("bundle") }
    var addons: URL { root.appendingPathComponent("addons21") }
    var destination: URL { addons.appendingPathComponent(AddonInstaller.folderName) }
    var installer: AddonInstaller { AddonInstaller(bundledAddon: bundle, addonsDirectory: addons) }
    init(addonsExist: Bool = true) throws {
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        if addonsExist { try FileManager.default.createDirectory(at: addons, withIntermediateDirectories: true) }
        try manifest("1.0.0", at: bundle)
        try write("# bundled bridge", at: bundle.appendingPathComponent("__init__.py"))
    }
    func write(_ text: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    func manifest(_ version: String?, at directory: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: version.map { ["human_version": $0] } ?? [:])
        try write(String(decoding: data, as: UTF8.self), at: directory.appendingPathComponent("manifest.json"))
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    func assertNoStaging() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: addons.path)
        XCTAssertFalse(names.contains { $0.hasPrefix(".airanki_bridge.tmp-") })
    }
}

private final class FailingCopyFileManager: FileManager, @unchecked Sendable {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if srcURL.lastPathComponent == "meta.json" { throw AnkiError.message("simulated copy failure") }
        try super.copyItem(at: srcURL, to: dstURL)
    }
}

final class AddonInstallTests: XCTestCase {
    func testMissingAnkiFolderIsNotCreated() throws {
        let fixture = try AddonFixture(addonsExist: false); defer { fixture.cleanup() }
        XCTAssertEqual(fixture.installer.state(), .ankiNotFound)
        do { try fixture.installer.install(); XCTFail("missing folder must fail") }
        catch { XCTAssertEqual(error.localizedDescription, "Anki's add-ons folder wasn't found. Open Anki once, then try again.") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.addons.path))
        try fixture.write("not a directory", at: fixture.addons)
        XCTAssertEqual(fixture.installer.state(), .ankiNotFound)
    }

    func testFreshInstall() throws {
        let fixture = try AddonFixture(); defer { fixture.cleanup() }
        XCTAssertEqual(fixture.installer.bundledVersion, "1.0.0")
        XCTAssertEqual(fixture.installer.state(), .notInstalled)
        try fixture.installer.install()
        XCTAssertEqual(fixture.installer.state(), .installed(version: "1.0.0"))
        let content = try String(contentsOf: fixture.destination.appendingPathComponent("__init__.py"))
        XCTAssertEqual(content, "# bundled bridge")
        try fixture.assertNoStaging()
    }

    func testUpgradePreservesMetadataAndRemovesOldFiles() throws {
        let fixture = try AddonFixture(); defer { fixture.cleanup() }
        try fixture.manifest("0.9.0", at: fixture.destination)
        let metadata = "{\"config\":{\"feedback_flash\":false},\"disabled\":true}"
        try fixture.write(metadata, at: fixture.destination.appendingPathComponent("meta.json"))
        try fixture.write("obsolete", at: fixture.destination.appendingPathComponent("old.py"))
        try fixture.write("bundle metadata must not win", at: fixture.bundle.appendingPathComponent("meta.json"))
        XCTAssertEqual(fixture.installer.state(), .outdated(installed: "0.9.0", bundled: "1.0.0"))
        try fixture.installer.install()
        XCTAssertEqual(fixture.installer.state(), .installed(version: "1.0.0"))
        let preserved = try String(contentsOf: fixture.destination.appendingPathComponent("meta.json"))
        XCTAssertEqual(preserved, metadata)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("old.py").path))
        try fixture.assertNoStaging()
    }

    func testDevelopmentLinksIncludingDanglingAreNeverReplaced() throws {
        for dangling in [false, true] {
            let fixture = try AddonFixture(); defer { fixture.cleanup() }
            let target = dangling ? fixture.root.appendingPathComponent("missing") : fixture.bundle
            try FileManager.default.createSymbolicLink(at: fixture.destination, withDestinationURL: target)
            XCTAssertEqual(fixture.installer.state(), .developmentLink(target: target.path))
            do { try fixture.installer.install(); XCTFail("developer link must fail") }
            catch { XCTAssertTrue(error.localizedDescription.contains("developer link")) }
            let actual = try FileManager.default.destinationOfSymbolicLink(atPath: fixture.destination.path)
            XCTAssertEqual(actual, target.path)
            XCTAssertEqual(fixture.installer.bundledVersion, "1.0.0")
            try fixture.assertNoStaging()
        }
    }

    func testBundleJunkIsExcludedRecursively() throws {
        let fixture = try AddonFixture(); defer { fixture.cleanup() }
        let excluded = ["__pycache__/commands.pyc", "tests/test.py", "meta.json", ".DS_Store",
                        "nested/__pycache__/x.pyc", "nested/tests/test.py", "nested/meta.json", "nested/.DS_Store"]
        for name in excluded { try fixture.write("junk", at: fixture.bundle.appendingPathComponent(name)) }
        try fixture.write("keep", at: fixture.bundle.appendingPathComponent("nested/keep.py"))
        try fixture.installer.install()
        for name in excluded {
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent(name).path))
        }
        let content = try String(contentsOf: fixture.destination.appendingPathComponent("nested/keep.py"))
        XCTAssertEqual(content, "keep")
    }

    func testNumericVersionComparison() throws {
        let fixture = try AddonFixture(); defer { fixture.cleanup() }
        for (installed, bundled, current) in [("1.0.10", "1.0.9", true), ("1.0.9", "1.0.10", false),
                                             ("2.0", "1.99.99", true), ("1.0", "1.0.0", true),
                                             ("1.0.0.1", "1.0.0", true), ("01.02.003", "1.2.3", true),
                                             ("1.invalid", "1.0.0", false), ("1..0", "1.0.0", false)] {
            try fixture.manifest(bundled, at: fixture.bundle)
            try fixture.manifest(installed, at: fixture.destination)
            XCTAssertEqual(fixture.installer.state(), current ? .installed(version: installed) : .outdated(installed: installed, bundled: bundled))
        }
    }

    func testMissingOrMalformedInstalledManifestCanBeUpgraded() throws {
        let fixture = try AddonFixture(); defer { fixture.cleanup() }
        for manifest in ["{}", "not json"] {
            try fixture.write(manifest, at: fixture.destination.appendingPathComponent("manifest.json"))
            XCTAssertEqual(fixture.installer.state(), .outdated(installed: nil, bundled: "1.0.0"))
            try fixture.installer.install()
            XCTAssertEqual(fixture.installer.state(), .installed(version: "1.0.0"))
        }
        try FileManager.default.removeItem(at: fixture.destination.appendingPathComponent("manifest.json"))
        XCTAssertEqual(fixture.installer.state(), .outdated(installed: nil, bundled: "1.0.0"))
    }

    func testInvalidBundleLeavesInstallationAlone() throws {
        let fixture = try AddonFixture(); defer { fixture.cleanup() }
        try fixture.manifest("0.9.0", at: fixture.destination)
        for version in [nil, "invalid"] as [String?] {
            try fixture.manifest(version, at: fixture.bundle)
            do { try fixture.installer.install(); XCTFail("invalid bundle must fail") }
            catch { XCTAssertTrue(error.localizedDescription.contains("bundled Anki add-on")) }
            let old = try String(contentsOf: fixture.destination.appendingPathComponent("manifest.json"))
            XCTAssertTrue(old.contains("0.9.0"))
            try fixture.assertNoStaging()
        }
    }

    func testCopyFailurePreservesInstallationAndCleansStaging() throws {
        let fixture = try AddonFixture(); defer { fixture.cleanup() }
        try fixture.manifest("0.9.0", at: fixture.destination)
        try fixture.write("user config", at: fixture.destination.appendingPathComponent("meta.json"))
        let installer = AddonInstaller(bundledAddon: fixture.bundle, addonsDirectory: fixture.addons,
                                       fileManager: FailingCopyFileManager())
        do { try installer.install(); XCTFail("copy must fail") }
        catch { XCTAssertEqual(error.localizedDescription, "simulated copy failure") }
        XCTAssertEqual(installer.state(), .outdated(installed: "0.9.0", bundled: "1.0.0"))
        let metadata = try String(contentsOf: fixture.destination.appendingPathComponent("meta.json"))
        XCTAssertEqual(metadata, "user config")
        try fixture.assertNoStaging()
    }
}

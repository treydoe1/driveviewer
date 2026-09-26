import Foundation
import XCTest
@testable import driveviewer

final class DriveviewerTests: XCTestCase {
    func testScannerAggregatesCategoriesAndSkipsLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("driveviewer-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let video = root.appendingPathComponent("clip.mp4")
        let app = root.appendingPathComponent("Editor.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8_192).write(to: video)
        try Data(repeating: 2, count: 4_096).write(to: app.appendingPathComponent("binary"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)

        let result = try XCTUnwrap(DiskScanner.scan(root: root, token: ScanToken(), progress: { _ in }))
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(result.items, 3)
        XCTAssertGreaterThan(result.root.size, 0)
        XCTAssertGreaterThan(result.root.categoryBytes[FileCategory.video.rawValue], 0)
        XCTAssertGreaterThan(result.root.categoryBytes[FileCategory.apps.rawValue], 0)
        XCTAssertEqual(result.root.children.count, 2)
        XCTAssertEqual(result.root.size, result.root.categoryBytes.reduce(0, +))
        let appNode = try XCTUnwrap(result.root.children.first { $0.name == "Editor.app" })
        XCTAssertEqual(appNode.children.map(\.name), ["binary"])
        XCTAssertEqual(appNode.itemCount, 2)
        let tiles = NestedTreemapLayout.layout(root: result.root, filter: nil,
                                                in: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertTrue(tiles.contains { $0.item.node?.name == "binary" && $0.depth > 0 })
    }

    func testScannerLimitsRetainedItemsWithoutLosingTotals() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("driveviewer-limit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<1_250 {
            try Data([1]).write(to: root.appendingPathComponent("file-\(index).txt"))
        }

        let result = try XCTUnwrap(DiskScanner.scan(root: root, token: ScanToken(), progress: { _ in }))
        XCTAssertEqual(result.items, 1_250)
        XCTAssertEqual(result.root.children.count, 48)
        XCTAssertEqual(result.omittedItems, 1_202)
        XCTAssertGreaterThan(result.root.size, result.root.children.reduce(0) { $0 + $1.size })
        XCTAssertEqual(result.root.size, result.root.categoryBytes.reduce(0, +))
    }

    func testRootScanSkipsDuplicateMountPaths() {
        XCTAssertTrue(DiskScanner.isDuplicateRootPath("/.nofollow", scanning: "/"))
        XCTAssertTrue(DiskScanner.isDuplicateRootPath("/System/Volumes/Data", scanning: "/"))
        XCTAssertFalse(DiskScanner.isDuplicateRootPath("/System/Volumes/Data", scanning: "/System"))
    }

    func testDeepFoldersRemainNavigable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("driveviewer-deep-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var directory = root
        for index in 0..<9 {
            directory.appendPathComponent("level-\(index)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data(repeating: 1, count: 2_048).write(to: directory.appendingPathComponent("large.mov"))

        let result = try XCTUnwrap(DiskScanner.scan(root: root, token: ScanToken(), progress: { _ in }))
        var cursor = result.root
        for index in 0..<9 {
            cursor = try XCTUnwrap(cursor.children.first { $0.name == "level-\(index)" })
        }
        XCTAssertEqual(cursor.children.first?.name, "large.mov")
    }

    @MainActor
    func testModelDoesNotScanOnStartup() {
        let model = AppModel()
        XCTAssertFalse(model.isScanning)
        XCTAssertNil(model.result)
    }

    @MainActor
    func testOpeningNestedFolderUsesExistingScan() async throws {
        let previousScanPath = UserDefaults.standard.string(forKey: "lastScanPath")
        defer {
            if let previousScanPath {
                UserDefaults.standard.set(previousScanPath, forKey: "lastScanPath")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastScanPath")
            }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("driveviewer-nav-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("A/B")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4_096).write(to: nested.appendingPathComponent("large.mov"))

        let model = AppModel()
        model.scan(root)
        let deadline = Date().addingTimeInterval(5)
        while model.isScanning && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let first = try XCTUnwrap(model.root?.children.first)
        let second = try XCTUnwrap(first.children.first)
        model.open(second)
        XCTAssertFalse(model.isScanning)
        XCTAssertEqual(model.navigation.map(\.name), ["A", "B"])
        XCTAssertEqual(model.current?.children.first?.name, "large.mov")
        model.goUp()
        XCTAssertEqual(model.current?.name, "A")
    }

    func testTreemapCoversAvailableArea() {
        let items = [
            MapItem(node: nil, size: 50, title: "A"),
            MapItem(node: nil, size: 30, title: "B"),
            MapItem(node: nil, size: 20, title: "C")
        ]
        let result = TreemapLayout.layout(items, in: CGRect(x: 0, y: 0, width: 600, height: 400))
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.reduce(0) { $0 + $1.rect.width * $1.rect.height }, 240_000, accuracy: 0.1)
        XCTAssertTrue(result.allSatisfy { $0.rect.minX >= 0 && $0.rect.minY >= 0 && $0.rect.maxX <= 600.1 && $0.rect.maxY <= 400.1 })
    }

    func testDiskCapacityPercentage() {
        XCTAssertEqual(DiskCapacity(total: 1_000, available: 125).percentLabel, "12.5%")
        XCTAssertEqual(DiskCapacity(total: 1_000, available: 1_500).availablePercent, 100)
    }
}

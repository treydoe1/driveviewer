import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    private static let lastScanPathKey = "lastScanPath"
    private static let openedFullDiskAccessKey = "openedFullDiskAccessSettings"
    private static let fullDiskAccessSettingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!

    @Published private(set) var result: ScanResult?
    @Published private(set) var progress: ScanProgress?
    @Published private(set) var isScanning = false
    @Published private(set) var errorMessage: String?
    @Published var categoryFilter: FileCategory?
    @Published var selectedIDs: Set<String> = []
    @Published var navigation: [FileNode] = []
    @Published var showTrashConfirmation = false
    @Published var showFullDiskAccessPrompt = false
    @Published private(set) var volumeTotal: Int64 = 0
    @Published private(set) var volumeAvailable: Int64 = 0

    private var token: ScanToken?
    private var resultBeforeScan: ScanResult?
    private(set) var scanURL: URL?

    var root: FileNode? { result?.root }
    var current: FileNode? { navigation.last ?? root }
    var selectedNodes: [FileNode] {
        guard let current, !selectedIDs.isEmpty else { return [] }
        var nodes: [FileNode] = []
        func visit(_ parent: FileNode) {
            for child in parent.children {
                if selectedIDs.contains(child.id) { nodes.append(child) }
                else if child.isDirectory { visit(child) }
            }
        }
        visit(current)
        return nodes
    }
    var selectedSize: Int64 { selectedNodes.reduce(0) { $0 + $1.size } }
    var displayChildren: [FileNode] { current?.sortedChildren(matching: categoryFilter) ?? [] }
    var activeSize: Int64 {
        guard let current else { return 0 }
        return categoryFilter.map { current.categoryBytes[$0.rawValue] } ?? current.size
    }

    init() {
        let savedPath = UserDefaults.standard.string(forKey: Self.lastScanPathKey)
            ?? UserDefaults(suiteName: "com.treykeys.spaceview")?.string(forKey: Self.lastScanPathKey)
        if UserDefaults.standard.string(forKey: Self.lastScanPathKey) == nil, let savedPath {
            UserDefaults.standard.set(savedPath, forKey: Self.lastScanPathKey)
        }
        let startURL = savedPath.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.homeDirectoryForCurrentUser
        scanURL = FileManager.default.fileExists(atPath: startURL.path) ? startURL : FileManager.default.homeDirectoryForCurrentUser
        if let capacity = DiskCapacity.startupDisk() {
            volumeTotal = capacity.total
            volumeAvailable = capacity.available
        }
        if !UserDefaults.standard.bool(forKey: Self.openedFullDiskAccessKey) {
            showFullDiskAccessPrompt = true
        }
    }

    func completeFullDiskAccessPrompt(openSettings: Bool) {
        showFullDiskAccessPrompt = false
        UserDefaults.standard.set(true, forKey: Self.openedFullDiskAccessKey)
        if openSettings { openFullDiskAccessSettings() }
    }

    @discardableResult
    func openFullDiskAccessSettings() -> Bool {
        NSWorkspace.shared.open(Self.fullDiskAccessSettingsURL)
    }

    func chooseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Scan"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async { self?.scan(url) }
        }
    }

    func scan(_ url: URL, preservingContext: Bool = false) {
        UserDefaults.standard.set(url.path, forKey: Self.lastScanPathKey)
        let previousFilter = preservingContext ? categoryFilter : nil
        let previousPaths = preservingContext ? navigation.map(\.id) : []
        resultBeforeScan = preservingContext ? result : nil
        token?.cancel()
        let nextToken = ScanToken()
        token = nextToken
        scanURL = url
        isScanning = true
        errorMessage = nil
        progress = ScanProgress(items: 0, bytes: 0, currentPath: url.path)
        result = nil
        if !preservingContext {
            navigation = []
        }
        selectedIDs = []
        categoryFilter = nil
        if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            volumeTotal = Int64(values.volumeTotalCapacity ?? 0)
            volumeAvailable = values.volumeAvailableCapacityForImportantUsage ?? 0
        }

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let scanResult = DiskScanner.scan(root: url, token: nextToken) { update in
                DispatchQueue.main.async { [self] in
                    guard self.token === nextToken else { return }
                    self.progress = update
                }
            }
            DispatchQueue.main.async { [self] in
                guard self.token === nextToken else { return }
                self.isScanning = false
                self.progress = nil
                self.result = scanResult
                self.resultBeforeScan = nil
                self.categoryFilter = previousFilter
                self.navigation = []
                if let scanResult {
                    var cursor = scanResult.root
                    for path in previousPaths {
                        guard let child = cursor.children.first(where: { $0.id == path }) else { break }
                        self.navigation.append(child)
                        cursor = child
                    }
                }
            }
        }
    }

    func cancelScan() {
        token?.cancel()
        token = nil
        isScanning = false
        progress = nil
        result = resultBeforeScan
        resultBeforeScan = nil
    }
    func refresh() { if let scanURL { scan(scanURL, preservingContext: true) } }
    func clearError() { errorMessage = nil }

    func open(_ node: FileNode) {
        guard node.isDirectory else { reveal(node) ; return }
        guard let root else { return }
        var path: [FileNode] = []
        var cursor: FileNode? = node
        while let current = cursor, current !== root {
            path.append(current)
            cursor = current.parent
        }
        guard cursor === root else { return }
        navigation = Array(path.reversed())
        selectedIDs = []
        categoryFilter = nil
    }

    func go(to index: Int) {
        guard !isScanning, index < navigation.count - 1, index >= -1 else { return }
        navigation = Array(navigation.prefix(index + 1))
        selectedIDs = []
        categoryFilter = nil
    }

    func goUp() {
        guard !isScanning, !navigation.isEmpty else { return }
        navigation.removeLast()
        selectedIDs = []
        categoryFilter = nil
    }

    func select(_ node: FileNode, extending: Bool) {
        if extending {
            if selectedIDs.contains(node.id) { selectedIDs.remove(node.id) }
            else { selectedIDs.insert(node.id) }
        } else { selectedIDs = [node.id] }
    }

    func reveal(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func revealCurrent() {
        if let node = selectedNodes.first { reveal(node) }
        else if let current { reveal(current) }
    }

    func requestTrash(_ nodes: [FileNode]? = nil) {
        if let nodes { selectedIDs = Set(nodes.map(\.id)) }
        guard !selectedNodes.isEmpty else { return }
        showTrashConfirmation = true
    }

    func trashSelected() {
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return }
        var failures: [String] = []
        var removed = 0
        for node in nodes {
            do {
                try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
                removed += node.itemCount
                node.removeFromTree()
            }
            catch { failures.append(node.name) }
        }
        showTrashConfirmation = false
        selectedIDs = []
        if let result {
            self.result = ScanResult(root: result.root, items: max(0, result.items - removed),
                                     skipped: result.skipped,
                                     omittedItems: result.root.directItemCount - result.root.children.count,
                                     duration: result.duration)
        }
        if !failures.isEmpty { errorMessage = failures.joined(separator: ", ") }
    }
}

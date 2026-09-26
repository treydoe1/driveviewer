import Foundation

enum FileCategory: Int, CaseIterable, Identifiable {
    case video, photos, audio, documents, apps, archives, code, other

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .video: "Video"
        case .photos: "Photos"
        case .audio: "Audio"
        case .documents: "Documents"
        case .apps: "Apps"
        case .archives: "Archives"
        case .code: "Code"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .video: "film"
        case .photos: "photo"
        case .audio: "waveform"
        case .documents: "doc.text"
        case .apps: "app"
        case .archives: "archivebox"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .other: "square.grid.2x2"
        }
    }

    static func forFile(_ url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()
        if ["mov", "mp4", "m4v", "mkv", "avi", "wmv", "webm", "mts", "mxf", "mpg", "mpeg"].contains(ext) { return .video }
        if ["jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp", "raw", "cr2", "nef", "dng", "psd", "ai", "svg"].contains(ext) { return .photos }
        if ["mp3", "m4a", "wav", "aiff", "flac", "aac", "ogg", "wma"].contains(ext) { return .audio }
        if ["pdf", "doc", "docx", "pages", "txt", "rtf", "odt", "xls", "xlsx", "numbers", "ppt", "pptx", "key", "csv", "epub"].contains(ext) { return .documents }
        if ["app", "dmg", "pkg", "ipa", "exe"].contains(ext) { return .apps }
        if ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "iso"].contains(ext) { return .archives }
        if ["swift", "py", "js", "jsx", "ts", "tsx", "html", "css", "json", "xml", "yaml", "yml", "toml", "sql", "rs", "go", "java", "c", "cpp", "h", "sh", "md"].contains(ext) { return .code }
        return .other
    }
}

final class FileNode: Identifiable, @unchecked Sendable {
    let url: URL
    let isDirectory: Bool
    let category: FileCategory
    weak var parent: FileNode?
    var size: Int64
    var children: [FileNode] = []
    var itemCount = 1
    var directItemCount = 0
    var retainedNodeCount = 1
    var categoryBytes = Array(repeating: Int64(0), count: FileCategory.allCases.count)

    var id: String { url.path }
    var name: String { url.path == "/" ? "Macintosh HD" : url.lastPathComponent }

    init(url: URL, isDirectory: Bool, size: Int64 = 0, categoryOverride: FileCategory? = nil) {
        self.url = url
        self.isDirectory = isDirectory
        self.category = categoryOverride ?? (isDirectory ? .other : FileCategory.forFile(url))
        self.size = size
        if !isDirectory { categoryBytes[category.rawValue] = size }
    }

    func sortedChildren(matching filter: FileCategory? = nil) -> [FileNode] {
        children.filter { node in
            guard let filter else { return true }
            return node.categoryBytes[filter.rawValue] > 0
        }.sorted { lhs, rhs in
            let a = filter.map { lhs.categoryBytes[$0.rawValue] } ?? lhs.size
            let b = filter.map { rhs.categoryBytes[$0.rawValue] } ?? rhs.size
            return a == b ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending : a > b
        }
    }

    func compact(maxChildren: Int, maxNodes: Int) {
        guard children.count > maxChildren || retainedNodeCount > maxNodes else { return }
        children.sort { $0.size > $1.size }
        if children.count > maxChildren {
            children.removeLast(children.count - maxChildren)
        }
        var count = 1 + children.reduce(0) { $0 + $1.retainedNodeCount }
        while count > maxNodes {
            if let index = children.indices.reversed().first(where: { children[$0].retainedNodeCount > 1 }) {
                let child = children[index]
                count -= child.retainedNodeCount - 1
                child.children.removeAll()
                child.retainedNodeCount = 1
            } else if let last = children.popLast() {
                count -= last.retainedNodeCount
            } else { break }
        }
        retainedNodeCount = count
    }

    func removeFromTree() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        parent.directItemCount -= 1
        var ancestor: FileNode? = parent
        while let node = ancestor {
            node.size -= size
            node.itemCount -= itemCount
            node.retainedNodeCount -= retainedNodeCount
            for index in node.categoryBytes.indices { node.categoryBytes[index] -= categoryBytes[index] }
            ancestor = node.parent
        }
        self.parent = nil
    }
}

struct ScanProgress: Sendable {
    let items: Int
    let bytes: Int64
    let currentPath: String
}

struct ScanResult: Sendable {
    let root: FileNode
    let items: Int
    let skipped: Int
    let omittedItems: Int
    let duration: TimeInterval
}

final class ScanToken: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

enum DiskScanner {
    private static let maximumVisibleItems = 48
    private static let trimThreshold = 64

    private static func nodeBudget(at level: Int) -> Int {
        switch level {
        case 0: 60_000
        case 1: 5_000
        case 2: 600
        case 3: 120
        case 4: 32
        default: 24
        }
    }

    static func isDuplicateRootPath(_ path: String, scanning rootPath: String) -> Bool {
        rootPath == "/" && (path == "/.nofollow" || path == "/System/Volumes/Data")
    }

    static func scan(root rootURL: URL, token: ScanToken, progress: @escaping @Sendable (ScanProgress) -> Void) -> ScanResult? {
        let started = Date()
        let manager = FileManager.default
        let rootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let explicitlyScanningCloudStorage = rootURL.pathComponents.contains("CloudStorage")
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isVolumeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        let root = FileNode(url: rootURL, isDirectory: true)
        var stack: [(level: Int, node: FileNode)] = [(0, root)]
        var count = 0
        var skipped = 0
        var totalBytes: Int64 = 0
        var lastReport = Date.distantPast
        var packageStack: [(path: String, category: FileCategory)] = []

        func packageCategory(_ url: URL) -> FileCategory? {
            switch url.pathExtension.lowercased() {
            case "app": .apps
            case "photoslibrary": .photos
            case "musiclibrary", "band": .audio
            case "xcodeproj", "xcworkspace": .code
            default: nil
            }
        }

        func retain(_ child: FileNode, in parent: FileNode, at level: Int) {
            guard child.size > 0 else { return }
            child.parent = parent
            parent.children.append(child)
            parent.retainedNodeCount += child.retainedNodeCount
            if parent.children.count > trimThreshold || parent.retainedNodeCount > nodeBudget(at: level) {
                parent.compact(maxChildren: maximumVisibleItems, maxNodes: nodeBudget(at: level))
            }
        }

        func finishDirectory() {
            let frame = stack.removeLast()
            let parentFrame = stack[stack.count - 1]
            let child = frame.node
            child.compact(maxChildren: maximumVisibleItems, maxNodes: nodeBudget(at: frame.level))
            let parent = parentFrame.node
            parent.directItemCount += 1
            parent.itemCount += child.itemCount
            parent.size += child.size
            for index in parent.categoryBytes.indices { parent.categoryBytes[index] += child.categoryBytes[index] }
            retain(child, in: parent, at: parentFrame.level)
        }

        guard let enumerator = manager.enumerator(at: rootURL, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in
            skipped += 1
            return true
        }) else {
            return ScanResult(root: root, items: 0, skipped: 1, omittedItems: 0,
                              duration: Date().timeIntervalSince(started))
        }

        while !token.isCancelled {
            let finished = autoreleasepool { () -> Bool in
                guard let url = enumerator.nextObject() as? URL else { return true }
                let path = url.path
                let level = enumerator.level
                while stack.count > 1 && stack[stack.count - 1].level >= level {
                    finishDirectory()
                }
                guard let values = try? url.resourceValues(forKeys: keys) else {
                    skipped += 1
                    enumerator.skipDescendants()
                    return false
                }
                let isDirectory = values.isDirectory == true
                if values.isSymbolicLink == true || values.isVolume == true {
                    enumerator.skipDescendants()
                    return false
                }
                if isDuplicateRootPath(path, scanning: rootURL.path) {
                    enumerator.skipDescendants()
                    return false
                }
                if isDirectory && !explicitlyScanningCloudStorage && url.lastPathComponent == "CloudStorage" && url.deletingLastPathComponent().lastPathComponent == "Library" {
                    skipped += 1
                    enumerator.skipDescendants()
                    return false
                }
                while let package = packageStack.last, !path.hasPrefix(package.path + "/") {
                    packageStack.removeLast()
                }
                if isDirectory, let category = packageCategory(url) {
                    packageStack.append((path, category))
                }
                if isDirectory {
                    let node = FileNode(url: url, isDirectory: true, categoryOverride: packageStack.last?.category)
                    stack.append((level, node))
                } else {
                    let bytes = Int64(max(0, values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0))
                    totalBytes += bytes
                    let parentFrame = stack[stack.count - 1]
                    let parent = parentFrame.node
                    parent.directItemCount += 1
                    parent.itemCount += 1
                    parent.size += bytes
                    let category = packageStack.last?.category ?? FileCategory.forFile(url)
                    parent.categoryBytes[category.rawValue] += bytes
                    if bytes > 0 {
                        let file = FileNode(url: url, isDirectory: false, size: bytes, categoryOverride: category)
                        retain(file, in: parent, at: parentFrame.level)
                    }
                }
                count += 1
                let now = Date()
                if now.timeIntervalSince(lastReport) > 0.25 {
                    lastReport = now
                    progress(ScanProgress(items: count, bytes: totalBytes, currentPath: path))
                }
                return false
            }
            if finished { break }
        }
        guard !token.isCancelled else { return nil }
        while stack.count > 1 { finishDirectory() }
        root.compact(maxChildren: maximumVisibleItems, maxNodes: nodeBudget(at: 0))
        progress(ScanProgress(items: count, bytes: totalBytes, currentPath: rootURL.path))
        return ScanResult(root: root, items: count, skipped: skipped,
                          omittedItems: root.directItemCount - root.children.count,
                          duration: Date().timeIntervalSince(started))
    }
}

func sizeString(_ bytes: Int64) -> String {
    if bytes <= 0 { return "0 B" }
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

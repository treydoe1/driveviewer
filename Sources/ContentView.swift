import AppKit
import SwiftUI

private enum UIStyle {
    static let background = Color(red: 0.055, green: 0.071, blue: 0.102)
    static let sidebar = Color(red: 0.075, green: 0.094, blue: 0.129)
    static let panel = Color(red: 0.092, green: 0.116, blue: 0.157)
    static let line = Color.white.opacity(0.075)
    static let secondary = Color(red: 0.60, green: 0.66, blue: 0.73)
    static let accent = Color(red: 0.43, green: 0.85, blue: 0.74)

    static func color(for category: FileCategory) -> Color {
        switch category {
        case .video: Color(red: 0.48, green: 0.62, blue: 0.95)
        case .photos: Color(red: 0.90, green: 0.58, blue: 0.72)
        case .audio: Color(red: 0.70, green: 0.58, blue: 0.91)
        case .documents: Color(red: 0.48, green: 0.77, blue: 0.91)
        case .apps: Color(red: 0.54, green: 0.83, blue: 0.68)
        case .archives: Color(red: 0.92, green: 0.70, blue: 0.44)
        case .code: Color(red: 0.65, green: 0.76, blue: 0.94)
        case .other: Color(red: 0.52, green: 0.60, blue: 0.69)
        }
    }

    static func color(for node: FileNode) -> Color {
        let index = node.categoryBytes.enumerated().max { $0.element < $1.element }?.offset ?? FileCategory.other.rawValue
        return color(for: FileCategory(rawValue: index) ?? .other)
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .alert("Full Disk Access", isPresented: $model.showFullDiskAccessPrompt) {
                    Button("Open Settings") { model.completeFullDiskAccessPrompt(openSettings: true) }
                    Button("Later", role: .cancel) { model.completeFullDiskAccessPrompt(openSettings: false) }
                } message: {
                    Text("Add driveviewer in System Settings, then turn it on.")
                }
                .frame(width: 242)
            Rectangle().fill(UIStyle.line).frame(width: 1)
            main
        }
        .background(UIStyle.background)
        .confirmationDialog(
            "Move \(model.selectedNodes.count) item\(model.selectedNodes.count == 1 ? "" : "s") to Trash?",
            isPresented: $model.showTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { model.trashSelected() }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Could not move to Trash", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("OK") { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(UIStyle.accent)
                Text("driveviewer")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.top, 56)
            .padding(.bottom, 38)

            Text("LOCATION")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(UIStyle.secondary)
                .padding(.bottom, 13)

            HStack(spacing: 11) {
                Image(systemName: "internaldrive.fill")
                    .foregroundStyle(UIStyle.accent)
                    .frame(width: 19)
                Text(model.root?.name ?? model.scanURL?.lastPathComponent ?? "Home")
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(UIStyle.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))

            Button(action: model.chooseLocation) {
                Label("Choose folder or drive", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(UIStyle.secondary)
            .padding(.top, 3)

            Button(action: { model.openFullDiskAccessSettings() }) {
                Label("Full Disk Access", systemImage: "lock.shield")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(UIStyle.secondary)
            .help("Add driveviewer in System Settings")

            Rectangle().fill(UIStyle.line).frame(height: 1).padding(.vertical, 18)

            HStack {
                Text("CATEGORIES")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(UIStyle.secondary)
                Spacer()
                if model.categoryFilter != nil {
                    Button("Clear") { model.categoryFilter = nil }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(UIStyle.accent)
                }
            }
            .padding(.bottom, 12)

            ForEach(FileCategory.allCases) { category in
                CategoryRow(category: category, bytes: model.current?.categoryBytes[category.rawValue] ?? 0,
                            total: model.current?.size ?? 0, selected: model.categoryFilter == category) {
                    model.categoryFilter = model.categoryFilter == category ? nil : category
                    model.selectedIDs = []
                }
            }

            Spacer(minLength: 20)
            if model.volumeTotal > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("DRIVE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.6)
                        Spacer()
                        Text(sizeString(model.volumeTotal))
                    }
                    .foregroundStyle(UIStyle.secondary)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1))
                            Capsule().fill(UIStyle.accent)
                                .frame(width: geometry.size.width * CGFloat(max(0, min(1, Double(model.volumeTotal - model.volumeAvailable) / Double(model.volumeTotal)))))
                        }
                    }
                    .frame(height: 5)
                    HStack {
                        Text("Used \(sizeString(model.volumeTotal - model.volumeAvailable))")
                        Spacer()
                        Text("Free \(sizeString(model.volumeAvailable))")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(UIStyle.secondary)
                }
                .padding(.bottom, 20)
            }
            if let result = model.result {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(result.items.formatted()) items scanned")
                    if let current = model.current, current.directItemCount > current.children.count {
                        Text("\((current.directItemCount - current.children.count).formatted()) grouped")
                    }
                    if result.skipped > 0 { Text("\(result.skipped.formatted()) folders not scanned") }
                }
                .font(.system(size: 11))
                .foregroundStyle(UIStyle.secondary)
                .padding(.bottom, 20)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity)
        .background(UIStyle.sidebar)
    }

    private var main: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(UIStyle.line).frame(height: 1)
            if model.isScanning { scanningView }
            else if model.result == nil { emptyView }
            else {
                HStack(spacing: 0) {
                    mapSection
                    Rectangle().fill(UIStyle.line).frame(width: 1)
                    itemsSection.frame(width: 305)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if let root = model.root {
                        breadcrumb(root.name, index: -1)
                        ForEach(Array(model.navigation.enumerated()), id: \.element.id) { index, node in
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(UIStyle.secondary.opacity(0.65))
                            breadcrumb(node.name, index: index)
                        }
                    } else {
                        Text("Overview")
                            .font(.system(size: 22, weight: .semibold))
                    }
                }
                .lineLimit(1)
                if model.isScanning || model.result != nil {
                    Text(model.isScanning ? "Scanning" : sizeString(model.activeSize))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(UIStyle.secondary)
                }
            }
            Spacer(minLength: 8)
            if model.result != nil {
                if !model.selectedIDs.isEmpty {
                    Text("\(model.selectedIDs.count) selected · \(sizeString(model.selectedSize))")
                        .font(.system(size: 12))
                        .foregroundStyle(UIStyle.secondary)
                        .lineLimit(1)
                }
                headerButton("arrow.up.left", label: "Up", enabled: !model.navigation.isEmpty) { model.goUp() }
                headerButton("arrow.clockwise", label: "Refresh") { model.refresh() }
                headerButton("folder", label: "Finder") { model.revealCurrent() }
                Button { model.requestTrash() } label: {
                    Label("Trash", systemImage: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .frame(height: 34)
                        .padding(.horizontal, 11)
                }
                .buttonStyle(.plain)
                .background(model.selectedIDs.isEmpty ? UIStyle.panel : Color(red: 0.39, green: 0.19, blue: 0.23), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(model.selectedIDs.isEmpty ? UIStyle.secondary : .white)
                .disabled(model.selectedIDs.isEmpty)
            }
        }
        .padding(.leading, 28)
        .padding(.trailing, 25)
        .padding(.top, 32)
        .padding(.bottom, 22)
        .frame(height: 105)
    }

    private func breadcrumb(_ name: String, index: Int) -> some View {
        Button { model.go(to: index) } label: {
            Text(name)
                .font(.system(size: 20, weight: index == model.navigation.count - 1 ? .semibold : .regular))
                .foregroundStyle(index == model.navigation.count - 1 ? .white : UIStyle.secondary)
        }
        .buttonStyle(.plain)
        .disabled(model.isScanning)
    }

    private func headerButton(_ symbol: String, label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .background(UIStyle.panel, in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(UIStyle.secondary)
        .disabled(!enabled)
        .help(label)
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SPACE MAP")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(UIStyle.secondary)
                Spacer()
            }
            .padding(.bottom, 18)
            NestedTreemapView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 10) {
                ForEach(FileCategory.allCases) { category in
                    HStack(spacing: 5) {
                        Circle().fill(UIStyle.color(for: category)).frame(width: 6, height: 6)
                        Text(category.title).font(.system(size: 10))
                    }
                    .foregroundStyle(UIStyle.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 17)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("LARGEST ITEMS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(UIStyle.secondary)
                Spacer()
                Text(model.displayChildren.count.formatted())
                    .font(.system(size: 11))
                    .foregroundStyle(UIStyle.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 25)
            .padding(.bottom, 14)
            Rectangle().fill(UIStyle.line).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.displayChildren) { node in
                        ItemRow(node: node, size: model.categoryFilter.map { node.categoryBytes[$0.rawValue] } ?? node.size,
                                selected: model.selectedIDs.contains(node.id), model: model)
                    }
                }
            }
        }
        .background(UIStyle.sidebar.opacity(0.48))
    }

    private var scanningView: some View {
        VStack(spacing: 20) {
            ProgressView().controlSize(.large).tint(UIStyle.accent)
            Text("Scanning \(model.progress?.items.formatted() ?? "0") items")
                .font(.system(size: 19, weight: .medium))
            Text(sizeString(model.progress?.bytes ?? 0))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(UIStyle.secondary)
            Text(model.progress?.currentPath ?? "")
                .font(.system(size: 11))
                .foregroundStyle(UIStyle.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 420)
            Button("Cancel") { model.cancelScan() }
                .buttonStyle(.plain)
                .foregroundStyle(UIStyle.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 18) {
            Image(systemName: "internaldrive")
                .font(.system(size: 45, weight: .ultraLight))
                .foregroundStyle(UIStyle.secondary)
            Text("No scan")
                .font(.system(size: 20, weight: .medium))
            Button("Scan") { model.refresh() }
                .buttonStyle(.borderedProminent)
                .tint(UIStyle.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NestedTreemapView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GeometryReader { geometry in
            let tiles = model.current.map {
                NestedTreemapLayout.layout(root: $0, filter: model.categoryFilter,
                                            in: CGRect(origin: .zero, size: geometry.size))
            } ?? []
            ZStack(alignment: .topLeading) {
                ForEach(tiles) { tile in
                    let rect = tile.rect
                    let node = tile.item.node
                    let color = node.map { UIStyle.color(for: $0) } ?? UIStyle.secondary
                    RoundedRectangle(cornerRadius: tile.depth == 0 ? 9 : 5)
                        .fill(color.opacity(tile.showsChildren ? 0.17 : 0.30))
                        .overlay {
                            RoundedRectangle(cornerRadius: tile.depth == 0 ? 9 : 5)
                                .strokeBorder(model.selectedIDs.contains(node?.id ?? "") ? UIStyle.accent : color.opacity(0.45),
                                              lineWidth: model.selectedIDs.contains(node?.id ?? "") ? 2 : 1)
                        }
                        .overlay(alignment: .topLeading) {
                            if rect.width > 82 && rect.height > 42 {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(tile.item.title)
                                        .font(.system(size: tile.depth == 0 ? 13 : 11, weight: .semibold))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 0)
                                    if rect.width > 155 {
                                        Text(sizeString(tile.item.size))
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.68))
                                            .lineLimit(1)
                                    }
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, tile.depth == 0 ? 11 : 8)
                                .padding(.top, tile.depth == 0 ? 9 : 6)
                            }
                        }
                        .frame(width: max(0, rect.width), height: max(0, rect.height))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            if let node { model.open(node) }
                        }
                        .onTapGesture {
                            if let node { model.select(node, extending: NSEvent.modifierFlags.contains(.command)) }
                        }
                        .contextMenu {
                            if let node {
                                if node.isDirectory { Button("Open") { model.open(node) } }
                                Button("Reveal in Finder") { model.reveal(node) }
                                Divider()
                                Button("Move to Trash") { model.requestTrash([node]) }
                            }
                        }
                        .help(node?.url.path ?? tile.item.title)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .background(UIStyle.panel, in: RoundedRectangle(cornerRadius: 11))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }
}

private struct CategoryRow: View {
    let category: FileCategory
    let bytes: Int64
    let total: Int64
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: category.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(UIStyle.color(for: category))
                    .frame(width: 19)
                Text(category.title)
                    .foregroundStyle(.white.opacity(bytes == 0 ? 0.5 : 0.9))
                Spacer(minLength: 2)
                Text(sizeString(bytes))
                    .foregroundStyle(UIStyle.secondary)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(selected ? Color.white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(bytes == 0)
    }
}

private struct ItemRow: View {
    let node: FileNode
    let size: Int64
    let selected: Bool
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 5)
                .fill(UIStyle.color(for: node).opacity(0.18))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: node.isDirectory ? "folder.fill" : node.category.symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(UIStyle.color(for: node))
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(node.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(node.isDirectory ? "Folder" : node.category.title)
                    .font(.system(size: 10))
                    .foregroundStyle(UIStyle.secondary)
            }
            Spacer(minLength: 2)
            Text(sizeString(size))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(UIStyle.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 15)
        .frame(height: 54)
        .background(selected ? UIStyle.accent.opacity(0.13) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.open(node) }
        .onTapGesture { model.select(node, extending: NSEvent.modifierFlags.contains(.command)) }
        .contextMenu {
            if node.isDirectory { Button("Open") { model.open(node) } }
            Button("Reveal in Finder") { model.reveal(node) }
            Divider()
            Button("Move to Trash") { model.requestTrash([node]) }
        }
    }
}

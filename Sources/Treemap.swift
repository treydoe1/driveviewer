import SwiftUI

struct MapItem: Identifiable {
    let node: FileNode?
    let size: Int64
    let title: String
    var id: String { node?.id ?? "__remaining" }
}

struct MapRect: Identifiable {
    let item: MapItem
    let rect: CGRect
    var id: String { item.id }
}

struct NestedMapRect: Identifiable {
    let item: MapItem
    let parentID: String
    let rect: CGRect
    let depth: Int
    let showsChildren: Bool

    var id: String { item.node?.id ?? parentID + "/__other" }
}

enum NestedTreemapLayout {
    static func layout(root: FileNode, filter: FileCategory?, in bounds: CGRect, maxDepth: Int = 3) -> [NestedMapRect] {
        var output: [NestedMapRect] = []

        func visit(_ parent: FileNode, bounds: CGRect, depth: Int) {
            let children = parent.sortedChildren(matching: filter)
            let shown = children.reduce(Int64(0)) { sum, child in
                sum + (filter.map { child.categoryBytes[$0.rawValue] } ?? child.size)
            }
            let total = filter.map { parent.categoryBytes[$0.rawValue] } ?? parent.size
            var items = children.map { child in
                MapItem(node: child,
                        size: filter.map { child.categoryBytes[$0.rawValue] } ?? child.size,
                        title: child.name)
            }
            let remaining = max(0, total - shown)
            if remaining > 0 { items.append(MapItem(node: nil, size: remaining, title: "Other items")) }

            for entry in TreemapLayout.layout(items, in: bounds) {
                let rect = entry.rect.insetBy(dx: depth == 0 ? 3 : 2, dy: depth == 0 ? 3 : 2)
                let child = entry.item.node
                let nested = depth < maxDepth && child?.isDirectory == true &&
                    child?.children.isEmpty == false && rect.width >= 180 && rect.height >= 125
                output.append(NestedMapRect(item: entry.item, parentID: parent.id,
                                            rect: rect, depth: depth, showsChildren: nested))
                if nested, let child {
                    let inner = CGRect(x: rect.minX + 6, y: rect.minY + 31,
                                       width: rect.width - 12, height: rect.height - 37)
                    visit(child, bounds: inner, depth: depth + 1)
                }
            }
        }

        visit(root, bounds: bounds, depth: 0)
        return output
    }
}

enum TreemapLayout {
    static func layout(_ items: [MapItem], in bounds: CGRect) -> [MapRect] {
        guard !items.isEmpty, bounds.width > 0, bounds.height > 0 else { return [] }
        let total = Double(items.reduce(Int64(0)) { $0 + max(0, $1.size) })
        guard total > 0 else { return [] }
        let area = bounds.width * bounds.height
        var remaining = bounds
        var pending = items.map { (item: $0, area: CGFloat(Double(max(0, $0.size)) / total) * area) }
        var results: [MapRect] = []

        func worst(_ row: ArraySlice<(item: MapItem, area: CGFloat)>, short: CGFloat) -> CGFloat {
            let sum = row.reduce(CGFloat(0)) { $0 + $1.area }
            guard sum > 0, short > 0 else { return .infinity }
            let largest = row.map(\.area).max() ?? 0
            let smallest = row.map(\.area).min() ?? 0
            guard smallest > 0 else { return .infinity }
            return max(short * short * largest / (sum * sum), (sum * sum) / (short * short * smallest))
        }

        while !pending.isEmpty {
            let horizontal = remaining.width >= remaining.height
            let short = min(remaining.width, remaining.height)
            var rowCount = 1
            while rowCount < pending.count {
                let current = worst(pending.prefix(rowCount), short: short)
                let next = worst(pending.prefix(rowCount + 1), short: short)
                if next > current { break }
                rowCount += 1
            }
            let row = pending.prefix(rowCount)
            let rowArea = row.reduce(CGFloat(0)) { $0 + $1.area }
            if horizontal {
                let width = remaining.height > 0 ? rowArea / remaining.height : 0
                var y = remaining.minY
                for entry in row {
                    let height = width > 0 ? entry.area / width : 0
                    results.append(MapRect(item: entry.item, rect: CGRect(x: remaining.minX, y: y, width: width, height: height)))
                    y += height
                }
                remaining.origin.x += width
                remaining.size.width = max(0, remaining.width - width)
            } else {
                let height = remaining.width > 0 ? rowArea / remaining.width : 0
                var x = remaining.minX
                for entry in row {
                    let width = height > 0 ? entry.area / height : 0
                    results.append(MapRect(item: entry.item, rect: CGRect(x: x, y: remaining.minY, width: width, height: height)))
                    x += width
                }
                remaining.origin.y += height
                remaining.size.height = max(0, remaining.height - height)
            }
            pending.removeFirst(rowCount)
        }
        return results
    }
}

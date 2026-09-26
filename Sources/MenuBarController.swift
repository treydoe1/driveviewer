import AppKit

@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private weak var model: AppModel?
    private var openWindow: (() -> Void)?
    private var statusItem: NSStatusItem?
    private var capacityItem: NSMenuItem?
    private var timer: Timer?

    func install(model: AppModel, openWindow: @escaping () -> Void) {
        self.model = model
        self.openWindow = openWindow
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        let capacity = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        capacity.isEnabled = false
        menu.addItem(capacity)
        menu.addItem(.separator())

        let scan = NSMenuItem(title: "Scan Drive", action: #selector(scanDrive), keyEquivalent: "")
        scan.target = self
        menu.addItem(scan)

        let show = NSMenuItem(title: "Open driveviewer", action: #selector(showWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        item.menu = menu
        statusItem = item
        capacityItem = capacity
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    private func refresh() {
        let capacity = DiskCapacity.startupDisk()
        statusItem?.button?.title = capacity?.percentLabel ?? "?%"
        capacityItem?.title = capacity.map { "\(sizeString($0.available)) free of \(sizeString($0.total))" } ?? "Disk space unavailable"
    }

    @objc private func scanDrive() {
        model?.scan(URL(fileURLWithPath: "/", isDirectory: true))
        showWindow()
    }

    @objc private func showWindow() {
        openWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }
}

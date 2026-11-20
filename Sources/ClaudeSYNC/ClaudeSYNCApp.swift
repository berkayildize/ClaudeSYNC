import AppKit
import Combine
import SwiftUI

@main
@MainActor
final class ClaudeSYNCEntryPoint {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let viewModel = AppViewModel()
    private var mainWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isSnapshotMode = CommandLine.arguments.contains("--snapshot")
            || CommandLine.arguments.contains("--demo-snapshot")

        if isSnapshotMode {
            NSApp.setActivationPolicy(.accessory)
            _ = SnapshotRenderer.runIfRequested(viewModel: viewModel)
            return
        }

        // Standard native macOS app menu (⌘Q, ⌘W, ⌘O, ⌘R, ⌘⇧M, ⌘C/V/X/A)
        installMainMenu()

        // Wire open-window & language-change handlers
        viewModel.openMainWindowAction = { [weak self] in
            self?.showMainWindow()
        }
        viewModel.languageChangedAction = { [weak self] in
            guard let self else { return }
            self.installMainMenu()
            self.updateStatusItemTooltip()
            self.updateStatusItemImage()
        }

        // Observe Menu Bar visibility toggle & live image updates
        viewModel.$showMenuBarExtra
            .removeDuplicates()
            .sink { [weak self] show in
                self?.syncStatusItemVisibility(show: show)
            }
            .store(in: &cancellables)

        // Re-render status bar image only when accounts, settings, or theme actually change
        Publishers.CombineLatest4(
            viewModel.$accounts,
            viewModel.$settings.map(\.menuBarDisplayMode).removeDuplicates(),
            viewModel.$isSwitchingNow.removeDuplicates(),
            viewModel.$appearanceTick
        )
        .debounce(for: .milliseconds(60), scheduler: RunLoop.main)
        .sink { [weak self] _, _, _, _ in
            self?.updateStatusItemImage()
        }
        .store(in: &cancellables)

        syncStatusItemVisibility(show: viewModel.showMenuBarExtra)

        // Open full standalone macOS Desktop Window cleanly on launch
        NSApp.setActivationPolicy(.regular)
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep alive if Menu Bar icon is enabled and user chose background mode
        if viewModel.showMenuBarExtra && viewModel.settings.keepRunningInMenuBarOnClose {
            return false
        }
        return false
    }

    // MARK: - Standalone Main Desktop Window

    private func ensureMainWindow() -> NSWindow {
        if let existing = mainWindow {
            return existing
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "ClaudeSYNC"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 800, height: 580)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let hosting = NSHostingController(rootView: MainWindowView(viewModel: viewModel, includeTrafficLightInset: true))
        window.contentViewController = hosting
        mainWindow = window
        return window
    }

    func showMainWindow() {
        popover?.performClose(nil)
        NSApp.setActivationPolicy(.regular)
        let win = ensureMainWindow()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if viewModel.showMenuBarExtra && viewModel.settings.keepRunningInMenuBarOnClose {
            // Optionally hide Dock icon while running purely in Menu Bar until reopened
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Toggleable macOS Menu Bar Status Item & Popover

    private func syncStatusItemVisibility(show: Bool) {
        if show {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = item.button {
                    button.target = self
                    button.action = #selector(handleStatusBarClick(_:))
                    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                    button.toolTip = viewModel.l10n.t(
                        "ClaudeSYNC — Sol tık: Hızlı Menü · Sağ tık: Kısayollar",
                        "ClaudeSYNC — Left-click: Quick Menu · Right-click: Shortcuts"
                    )
                }
                statusItem = item
            }
            updateStatusItemImage()
        } else {
            popover?.performClose(nil)
            if let existing = statusItem {
                NSStatusBar.system.removeStatusItem(existing)
                statusItem = nil
            }
            // Guarantee Dock icon & main window stay accessible when Menu Bar is hidden
            NSApp.setActivationPolicy(.regular)
        }
    }

    private func updateStatusItemTooltip() {
        statusItem?.button?.toolTip = viewModel.l10n.t(
            "ClaudeSYNC — Sol tık: Hızlı Menü · Sağ tık: Kısayollar",
            "ClaudeSYNC — Left-click: Quick Menu · Right-click: Shortcuts"
        )
    }

    private func updateStatusItemImage() {
        guard let button = statusItem?.button else { return }
        button.image = viewModel.menuBarImage
        button.imagePosition = .imageOnly
    }

    @objc private func handleStatusBarClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(relativeTo: sender)
            return
        }

        if event.type == .rightMouseUp {
            showStatusBarContextMenu(from: sender)
        } else {
            togglePopover(relativeTo: sender)
        }
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        if let pop = popover, pop.isShown {
            pop.performClose(nil)
            return
        }

        let pop = popover ?? {
            let p = NSPopover()
            p.contentSize = NSSize(width: BridgeTheme.popoverWidth, height: BridgeTheme.popoverHeight)
            p.behavior = .transient
            p.animates = true
            p.contentViewController = NSHostingController(rootView: MenuBarContentView(viewModel: viewModel))
            popover = p
            return p
        }()

        viewModel.refresh(userInitiated: false)
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        pop.contentViewController?.view.window?.makeKey()
    }

    private func showStatusBarContextMenu(from button: NSStatusBarButton) {
        let t = viewModel.l10n
        let menu = NSMenu()
        let openItem = NSMenuItem(title: t.t("ClaudeSYNC Penceresini Aç", "Open ClaudeSYNC Window"), action: #selector(handleOpenMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let syncItem = NSMenuItem(title: t.t("Tüm Aktif Oturumları Eşitle", "Sync All Active Sessions"), action: #selector(handleQuickSync), keyEquivalent: "")
        syncItem.target = self
        menu.addItem(syncItem)

        let refreshItem = NSMenuItem(title: t.t("Yenile", "Refresh"), action: #selector(handleRefresh), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let hideBarItem = NSMenuItem(title: t.t("Üst Bar Simgesini Gizle", "Hide Menu Bar Icon"), action: #selector(handleToggleMenuBar), keyEquivalent: "")
        hideBarItem.target = self
        menu.addItem(hideBarItem)

        let quitItem = NSMenuItem(title: t.t("ClaudeSYNC'ten Çık", "Quit ClaudeSYNC"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    // MARK: - Native AppKit Application Menu

    private func installMainMenu() {
        let t = viewModel.l10n
        let mainMenu = NSMenu()

        // 1. ClaudeSYNC Application Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "ClaudeSYNC")
        appMenu.addItem(NSMenuItem(title: t.t("ClaudeSYNC Hakkında", "About ClaudeSYNC"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        let wizardItem = NSMenuItem(title: t.t("İlk Kurulum Sihirbazı...", "Setup Wizard..."), action: #selector(handleOpenOnboarding), keyEquivalent: "")
        wizardItem.target = self
        appMenu.addItem(wizardItem)
        appMenu.addItem(.separator())
        let hideItem = NSMenuItem(title: t.t("ClaudeSYNC'i Gizle", "Hide ClaudeSYNC"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hideItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: t.t("ClaudeSYNC'ten Çık", "Quit ClaudeSYNC"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. Actions Menu
        let actionsMenuItem = NSMenuItem()
        let actionsMenu = NSMenu(title: t.t("İşlemler", "Actions"))

        let openItem = NSMenuItem(title: t.t("Ana Pencereyi Aç", "Open Main Window"), action: #selector(handleOpenMainWindow), keyEquivalent: "o")
        openItem.target = self
        actionsMenu.addItem(openItem)

        let refreshItem = NSMenuItem(title: t.t("Yenile", "Refresh"), action: #selector(handleRefresh), keyEquivalent: "r")
        refreshItem.target = self
        actionsMenu.addItem(refreshItem)

        let syncItem = NSMenuItem(title: t.t("Tüm Aktifleri Eşitle", "Sync All Active"), action: #selector(handleQuickSync), keyEquivalent: "s")
        syncItem.keyEquivalentModifierMask = [.command, .shift]
        syncItem.target = self
        actionsMenu.addItem(syncItem)

        actionsMenu.addItem(.separator())

        let toggleBarItem = NSMenuItem(title: t.t("Üst Bar Simgesini Aç/Kapat", "Toggle Menu Bar Icon"), action: #selector(handleToggleMenuBar), keyEquivalent: "m")
        toggleBarItem.keyEquivalentModifierMask = [.command, .shift]
        toggleBarItem.target = self
        actionsMenu.addItem(toggleBarItem)

        actionsMenu.addItem(.separator())
        actionsMenu.addItem(NSMenuItem(title: t.t("Pencereyi Kapat", "Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        actionsMenuItem.submenu = actionsMenu
        mainMenu.addItem(actionsMenuItem)

        // 3. Edit Menu — enables ⌘C, ⌘V, ⌘X, ⌘A inside TextFields
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: t.t("Düzenle", "Edit"))
        editMenu.addItem(NSMenuItem(title: t.t("Geri Al", "Undo"), action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: t.t("Kes", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: t.t("Kopyala", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: t.t("Yapıştır", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: t.t("Tümünü Seç", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func handleOpenOnboarding() {
        viewModel.reopenOnboarding()
        showMainWindow()
    }

    @objc private func handleOpenMainWindow() {
        showMainWindow()
    }

    @objc private func handleRefresh() {
        viewModel.refresh(userInitiated: true)
    }

    @objc private func handleQuickSync() {
        viewModel.syncAllActive(bidirectional: true)
    }

    @objc private func handleToggleMenuBar() {
        viewModel.setShowMenuBarExtra(!viewModel.showMenuBarExtra)
    }
}

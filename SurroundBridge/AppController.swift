//
//  AppController.swift
//  SurroundBridge
//
//  Glue between SoundPusher's Objective-C app delegate (menu bar icon, audio chains) and the SwiftUI window.
//

import AppKit
import SwiftUI

@objc(SBAppController)
final class AppController: NSObject, NSWindowDelegate, NSMenuDelegate {
    @objc static let shared = AppController()

    private var window: NSWindow?
    private weak var statusMenu: NSMenu?
    private let bypassItem = NSMenuItem(title: "Bypass Processing", action: #selector(toggleBypass), keyEquivalent: "")
    private let presetsMenu = NSMenu(title: "Presets")
    private let spotsMenu = NSMenu(title: "Listening Position")

    private var model: BridgeModel { BridgeModel.shared }

    // MARK: menu bar

    /// Adds SurroundBridge's items to the menu bar menu. Called once by the app delegate at launch.
    @objc(installInMenu:)
    func install(in menu: NSMenu) {
        statusMenu = menu

        let open = NSMenuItem(title: "Open SurroundBridge…", action: #selector(showWindow), keyEquivalent: "")
        open.target = self
        bypassItem.target = self
        let presets = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        presets.submenu = presetsMenu
        presetsMenu.delegate = self
        let spots = NSMenuItem(title: "Listening Position", action: nil, keyEquivalent: "")
        spots.submenu = spotsMenu
        spotsMenu.delegate = self

        // SoundPusher inserts its "source → output" items above whatever is in the menu at launch, so ours go on top here.
        for (index, item) in [NSMenuItem.separator(), open, bypassItem, presets, spots, NSMenuItem.separator()].enumerated() {
            menu.insertItem(item, at: index)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(chainsChanged),
                                               name: .SBChainsDidChange, object: nil)
        chainsChanged()
    }

    @objc private func chainsChanged() {
        model.outputName = (NSApp.delegate as? AppDelegate)?.activeOutputName()
    }

    @objc private func toggleBypass() {
        model.state.bypass.toggle()
    }

    @objc private func loadPresetFromMenu(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { model.loadPreset(named: name) }
    }

    @objc private func goToSpotFromMenu(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String,
           let spot = model.state.room.spots.first(where: { $0.name == name }) {
            model.goToSpot(spot)
        }
    }

    @objc private func togglePositionAdjustment() {
        model.state.room.compensate.toggle()
    }

    private func rebuildSpotsMenu() {
        spotsMenu.removeAllItems()
        let toggle = NSMenuItem(title: "Adjust Speakers for My Position", action: #selector(togglePositionAdjustment), keyEquivalent: "")
        toggle.target = self
        toggle.state = model.state.room.compensate ? .on : .off
        spotsMenu.addItem(toggle)
        spotsMenu.addItem(.separator())
        if model.state.room.spots.isEmpty {
            let empty = NSMenuItem(title: "No saved spots yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            spotsMenu.addItem(empty)
        }
        for spot in model.state.room.spots {
            let item = NSMenuItem(title: spot.name, action: #selector(goToSpotFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = spot.name
            item.state = model.currentSpot == spot && model.state.room.compensate ? .on : .off
            spotsMenu.addItem(item)
        }
    }

    /// Rebuilds the Presets and Listening Position submenus each time they open.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === spotsMenu { rebuildSpotsMenu(); return }
        guard menu === presetsMenu else { return }
        menu.removeAllItems()
        model.refreshPresets()
        if model.presetNames.isEmpty {
            let empty = NSMenuItem(title: "No saved presets yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for name in model.presetNames {
            let item = NSMenuItem(title: name, action: #selector(loadPresetFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = name == model.currentPresetName ? .on : .off
            menu.addItem(item)
        }
    }

    /// Keeps the Bypass checkmark in sync. Called for our items just before the menu is shown.
    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item === bypassItem { item.state = model.state.bypass ? .on : .off }
        return true
    }

    /// Shows SoundPusher's device menu at the mouse position (used by the "Output" button in the window).
    func popUpOutputMenu() {
        guard let statusMenu else { return }
        statusMenu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: window

    @objc func showWindow() {
        if window == nil {
            let hosting = NSHostingController(rootView: ContentView()
                .environment(BridgeModel.shared)
                .environment(MeterModel.shared))
            let window = NSWindow(contentViewController: hosting)
            window.title = "SurroundBridge"
            // match the window frame to the app's own dark navy look
            window.appearance = NSAppearance(named: .darkAqua)
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(red: 0.086, green: 0.110, blue: 0.157, alpha: 1)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 1180, height: 800))
            window.center()
            window.setFrameAutosaveName("SurroundBridgeMainWindow")
            self.window = window
        }
        installMainMenuIfNeeded()
        // While the window is open we behave like a normal app (Dock icon, menus); otherwise we live in the menu bar only.
        NSApp.setActivationPolicy(.regular)
        MeterModel.shared.start()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(nil)   // don't start with the cursor blinking in a text field
    }

    /// Developer aid: launching with `-SBSnapshot <tab>` saves a picture of the window to the app's temporary folder,
    /// so the layout can be checked without screen-recording permission. `<tab>` is speakers, routing or bass.
    @objc func saveSnapshotIfRequested() {
        guard let tab = UserDefaults.standard.string(forKey: "SBSnapshot") else { return }
        if UserDefaults.standard.bool(forKey: "SBSnapshotDemo") {
            // show the position feature in the picture without changing any saved settings
            BridgeModel.shared.loadDemoStateForSnapshot()
        }
        showWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let view = self?.window?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snapshot-\(tab).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            NSLog("SurroundBridge snapshot saved to %@", url.path)
            NSApp.terminate(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        MeterModel.shared.stop()
        model.stopTone()
        NSApp.setActivationPolicy(.accessory)
    }

    /// A minimal main menu so standard shortcuts (⌘Q, ⌘W, copy/paste in text fields) work.
    private func installMainMenuIfNeeded() {
        guard NSApp.mainMenu == nil || NSApp.mainMenu?.items.isEmpty == true else { return }
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About SurroundBridge", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide SurroundBridge", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit SurroundBridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}

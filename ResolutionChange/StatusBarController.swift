import Cocoa  // macOSアプリの基本機能（UI含む）を提供するフレームワークをインポート
import SwiftUI
import ServiceManagement  // アプリのログイン時自動起動を制御するためのフレームワークをインポート
import CoreGraphics // ディスプレイ情報にアクセスするためにインポート
import Combine

// ディスプレイ再構成コールバック関数
private func displayReconfigurationCallback(display: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags, userInfo: UnsafeMutableRawPointer?) {
    // userInfoからStatusBarControllerのインスタンスを取得
    if let userInfo = userInfo {
        let controller = Unmanaged<StatusBarController>.fromOpaque(userInfo).takeUnretainedValue()
        // ディスプレイ構成の変更があった場合にメニューを更新
        // .beginConfigurationFlag は多くの変更で発生するため、ここで更新をかける
        if flags.contains(.beginConfigurationFlag) || flags.contains(.addFlag) || flags.contains(.removeFlag) {
            // メインスレッドでUI更新を実行
            DispatchQueue.main.async {
                controller.handleDisplayReconfiguration()
            }
        }
    }
}

// ステータスバーのコントローラークラス（NSStatusItemとメニューを管理）
@MainActor
final class StatusBarController: NSObject {
    // MARK: - Properties
    private var statusItem: NSStatusItem!
    private let resolutionManager = ResolutionManager()
    private let store = InAppPurchaseManager()
    private var cancellables = Set<AnyCancellable>()
    private var purchaseWindow: NSWindow?

    // MARK: - Constants
    private enum UI {
        static let displayMenuTitle = "Display"
        static let favoriteMenuTitle = "Favorite"
        static let refreshListTitle = "Refresh List"
        static let autoRunTitle = "Auto Run"
        static let unlockFeatureTitle = "Unlock Favorite Feature..."
        static let quitTitle = "Quit"
        static let noDisplaysFoundTitle = "ディスプレイが見つかりません"
    }

    private enum UserDefaultsKeys {
        // [String: [String]] の形式で保存 (CGDirectDisplayIDはIntなのでStringに変換)
        static let favoriteResolutionsByDisplay = "FavoriteResolutionsByDisplay"
    }

    
    // 初期化処理
    override init() {
        super.init()
        // ステータスバーに四角い長さでアイコンを登録
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // ボタン部分（アイコン）が取得できればシステム画像を設定
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Resolution")
        }

        store.$hasUnlockedFullVersion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshMenu()
            }
            .store(in: &cancellables)

        // メニュー構築関数の呼び出し
        constructMenu()

        // ディスプレイ再構成コールバックを登録
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, pointer)
    }

    deinit {
        // コールバックの登録を解除
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, pointer)
    }
    
    private func constructMenu() {
        let menu = NSMenu()
        let displays = resolutionManager.getDisplays()

        if displays.isEmpty {
            buildEmptyMenu(on: menu)
            statusItem.menu = menu
            return
        }

        // 各ディスプレイのお気に入りをトップレベルに表示
        for display in displays {
            buildFavoritesMenu(for: display, on: menu, displayCount: displays.count)
        }

        if displays.contains(where: { !getFavoriteResolutions(for: $0.id).isEmpty }) {
             menu.addItem(NSMenuItem.separator())
        }

        // 各ディスプレイのメニューを構築
        for display in displays {
            buildDisplaySubMenu(for: display, on: menu)
        }

        menu.addItem(NSMenuItem.separator())

        // 各ディスプレイのお気に入り管理メニューを構築
        for display in displays {
            buildFavoriteManagementSubMenu(for: display, on: menu)
        }

        menu.addItem(NSMenuItem.separator())

        // コントロール項目を構築
        buildControlMenu(on: menu)

        statusItem.menu = menu
    }

    private func buildEmptyMenu(on menu: NSMenu) {
        let errorItem = NSMenuItem(title: UI.noDisplaysFoundTitle, action: nil, keyEquivalent: "")
        errorItem.isEnabled = false
        menu.addItem(errorItem)
        menu.addItem(NSMenuItem.separator())
        let refreshItem = NSMenuItem(title: UI.refreshListTitle, action: #selector(refreshMenu), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(NSMenuItem(title: UI.quitTitle, action: #selector(quitApp), keyEquivalent: "q").then {
            $0.target = self
        })
    }

    private func buildFavoritesMenu(for display: Display, on menu: NSMenu, displayCount: Int) {
        let favoriteStrings = getFavoriteResolutions(for: display.id)
        if favoriteStrings.isEmpty { return }

        let currentMode = CGDisplayCopyDisplayMode(display.id)
        let currentRes = currentMode.map { "\($0.width)x\($0.height)" }

        // お気に入り解像度をピクセル数（面積）で降順に並べる
        let sortedFavorites = favoriteStrings.sorted { a, b in
            guard let (aw, ah) = parseResolutionString(a), let (bw, bh) = parseResolutionString(b) else { return a < b }
            return (aw * ah) > (bw * bh)
        }

        // 並べたお気に入りをメニューに追加
        for fav in sortedFavorites {
            guard let (w, h) = parseResolutionString(fav),
                  let mode = display.modes.first(where: { $0.width == w && $0.height == h }) else { continue }
            
            let title = displayCount > 1 ? "🖥️\(display.id): \(fav)" : fav
            let item = NSMenuItem(title: title, action: #selector(favoriteResolutionSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = (display.id, mode)

            if fav == currentRes {
                item.state = .on
            }
            
            if !store.hasUnlockedFullVersion {
                let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.disabledControlTextColor]
                item.attributedTitle = NSAttributedString(string: title, attributes: attributes)
            }
            menu.addItem(item)
        }
    }

    private func buildDisplaySubMenu(for display: Display, on menu: NSMenu) {
        let displayItem = NSMenuItem(title: "\(UI.displayMenuTitle) \(display.id)", action: nil, keyEquivalent: "")
        let subMenu = NSMenu()
        let currentMode = CGDisplayCopyDisplayMode(display.id)
        
        for mode in display.modes {
            let title = "\(mode.width)x\(mode.height)"
            let item = NSMenuItem(title: title, action: #selector(changeResolution(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = (display.id, mode)
            item.isEnabled = resolutionManager.canSetResolution(displayID: display.id, mode: mode)
            
            if let cur = currentMode, cur.ioDisplayModeID == mode.ioDisplayModeID {
                item.state = .on
            }
            subMenu.addItem(item)
        }
        displayItem.submenu = subMenu
        menu.addItem(displayItem)
    }

    private func buildFavoriteManagementSubMenu(for display: Display, on menu: NSMenu) {
        let favoriteItem = NSMenuItem(title: "\(UI.favoriteMenuTitle) (Display \(display.id))", action: nil, keyEquivalent: "")
        let subMenu = NSMenu()
        let favoriteStrings = getFavoriteResolutions(for: display.id)

        for mode in display.modes {
            let resStr = "\(mode.width)x\(mode.height)"
            let item = NSMenuItem(title: resStr, action: #selector(toggleFavorite(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = (display.id, resStr) // display.id を含める
            if favoriteStrings.contains(resStr) {
                item.state = .on
            }
            subMenu.addItem(item)
        }
        favoriteItem.submenu = subMenu
        menu.addItem(favoriteItem)
    }

    private func buildControlMenu(on menu: NSMenu) {
        // Refresh List
        menu.addItem(NSMenuItem(title: UI.refreshListTitle, action: #selector(refreshMenu), keyEquivalent: "r").then {
            $0.target = self
        })
        
        // Auto Run
        let autorunItem = NSMenuItem(title: UI.autoRunTitle, action: #selector(AppDelegate.toggleAutorun(_:)), keyEquivalent: "")
        autorunItem.target = NSApp.delegate
        autorunItem.state = isLoginItemEnabled() ? .on : .off
        menu.addItem(autorunItem)
        
        // Unlock Feature
        if !store.hasUnlockedFullVersion {
            menu.addItem(NSMenuItem(title: UI.unlockFeatureTitle, action: #selector(showPurchaseWindow), keyEquivalent: "").then {
                $0.target = self
            })
        }
        
        menu.addItem(NSMenuItem.separator())

        // Quit
        menu.addItem(NSMenuItem(title: UI.quitTitle, action: #selector(quitApp), keyEquivalent: "q").then {
            $0.target = self
        })
    }

    // ディスプレイ構成が変更されたときにコールバックから呼び出される
    func handleDisplayReconfiguration() {
        //print("Display reconfiguration detected. Refreshing menu.")
        refreshMenu()
    }

    @objc private func showPurchaseWindow() {
        if self.purchaseWindow == nil {
            // SwiftUIビューを生成
            let purchaseView = PurchaseView(store: self.store)
            // NSHostingViewでSwiftUIビューをラップ
            let hostingView = NSHostingView(rootView: purchaseView)

            // ウィンドウを生成
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false)
            window.center()
            window.setFrameAutosaveName("PurchaseWindow")
            window.contentView = hostingView
            window.title = "Unlock Full Version"
            // isReleasedWhenClosedをfalseに設定（デフォルトですが、明示的に）
            // これにより、ウィンドウは閉じられてもメモリに残り、再利用可能
            window.isReleasedWhenClosed = false
            // ウィンドウレベルを上げて、他のウィンドウより手前に表示
            window.level = .floating

            self.purchaseWindow = window
        }

        self.purchaseWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func favoriteResolutionSelected(_ sender: NSMenuItem) {
        if store.hasUnlockedFullVersion {
            changeResolution(sender)
        } else {
            showPurchaseWindow()
        }
    }

    // MARK: - Favorite Management
    
    // お気に入りのオン・オフを切り替えるアクション
    @objc private func toggleFavorite(_ sender: NSMenuItem) {
        guard let (displayID, resStr) = sender.representedObject as? (CGDirectDisplayID, String) else { return }
        
        var allFavorites = getAllFavoriteResolutions()
        var displayFavorites = allFavorites[String(displayID)] ?? []
        
        if displayFavorites.contains(resStr) {
            // すでに登録されている → 削除
            displayFavorites.removeAll { $0 == resStr }
        } else {
            // 登録されていない → 追加
            displayFavorites.append(resStr)
        }

        allFavorites[String(displayID)] = displayFavorites

        // UserDefaultsに保存
        UserDefaults.standard.set(allFavorites, forKey: UserDefaultsKeys.favoriteResolutionsByDisplay)

        // メニューを再構築して見た目を更新
        refreshMenu()
    }
    
    // 指定されたディスプレイのお気に入り解像度リストを取得
    private func getFavoriteResolutions(for displayID: CGDirectDisplayID) -> [String] {
        let allFavorites = getAllFavoriteResolutions()
        return allFavorites[String(displayID)] ?? []
    }

    // すべてのディスプレイのお気に入り解像度を辞書形式で取得
    private func getAllFavoriteResolutions() -> [String: [String]] {
        return UserDefaults.standard.dictionary(forKey: UserDefaultsKeys.favoriteResolutionsByDisplay) as? [String: [String]] ?? [:]
    }
    
    // "1440x900" のような文字列を (Int, Int) に変換するユーティリティ
    private func parseResolutionString(_ string: String) -> (Int, Int)? {
        let parts = string.split(separator: "x")
        guard parts.count == 2,
              let w = Int(parts[0]),
              let h = Int(parts[1]) else { return nil }
        return (w, h)
    }
    
    // メニューを再構築するためのアクション
    @objc private func refreshMenu() {
        constructMenu()
    }
    
    // 解像度を変更するアクション（NSMenuItem から情報を取得）
    @objc private func changeResolution(_ sender: NSMenuItem) {
        
//        if(!store.hasUnlockedFullVersion){return}
        
        guard let (displayID, mode) = sender.representedObject as? (CGDirectDisplayID, CGDisplayMode) else {
            //print("representedObject not set correctly")
            return
        }
        //print("Try set \(mode.width)x\(mode.height) for \(displayID)")
        resolutionManager.setResolution(displayID: displayID, mode: mode)
        refreshMenu()
    }
    
    // ログイン時自動起動が有効かをチェック
    func isLoginItemEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }
    
    // アプリケーションを終了
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// NSMenuItem をチェーン的に初期化するためのユーティリティ
private extension NSMenuItem {
    func then(_ body: (NSMenuItem) -> Void) -> NSMenuItem {
        body(self)
        return self
    }
}

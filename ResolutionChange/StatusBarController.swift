import Cocoa
import ServiceManagement

final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private let resolutionManager = ResolutionManager()
    
    // UserDefaultsキー
    private let favoriteResolutionsKey = "FavoriteResolutions"

    override init() {
        super.init()
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Resolution")
        }
        constructMenu()
    }
    
    private func constructMenu() {
        let menu = NSMenu()
        let displays = resolutionManager.getDisplays()

        guard let display = displays.first else { return }

        let currentMode = CGDisplayCopyDisplayMode(display.id)
        let currentRes = currentMode.map { "\($0.width)x\($0.height)" }
        let favoriteStrings = getFavoriteResolutions()

        //お気に入り解像度をピクセル数の大きい順に並べる（現在の解像度は .state で示すのみ）
        let sortedFavorites = favoriteStrings.sorted { a, b in
            // 解像度文字列を数値に変換（"1440x900" → (1440, 900)）
            guard let (aw, ah) = parseResolutionString(a),
                  let (bw, bh) = parseResolutionString(b) else {
                return a < b // パースできない場合は文字列昇順
            }
            return (aw * ah) > (bw * bh) // ピクセル数が大きい方を上に
        }

        for fav in sortedFavorites {
            guard let (w, h) = parseResolutionString(fav),
                  let mode = display.modes.first(where: { $0.width == w && $0.height == h }) else { continue }

            let item = NSMenuItem(title: fav, action: #selector(changeResolution(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = (display.id, mode)
            // ✅ 現在の解像度であればチェックマークを付ける（位置は固定せず、state だけで表示）
            if fav == currentRes {
                item.state = .on
            }

            menu.addItem(item)
        }

        // サブメニューとメインメニューの区切り線を追加
        menu.addItem(NSMenuItem.separator())
        
        // Display メニュー
        for display in displays {
            let displayItem = NSMenuItem(title: "Display \(display.id)", action: nil, keyEquivalent: "")
            let subMenu = NSMenu()
            let currentMode = CGDisplayCopyDisplayMode(display.id)

            for mode in display.modes {
                let title = "\(mode.width)x\(mode.height)"
                let item = NSMenuItem(title: title, action: #selector(changeResolution(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = (display.id, mode)

                let canSet = resolutionManager.canSetResolution(displayID: display.id, mode: mode)
                item.isEnabled = canSet
                if let cur = currentMode, cur.ioDisplayModeID == mode.ioDisplayModeID {
                    item.state = .on
                }

                subMenu.addItem(item)
            }

            displayItem.submenu = subMenu
            menu.addItem(displayItem)
        }
        
        // サブメニューとメインメニューの区切り線を追加
        menu.addItem(NSMenuItem.separator())

        // Favorite サブメニュー（お気に入り解像度一覧）を作成開始
        let favoriteItem = NSMenuItem(title: "Favorite", action: nil, keyEquivalent: "")
        let favoriteSubMenu = NSMenu()
        
        // 「[Display 1]」というタイトル行を追加（選択不可・装飾なし）
        let headerItem = NSMenuItem(title: "[ Display 1 ]", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false // 選択不可にする
        favoriteSubMenu.addItem(headerItem)

        for mode in display.modes {
            let resStr = "\(mode.width)x\(mode.height)"
            let item = NSMenuItem(title: resStr, action: #selector(toggleFavorite(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = resStr

            if favoriteStrings.contains(resStr) {
                item.state = .on
            }

            favoriteSubMenu.addItem(item)
        }
        // 「Favorite >」メニューにサブメニューを設定
        favoriteItem.submenu = favoriteSubMenu
        // メインメニューに「Favorite >」メニューを追加
        menu.addItem(favoriteItem)
        // サブメニューとメインメニューの区切り線を追加
        menu.addItem(NSMenuItem.separator())

        
        let refreshItem = NSMenuItem(title: "Refresh List", action: #selector(refreshMenu), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let autorunItem = NSMenuItem(
            title: "Auto Run",
            action: #selector(AppDelegate.toggleAutorun(_:)),
            keyEquivalent: ""
        )
        autorunItem.target = NSApp.delegate
        autorunItem.state = isLoginItemEnabled() ? .on : .off
        menu.addItem(autorunItem)

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q").then {
            $0.target = self
        })

        statusItem.menu = menu
    }

    
    @objc private func toggleFavorite(_ sender: NSMenuItem) {
        guard let resStr = sender.representedObject as? String else { return }

        var favorites = UserDefaults.standard.stringArray(forKey: "FavoriteResolutions") ?? []

        if favorites.contains(resStr) {
            // すでに登録されている → 削除
            favorites.removeAll { $0 == resStr }
            //print("⭐️ Removed favorite: \(resStr)")
        } else {
            // 登録されていない → 追加
            favorites.append(resStr)
            //print("⭐️ Added favorite: \(resStr)")
        }

        UserDefaults.standard.set(favorites, forKey: "FavoriteResolutions")

        // メニューを再構築して見た目を更新
        refreshMenu()
    }

    private func parseResolutionString(_ string: String) -> (Int, Int)? {
        let parts = string.split(separator: "x")
        guard parts.count == 2,
              let w = Int(parts[0]),
              let h = Int(parts[1]) else { return nil }
        return (w, h)
    }
    
    @objc private func refreshMenu() {
        constructMenu()
    }
    
    private func getFavoriteResolutions() -> [String] {
        return UserDefaults.standard.stringArray(forKey: favoriteResolutionsKey) ?? []
    }
    
    @objc private func changeResolution(_ sender: NSMenuItem) {
        guard let (displayID, mode) = sender.representedObject as? (CGDirectDisplayID, CGDisplayMode) else {
            //print("representedObject not set correctly")
            return
        }
        //print("Try set \(mode.width)x\(mode.height) for \(displayID)")
        resolutionManager.setResolution(displayID: displayID, mode: mode)
        refreshMenu()
    }
    
    
    func isLoginItemEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// 小さなヘルパー（任意）
private extension NSMenuItem {
    func then(_ body: (NSMenuItem) -> Void) -> NSMenuItem {
        body(self)
        return self
    }
}

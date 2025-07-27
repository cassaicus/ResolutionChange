import Cocoa  // macOSアプリの基本機能（UI含む）を提供するフレームワークをインポート
import ServiceManagement  // アプリのログイン時自動起動を制御するためのフレームワークをインポート

// ステータスバーのコントローラークラス（NSStatusItemとメニューを管理）
final class StatusBarController: NSObject {
    // ステータスバーアイテム（メニューバーに表示されるアイコン）
    private var statusItem: NSStatusItem!
    // 解像度を管理するためのマネージャークラス（独自定義のResolutionManager）
    private let resolutionManager = ResolutionManager()
    // UserDefaultsキー
    private let favoriteResolutionsKey = "FavoriteResolutions"
    
    // 初期化処理
    override init() {
        super.init()
        // ステータスバーに四角い長さでアイコンを登録
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // ボタン部分（アイコン）が取得できればシステム画像を設定
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Resolution")
        }
        // メニュー構築関数の呼び出し
        constructMenu()
    }
    
    // メニューを構築する関数
    private func constructMenu() {
        // 新しいメニューを生成
        let menu = NSMenu()
        // 利用可能なディスプレイ情報を取得
        let displays = resolutionManager.getDisplays()
        // 最初のディスプレイのみ対応（他ディスプレイの対応は未実装）
        guard let display = displays.first else { return }
        // 現在の解像度を取得し、文字列に変換
        let currentMode = CGDisplayCopyDisplayMode(display.id)
        let currentRes = currentMode.map { "\($0.width)x\($0.height)" }
        // UserDefaults からお気に入り解像度のリストを取得
        let favoriteStrings = getFavoriteResolutions()
        
        // お気に入り解像度をピクセル数（面積）で降順に並べる
        let sortedFavorites = favoriteStrings.sorted { a, b in
            // 解像度文字列を数値に変換（"1440x900" → (1440, 900)）
            guard let (aw, ah) = parseResolutionString(a),
                  let (bw, bh) = parseResolutionString(b) else {
                // パースできない場合は文字列で比較
                return a < b
            }
            // ピクセル数が大きい方を上に
            return (aw * ah) > (bw * bh)
        }
        
        // 並べたお気に入りをメニューに追加
        for fav in sortedFavorites {
            guard let (w, h) = parseResolutionString(fav),
                  let mode = display.modes.first(where: { $0.width == w && $0.height == h }) else { continue }
            
            let item = NSMenuItem(title: fav, action: #selector(changeResolution(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = (display.id, mode)
            // 現在の解像度にはチェックマークを付ける
            if fav == currentRes {
                item.state = .on
            }
            // メニューに追加
            menu.addItem(item)
        }
        
        //区切り線を追加
        menu.addItem(NSMenuItem.separator())
        
        // Display メニュー
        for display in displays {
            let displayItem = NSMenuItem(title: "Display \(display.id)", action: nil, keyEquivalent: "")
            let subMenu = NSMenu()
            let currentMode = CGDisplayCopyDisplayMode(display.id)
            
            // 各解像度モードをサブメニューに追加
            for mode in display.modes {
                let title = "\(mode.width)x\(mode.height)"
                let item = NSMenuItem(title: title, action: #selector(changeResolution(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = (display.id, mode)
                
                // このモードに切り替え可能か確認
                let canSet = resolutionManager.canSetResolution(displayID: display.id, mode: mode)
                item.isEnabled = canSet
                // 現在の解像度にはチェックマークを付ける
                if let cur = currentMode, cur.ioDisplayModeID == mode.ioDisplayModeID {
                    item.state = .on
                }
                subMenu.addItem(item)
            }
            // サブメニューをディスプレイ項目に設定し、メニューに追加
            displayItem.submenu = subMenu
            menu.addItem(displayItem)
        }
        
        //区切り線を追加
        menu.addItem(NSMenuItem.separator())
        
        // 「Favorite >」メニューを作成
        let favoriteItem = NSMenuItem(title: "Favorite", action: nil, keyEquivalent: "")
        let favoriteSubMenu = NSMenu()
        
        // 「[ Display 1 ]」のラベル行を追加（選択不可）
        let headerItem = NSMenuItem(title: "[ Display 1 ]", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false // 選択不可にする
        favoriteSubMenu.addItem(headerItem)
        
        // 各解像度ごとにお気に入り状態の切り替え項目を追加
        for mode in display.modes {
            let resStr = "\(mode.width)x\(mode.height)"
            let item = NSMenuItem(title: resStr, action: #selector(toggleFavorite(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = resStr
            // お気に入りに含まれていればチェック状態にする
            if favoriteStrings.contains(resStr) {
                item.state = .on
            }
            favoriteSubMenu.addItem(item)
        }
        // 「Favorite >」メニューにサブメニューを設定
        favoriteItem.submenu = favoriteSubMenu
        // メインメニューに「Favorite >」メニューを追加
        menu.addItem(favoriteItem)
        //区切り線を追加
        menu.addItem(NSMenuItem.separator())
        
        // リスト再読み込み項目（ショートカットキー "r"）
        let refreshItem = NSMenuItem(title: "Refresh List", action: #selector(refreshMenu), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        // Auto Run　項目
        let autorunItem = NSMenuItem(
            title: "Auto Run",
            action: #selector(AppDelegate.toggleAutorun(_:)),
            keyEquivalent: ""
        )
        autorunItem.target = NSApp.delegate
        autorunItem.state = isLoginItemEnabled() ? .on : .off
        menu.addItem(autorunItem)
        
        // 終了項目（ショートカットキー "q"）
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q").then {
            $0.target = self
        })
        // 最終的にメニューをステータスアイテムに設定
        statusItem.menu = menu
    }
    
    
    // お気に入りのオン・オフを切り替えるアクション
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
    
    // UserDefaults からお気に入り解像度を取得
    private func getFavoriteResolutions() -> [String] {
        return UserDefaults.standard.stringArray(forKey: favoriteResolutionsKey) ?? []
    }
    
    // 解像度を変更するアクション（NSMenuItem から情報を取得）
    @objc private func changeResolution(_ sender: NSMenuItem) {
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

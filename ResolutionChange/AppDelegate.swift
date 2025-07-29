import Cocoa  // macOSアプリの基本機能（UI含む）を提供するフレームワークをインポート
import ServiceManagement  // アプリのログイン時自動起動を制御するためのフレームワークをインポート

// アプリケーションのエントリーポイントとして機能するクラス
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // メニューバー常駐アイコンを制御するコントローラへの参照
    var statusBarController: StatusBarController?
    
    // アプリ起動完了時に呼ばれるメソッド（初期化処理を記述）
    func applicationDidFinishLaunching(_ notification: Notification) {
        // ステータスバー用のコントローラを初期化（アイコン表示など）
        statusBarController = StatusBarController()
        //ドックからアイコンを消す
        NSApp.setActivationPolicy(.accessory)
    }

    // アプリ終了時に呼ばれるメソッド（必要なら後始末処理を記述）
    func applicationWillTerminate(_ notification: Notification) {
        // クリーンアップ処理（現時点では何もしていない）
    }
    
    // メニューから「ログイン時に自動起動」をON/OFF切り替えるアクション
    @objc func toggleAutorun(_ sender: NSMenuItem) {
        if sender.state == .on {
            // すでにONなら、自動起動をOFFにする
            // ログイン項目（Login Item）から本アプリを解除
            try? SMAppService.mainApp.unregister()
            // メニューに反映（チェックを外す）
            sender.state = .off
        } else {
            // OFFなら、自動起動をONにする
            do {
                // ログイン項目として本アプリを登録
                try SMAppService.mainApp.register()
                // メニューに反映（チェックを付ける）
                sender.state = .on
            } catch {
                // 登録失敗時（例：権限不足）、メッセージをログに出力してもよい（現在は無効化中）
                // print("Failed to register login item: \(error)")
            }
        }
    }
}

import SwiftUI

@main
struct ResolutionChangeApp: App {
    // AppDelegateクラスをAppKitライフサイクルに適応させて使用
    // これによりNSApplicationDelegateのイベント（起動・終了・ステータスバー制御など）を使えるようにする
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // アプリのUI構成を定義（通常はWindowGroupやSettingsなどのSceneを返す）
    var body: some Scene {
        Settings {
            // 「設定」メニューから開かれる SwiftUI ビュー（macOS専用）
            // 必要なUIや設定内容を表示できる（今回の例では設定画面が未定義なら単に空）
            ContentView()
        }
    }
}

import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // クリーンアップ処理
    }
    
    @objc func toggleAutorun(_ sender: NSMenuItem) {
        if sender.state == .on {
            // OFF にする
            try? SMAppService.mainApp.unregister()
            sender.state = .off
        } else {
            // ON にする
            do {
                try SMAppService.mainApp.register()
                sender.state = .on
            } catch {
                //print("❌ Failed to register login item: \(error)")
            }
        }
    }
}

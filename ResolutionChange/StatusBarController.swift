import Cocoa
import ServiceManagement


final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private let resolutionManager = ResolutionManager()
    
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
        
        print("🖥️ Found \(displays.count) displays")
        
        if displays.count == 1 {
            let display = displays[0]
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
                print("🧪 \(title): \(canSet ? "✅ OK" : "❌ NG")  enabled=\(item.isEnabled)")
                menu.addItem(item)
            }
        } else {
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
                    
                    print("🧪 \(title): \(canSet ? "✅ OK" : "❌ NG")  enabled=\(item.isEnabled)")
                    subMenu.addItem(item)
                }
                displayItem.submenu = subMenu
                menu.addItem(displayItem)
            }
        }
        
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
        //autorunItem.target = self
        autorunItem.state = isLoginItemEnabled() ? .on : .off
        menu.addItem(autorunItem)
        
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q").then {
            $0.target = self
        })
        
        statusItem.menu = menu
    }
    
    @objc private func refreshMenu() {
        constructMenu()
    }
    
    @objc private func changeResolution(_ sender: NSMenuItem) {
        guard let (displayID, mode) = sender.representedObject as? (CGDirectDisplayID, CGDisplayMode) else {
            print("❌ representedObject not set correctly")
            return
        }
        print("🔁 Try set \(mode.width)x\(mode.height) for \(displayID)")
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

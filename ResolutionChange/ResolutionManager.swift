import Foundation
import CoreGraphics

// ディスプレイ情報構造体
struct Display {
    let id: CGDirectDisplayID
    let modes: [CGDisplayMode]
}

class ResolutionManager {
    // 接続中のディスプレイと、その使用可能なモード一覧を取得
    func getDisplays() -> [Display] {
        var displayCount: UInt32 = 0
        var result = CGGetOnlineDisplayList(0, nil, &displayCount)
        if result != .success {
            print("❌ Failed to get display count")
            return []
        }

        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        result = CGGetOnlineDisplayList(displayCount, &activeDisplays, &displayCount)
        if result != .success {
            print("❌ Failed to get display list")
            return []
        }

        var displays: [Display] = []

        for id in activeDisplays {
            // すべてのモードを取得
            let options: CFDictionary = [
                kCGDisplayShowDuplicateLowResolutionModes: true
            ] as CFDictionary

            guard let allModesCF = CGDisplayCopyAllDisplayModes(id, options) else {
                continue
            }
            let allModes = (allModesCF as NSArray) as! [CGDisplayMode]

            var validModes: [CGDisplayMode] = []

            // 1) HiDPIかつ幅>=1000のモードを追加
            for mode in allModes {
                if mode.isHiDPI && mode.width >= 1000 && canSetResolution(displayID: id, mode: mode) {
                    validModes.append(mode)
                }
            }

            // 2) 最大解像度モードを追加（まだ含まれていなければ）
            if let largest = allModes.max(by: { $0.width * $0.height < $1.width * $1.height }),
               canSetResolution(displayID: id, mode: largest),
               !validModes.contains(where: { $0.width == largest.width && $0.height == largest.height }) {
                validModes.append(largest)
            }

            // 3) モードを「見た目の大きさ」でソートして返す
            //validModes.sort { $0.width * $0.height < $1.width * $1.height }
            
            validModes.sort { (a, b) in
                (a.width * a.height) > (b.width * b.height)
            }

            if !validModes.isEmpty {
                displays.append(Display(id: id, modes: validModes))
            }
        }

        return displays
    }
    // 指定のモードに解像度を変更する
    func setResolution(displayID: CGDirectDisplayID, mode: CGDisplayMode) {
        var configRef: CGDisplayConfigRef?
        let beginResult = CGBeginDisplayConfiguration(&configRef)
        if beginResult != .success {
            print("❌ Failed to begin display config: \(beginResult.rawValue)")
            return
        }

        let result = CGConfigureDisplayWithDisplayMode(configRef, displayID, mode, nil)
        if result != .success {
            print("❌ Failed to set resolution \(mode.width)x\(mode.height): \(result.rawValue)")
            CGCancelDisplayConfiguration(configRef)
            return
        }

        CGCompleteDisplayConfiguration(configRef, .permanently)
        print("✅ Resolution set to \(mode.width)x\(mode.height) for display \(displayID)")
    }
    func canSetResolution(displayID: CGDirectDisplayID, mode: CGDisplayMode) -> Bool {
        // 実際に CGDisplaySetDisplayMode で試してみるのは重いので、
        // 一般的には以下の条件などで判定
        // ここでは単純にピクセル数が小さすぎるものを除外例

        let minWidth = 1000
        let minHeight = 600

        if mode.width < minWidth || mode.height < minHeight {
            return false
        }
        return true
    }
}

func aspectRatio(of width: Int, _ height: Int) -> Double {
    return Double(width) / Double(height)
}

// MARK: - CGDisplayMode 拡張（仮想・テレビ出力判定）

extension CGDisplayMode {
    var isVirtualMode: Bool {
        return self.ioDisplayModeID == 0
    }

    var isTelevisionOutput: Bool {
        return (self.pixelEncoding as String?) == "kIO16BitFloatPixels"
    }
    
    var isHiDPI: Bool {
        return (self.pixelWidth / self.width) >= 2
    }
}



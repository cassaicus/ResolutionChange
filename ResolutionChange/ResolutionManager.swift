import Foundation       // 基本的なSwift標準ライブラリ
import CoreGraphics     // ディスプレイ解像度操作やモード管理に必要なフレームワーク


// ディスプレイ情報構造体
struct Display {
    // ディスプレイの識別子
    let id: CGDirectDisplayID
    // 使用可能な解像度モードの一覧
    let modes: [CGDisplayMode]
}

// 解像度操作を管理するクラス
class ResolutionManager {
    // 接続中のディスプレイと、その使用可能なモード一覧を取得
    func getDisplays() -> [Display] {
        // 検出されたディスプレイ数を格納する変数
        var displayCount: UInt32 = 0
        // ディスプレイ数を取得（最初はnilでカウントのみ）
        var result = CGGetOnlineDisplayList(0, nil, &displayCount)
        if result != .success {
            //print("❌ Failed to get display count")
            // エラー発生時は空配列を返す
            return []
        }

        // 実際のディスプレイID一覧を取得
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        result = CGGetOnlineDisplayList(displayCount, &activeDisplays, &displayCount)
        if result != .success {
            //print("❌ Failed to get display list")
            // エラー発生時は空配列を返す
            return []
        }

        // 結果格納用配列
        var displays: [Display] = []

        for id in activeDisplays {
            // 重複した低解像度モードも含めてすべてのモードを取得するためのオプション
            let options: CFDictionary = [
                kCGDisplayShowDuplicateLowResolutionModes: true
            ] as CFDictionary
            // ディスプレイIDに対応する全モードを取得
            guard let allModesCF = CGDisplayCopyAllDisplayModes(id, options) else {
                continue
            }
            // CFArrayからSwiftのArray<CGDisplayMode>へキャスト
            let allModes = (allModesCF as NSArray) as! [CGDisplayMode]
            var validModes: [CGDisplayMode] = []

            // 1) HiDPIかつ幅>=1000のモードを追加
            for mode in allModes {
                if mode.isHiDPI && mode.width >= 1000 && canSetResolution(displayID: id, mode: mode) {
                    validModes.append(mode)
                }
            }

            // 2) さらに最大解像度（物理ピクセル数最大）のモードを1つだけ追加（未含なら）
            if let largest = allModes.max(by: { $0.width * $0.height < $1.width * $1.height }),
               canSetResolution(displayID: id, mode: largest),
               !validModes.contains(where: { $0.width == largest.width && $0.height == largest.height }) {
                validModes.append(largest)
            }
            
            // 3) 解像度の大きい順にソート（横×縦のピクセル数降順）
            validModes.sort { (a, b) in
                (a.width * a.height) > (b.width * b.height)
            }
            // 有効なモードがある場合だけ追加
            if !validModes.isEmpty {
                displays.append(Display(id: id, modes: validModes))
            }
        }
        // 最終的に全ディスプレイ情報を返す
        return displays
    }
    
    
    // 指定のモードに解像度を変更する
    func setResolution(displayID: CGDirectDisplayID, mode: CGDisplayMode) {
        var configRef: CGDisplayConfigRef?
        // 解像度変更の設定を開始
        let beginResult = CGBeginDisplayConfiguration(&configRef)
        if beginResult != .success {
            //print("❌ Failed to begin display config: \(beginResult.rawValue)")
            // 開始に失敗したら終了
            return
        }
        // 実際に解像度を設定
        let result = CGConfigureDisplayWithDisplayMode(configRef, displayID, mode, nil)
        if result != .success {
            //print("❌ Failed to set resolution \(mode.width)x\(mode.height): \(result.rawValue)")
            // エラー時はキャンセル
            CGCancelDisplayConfiguration(configRef)
            return
        }
        // 設定を永続的に適用
        CGCompleteDisplayConfiguration(configRef, .permanently)
        //print("✅ Resolution set to \(mode.width)x\(mode.height) for display \(displayID)")
    }
    
    // 指定の解像度モードが使用可能かどうかを簡易判定（小さすぎるモードを除外）
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

// アスペクト比を計算するヘルパー関数（横÷縦）
func aspectRatio(of width: Int, _ height: Int) -> Double {
    return Double(width) / Double(height)
}

// MARK: - CGDisplayMode 拡張（仮想・テレビ出力判定）
extension CGDisplayMode {
    // 仮想モードかどうかの判定（IDが0の特殊モード）
    var isVirtualMode: Bool {
        return self.ioDisplayModeID == 0
    }

    // テレビ出力（HDRや16bit floatなど）かの判定
//    var isTelevisionOutput: Bool {
//        return (self.pixelEncoding as String?) == "kIO16BitFloatPixels"
//    }
    
    // HiDPIモード（物理ピクセルが論理ピクセルの2倍以上）かを判定
    var isHiDPI: Bool {
        return (self.pixelWidth / self.width) >= 2
    }
}



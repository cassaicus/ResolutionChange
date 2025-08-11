import StoreKit

@MainActor
class InAppPurchaseManager: ObservableObject {
    @Published var hasUnlockedFullVersion = false
    @Published var products: [Product] = []
    
    private enum Constants {
        static let fullVersionProductID = "unlock_full_version"
    }

    private let productIDs = [Constants.fullVersionProductID]
    
    init() {
        Task {
            await fetchProducts()
            await updatePurchasedProducts()
            observeTransactions()
        }
    }
    
    // 商品情報取得
    func fetchProducts() async {
        do {
            products = try await Product.products(for: productIDs)
        } catch {
            // TODO: より良いエラーハンドリング
            print("商品取得エラー: \(error)")
        }
    }
    
    // 購入実行
    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await MainActor.run {
                        self.hasUnlockedFullVersion = true
                    }
                }
            case .userCancelled:
                // ユーザーによるキャンセルはエラーではないので、ログ出力は任意
                break
            default:
                break
            }
        } catch {
            // TODO: より良いエラーハンドリング
            print("購入エラー: \(error)")
        }
    }
    
    // 購入済み状態を確認
    func updatePurchasedProducts() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               productIDs.contains(transaction.productID) {
                await MainActor.run {
                    self.hasUnlockedFullVersion = true
                }
            }
        }
    }
    
    // 購入更新を監視
    func observeTransactions() {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result,
                   self.productIDs.contains(transaction.productID) {
                    await transaction.finish()
                    await MainActor.run {
                        self.hasUnlockedFullVersion = true
                    }
                }
            }
        }
    }
}

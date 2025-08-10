import StoreKit

@MainActor
class InAppPurchaseManager: ObservableObject {
    @Published var hasUnlockedFullVersion = false
    @Published var products: [Product] = []
    
    // 購入アイテムのID（App Store Connectと一致）
    private let productIDs = ["unlock_full_version"]
    
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
                    hasUnlockedFullVersion = true
                }
            case .userCancelled:
                print("ユーザーが購入をキャンセル")
            default:
                break
            }
        } catch {
            print("購入エラー: \(error)")
        }
    }
    
    // 購入済み状態を確認
    func updatePurchasedProducts() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               productIDs.contains(transaction.productID) {
                hasUnlockedFullVersion = true
            }
        }
    }
    
    // 購入更新を監視
    func observeTransactions() {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result,
                   self.productIDs.contains(transaction.productID) {
                    await MainActor.run {
                        self.hasUnlockedFullVersion = true
                    }
                    await transaction.finish()
                }
            }
        }
    }
}

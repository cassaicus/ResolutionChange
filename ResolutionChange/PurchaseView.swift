import SwiftUI
import StoreKit

struct PurchaseView: View {
    @ObservedObject var store: InAppPurchaseManager

    var body: some View {
        VStack(spacing: 20) {
            Text("Unlock Favorites")
                .font(.largeTitle)

            if store.hasUnlockedFullVersion {
                Text("🎉 Thank you for your purchase! The Favorite feature is now unlocked.")
                    .font(.title2)
                    .multilineTextAlignment(.center)
            } else {
                Text("Purchase the full version to unlock the Favorite feature.")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let product = store.products.first { // Assuming only one product
                    Button {
                        Task {
                            await store.purchase(product)
                        }
                    } label: {
                        Text("Purchase for \(product.displayPrice)")
                            .font(.title2)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    ProgressView("Loading product information...")
                }
            }

        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 300)
    }
}

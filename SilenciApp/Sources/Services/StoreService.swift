import Foundation
import StoreKit

/// StoreKit 2 — manages the single PRO non-consumable product.
/// Production purchase requires App Store Connect setup.
/// Local testing: open in Xcode with TextBasedEdit.storekit configuration active.
@MainActor
@Observable
final class StoreService {

    static let proProductId = "com.textbasededit.pro"

    // MARK: - State

    private(set) var products: [Product] = []
    private(set) var isPurchasing = false
    private(set) var purchaseError: String?

    @ObservationIgnored
    private var transactionListenerTask: Task<Void, Error>?

    // MARK: - Init / Deinit

    init() {
        transactionListenerTask = listenForTransactions()
        Task { await loadProducts() }
    }

    // MARK: - Product Loading

    func loadProducts() async {
        do {
            products = try await Product.products(for: [Self.proProductId])
        } catch {
            print("[StoreService] Failed to load products: \(error)")
        }
    }

    // MARK: - Purchase

    func purchase(proManager: ProManager) async {
        guard let product = products.first else {
            purchaseError = "Product not available. Check App Store Connect setup."
            return
        }
        isPurchasing = true
        purchaseError = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verify(verification)
                await transaction.finish()
                proManager.unlock()
                print("[StoreService] ✅ Purchase verified and unlocked PRO")
            case .userCancelled:
                print("[StoreService] User cancelled purchase")
            case .pending:
                print("[StoreService] Purchase pending (requires approval)")
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
            print("[StoreService] ❌ Purchase failed: \(error)")
        }

        isPurchasing = false
    }

    // MARK: - Restore

    /// Re-verify all current entitlements — call on launch to restore PRO after reinstall.
    func restoreIfNeeded(proManager: ProManager) async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.proProductId {
                proManager.unlock()
                print("[StoreService] ✅ Restored PRO from existing entitlement")
            }
        }
    }

    // MARK: - Transaction listener

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    print("[StoreService] Transaction update: \(transaction.productID)")
                }
            }
        }
    }

    private func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    // MARK: - Formatted price

    var proPrice: String {
        products.first?.displayPrice ?? "—"
    }
}

//
//  SubscriptionManager.swift
//  TasksCall19092025 (أنجز)
//
//  نظام الاشتراكات — شهري + سنوي + مدى الحياة
//

import SwiftUI
import Combine
import StoreKit

// MARK: - معرفات المنتجات
struct SubscriptionProducts {
    // ⚠️ غيّر هذه المعرفات حسب ما تعرّفه في App Store Connect
    static let monthlyID = "com.MHD.TasksCall19092025.premium.monthly"
    static let yearlyID = "com.MHD.TasksCall19092025.premium.yearly"
    static let lifetimeID = "com.MHD.TasksCall19092025.premium.lifetime"

    static let allIDs: Set<String> = [monthlyID, yearlyID, lifetimeID]
}

// MARK: - نوع الخطة
enum PlanType: String, Identifiable {
    case monthly = "شهري"
    case yearly = "سنوي"
    case lifetime = "مدى الحياة"

    var id: String { rawValue }

    var badge: String? {
        switch self {
        case .monthly: return nil
        case .yearly: return "وفّر 58%"
        case .lifetime: return "الأفضل قيمة"
        }
    }

    var icon: String {
        switch self {
        case .monthly: return "calendar"
        case .yearly: return "star.fill"
        case .lifetime: return "crown.fill"
        }
    }
}

// MARK: - مدير الاشتراكات
@MainActor
final class SubscriptionManager: ObservableObject {
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    var isPremium: Bool {
        !purchasedProductIDs.isEmpty
    }

    var monthlyProduct: Product? {
        products.first { $0.id == SubscriptionProducts.monthlyID }
    }
    var yearlyProduct: Product? {
        products.first { $0.id == SubscriptionProducts.yearlyID }
    }
    var lifetimeProduct: Product? {
        products.first { $0.id == SubscriptionProducts.lifetimeID }
    }

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - تحميل المنتجات
    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        do {
            let storeProducts = try await Product.products(for: SubscriptionProducts.allIDs)
            products = storeProducts.sorted { $0.price < $1.price }
            isLoading = false
        } catch {
            errorMessage = "تعذر تحميل خطط الاشتراك"
            isLoading = false
        }
    }

    // MARK: - شراء منتج
    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                purchasedProductIDs.insert(transaction.productID)
                await transaction.finish()
                isLoading = false
                return true
            case .userCancelled:
                isLoading = false
                return false
            case .pending:
                isLoading = false
                return false
            @unknown default:
                isLoading = false
                return false
            }
        } catch {
            errorMessage = "فشلت عملية الشراء"
            isLoading = false
            return false
        }
    }

    // MARK: - استعادة المشتريات
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        do {
            // مزامنة مع سيرفر Apple للتأكد من آخر حالة
            try await AppStore.sync()
        } catch {
            #if DEBUG
            NSLog("⚠️ AppStore.sync failed: \(error.localizedDescription)")
            #endif
        }
        await updatePurchasedProducts()
        isLoading = false
        if purchasedProductIDs.isEmpty {
            errorMessage = "لم يتم العثور على مشتريات سابقة"
        }
    }

    // MARK: - تحديث المشتريات
    func updatePurchasedProducts() async {
        var purchased: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                // تأكد إن المعاملة ما تم إلغاؤها أو استرجاعها
                if transaction.revocationDate == nil {
                    purchased.insert(transaction.productID)
                }
            }
        }

        purchasedProductIDs = purchased
    }

    // MARK: - الاستماع للمعاملات
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            guard let self else { return }
            for await result in Transaction.updates {
                if let transaction = try? self.checkVerified(result) {
                    let productID = transaction.productID
                    let isRevoked = transaction.revocationDate != nil
                    await MainActor.run {
                        if isRevoked {
                            self.purchasedProductIDs.remove(productID)
                        } else {
                            self.purchasedProductIDs.insert(productID)
                        }
                    }
                    await transaction.finish()
                }
            }
        }
    }

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: Error {
        case failedVerification
    }
}

// MARK: - مميزات PRO
struct PremiumFeatures {
    static let features: [(icon: String, title: String, description: String)] = [
        ("paintbrush.fill", "ثيمات حصرية", "3 ثيمات إضافية لتخصيص تطبيقك"),
        ("nosign", "بدون إعلانات", "تجربة نظيفة بدون أي إعلانات"),
        ("externaldrive.fill", "نسخ احتياطي وتصدير", "تصدير بياناتك ومرفقاتك بالكامل"),
        ("crown.fill", "دعم التطوير", "ساهم في تطوير وتحسين التطبيق"),
    ]
}

// MARK: - شاشة الاشتراك (Paywall) — احترافية
struct PaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: String = SubscriptionProducts.yearlyID

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // العنوان
                    headerSection

                    // المميزات
                    featuresSection

                    // خطط الاشتراك
                    plansSection

                    // زرار الشراء
                    purchaseButton

                    // استعادة المشتريات
                    restoreButton

                    // ملاحظات قانونية
                    legalSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(
                LinearGradient(
                    colors: [Color.blue.opacity(0.05), Color.purple.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { dismiss() }
                }
            }
            .task {
                // لو المنتجات ما تحملت — حاول تحميلها عند فتح صفحة الاشتراك
                if subscriptionManager.products.isEmpty {
                    await subscriptionManager.loadProducts()
                }
            }
        }
    }

    // MARK: - العنوان
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.top, 20)

            Text("أنجز PRO")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("أطلق العنان لإنتاجيتك")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - المميزات
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(PremiumFeatures.features, id: \.title) { feature in
                HStack(spacing: 14) {
                    Image(systemName: feature.icon)
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(feature.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    // MARK: - خطط الاشتراك
    private var plansSection: some View {
        VStack(spacing: 10) {
            // شهري — من المتجر أو افتراضي
            if let monthly = subscriptionManager.monthlyProduct {
                planCard(product: monthly, type: .monthly)
            } else if !subscriptionManager.isLoading {
                defaultPlanCard(title: "شهري", price: "$1.99/شهر", id: SubscriptionProducts.monthlyID, type: .monthly)
            }

            // سنوي — من المتجر أو افتراضي
            if let yearly = subscriptionManager.yearlyProduct {
                planCard(product: yearly, type: .yearly)
            } else if !subscriptionManager.isLoading {
                defaultPlanCard(title: "سنوي", price: "$9.99/سنة", id: SubscriptionProducts.yearlyID, type: .yearly)
            }

            // مدى الحياة — من المتجر أو افتراضي
            if let lifetime = subscriptionManager.lifetimeProduct {
                planCard(product: lifetime, type: .lifetime)
            } else if !subscriptionManager.isLoading {
                defaultPlanCard(title: "مدى الحياة", price: "$19.99", id: SubscriptionProducts.lifetimeID, type: .lifetime)
            }
        }
    }

    private func planCard(product: Product, type: PlanType) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPlan = product.id
            }
        } label: {
            HStack {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundStyle(selectedPlan == product.id ? .white : .blue)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(type.rawValue)
                            .font(.headline)
                        if let badge = type.badge {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    Text(product.displayPrice + (type == .lifetime ? "" : type == .yearly ? "/سنة" : "/شهر"))
                        .font(.subheadline)
                        .foregroundStyle(selectedPlan == product.id ? .white.opacity(0.8) : .secondary)
                }

                Spacer()

                Image(systemName: selectedPlan == product.id ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selectedPlan == product.id ? .white : .secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selectedPlan == product.id
                          ? LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                          : LinearGradient(colors: [Color.secondary.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selectedPlan == product.id ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func defaultPlanCard(title: String, price: String, id: String, type: PlanType) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPlan = id
            }
        } label: {
            HStack {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundStyle(selectedPlan == id ? .white : .blue)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title)
                            .font(.headline)
                        if let badge = type.badge {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    Text(price)
                        .font(.subheadline)
                        .foregroundStyle(selectedPlan == id ? .white.opacity(0.8) : .secondary)
                }

                Spacer()

                Image(systemName: selectedPlan == id ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selectedPlan == id ? .white : .secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selectedPlan == id
                          ? LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                          : LinearGradient(colors: [Color.secondary.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selectedPlan == id ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - زرار الشراء
    private var purchaseButton: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    if let product = subscriptionManager.products.first(where: { $0.id == selectedPlan }) {
                        let success = await subscriptionManager.purchase(product)
                        if success {
                            dismiss()
                        }
                    } else if subscriptionManager.products.isEmpty {
                        // المنتجات لم تتحمل — حاول تحميلها مرة أخرى
                        await subscriptionManager.loadProducts()
                        if subscriptionManager.products.isEmpty {
                            subscriptionManager.errorMessage = "تعذر الاتصال بالمتجر. تأكد من اتصالك بالإنترنت وحاول مرة أخرى."
                        } else if let product = subscriptionManager.products.first(where: { $0.id == selectedPlan }) {
                            let success = await subscriptionManager.purchase(product)
                            if success {
                                dismiss()
                            }
                        }
                    }
                }
            } label: {
                Group {
                    if subscriptionManager.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("اشترك الآن")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(subscriptionManager.isLoading)

            // رسالة الخطأ
            if let error = subscriptionManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - استعادة المشتريات
    private var restoreButton: some View {
        Button {
            Task {
                await subscriptionManager.restorePurchases()
                if subscriptionManager.isPremium {
                    dismiss()
                }
            }
        } label: {
            Text("استعادة المشتريات")
                .font(.subheadline)
                .foregroundStyle(.blue)
        }
    }

    // MARK: - ملاحظات قانونية
    private var legalSection: some View {
        VStack(spacing: 12) {
            // معلومات الاشتراك المطلوبة من Apple
            VStack(spacing: 4) {
                Text("معلومات الاشتراك")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text("• الاشتراك يتجدد تلقائياً ما لم يتم إلغاؤه قبل 24 ساعة من انتهاء الفترة الحالية")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("• يتم خصم المبلغ من حساب iTunes عند تأكيد الشراء")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("• يمكنك إدارة أو إلغاء الاشتراك من إعدادات الجهاز > Apple ID > الاشتراكات")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // روابط قانونية واضحة وبارزة
            HStack(spacing: 16) {
                Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.caption)
                        Text("شروط الاستخدام")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.blue)
                }

                Text("·")
                    .foregroundStyle(.secondary)

                Link(destination: URL(string: "https://vip1981111.github.io/anjaz-support/privacy.html")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.raised.fill")
                            .font(.caption)
                        Text("سياسة الخصوصية")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.blue)
                }
            }

            Text("بالمتابعة، فإنك توافق على شروط الاستخدام وسياسة الخصوصية")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }
}

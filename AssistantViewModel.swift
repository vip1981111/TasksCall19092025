import Foundation
import SwiftUI

// بسيط وآمن: كاش داخل actor + debounce + cancel support
actor ResponseCache {
    private var cache = NSCache<NSString, NSString>()
    func get(key: String) -> String? { cache.object(forKey: key as NSString) as String? }
    func set(key: String, value: String) { cache.setObject(value as NSString, forKey: key as NSString) }
}

@MainActor
class AssistantViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var responseText = ""
    @Published var isLoading = false

    private var currentTask: Task<Void, Never>? = nil
    private let cache = ResponseCache()
    private var debouncer: Task<Void, Never>? = nil

    // call this when user edits the input
    func userEditedInput(_ text: String) {
        inputText = text

        // cancel previous debounce
        debouncer?.cancel()
        debouncer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300 * 1_000_000) // 300ms
            await self?.performRequestDebounced()
        }
    }

    private func requestKey(for text: String) -> String {
        return "assistant:\(text.hashValue)"
    }

    private func performRequestDebounced() async {
        let key = requestKey(for: inputText)
        if let cached = await cache.get(key: key) {
            responseText = cached
            return
        }

        // cancel previous active network task
        currentTask?.cancel()

        isLoading = true
        responseText = ""

        currentTask = Task.detached { [weak self] in
            guard let self = self else { return }
            if Task.isCancelled { return }

            // ====== استبدل السطر التالي بنداء الـ API الحقيقي لديك ======
            // مثال محاكاة تأخير واستجابة:
            try? await Task.sleep(nanoseconds: 700 * 1_000_000) // simulate 700ms
            let result = "Simulated answer for: \(self.inputText)"
            // =========================================================

            if Task.isCancelled { return }

            await self.cache.set(key: key, value: result)

            await MainActor.run {
                self.responseText = result
                self.isLoading = false
            }
        }
    }

    // Manual cancel (e.g., user pressed cancel)
    func cancelRequest() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
    }
}

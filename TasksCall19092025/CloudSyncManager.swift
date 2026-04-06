//
//  CloudSyncManager.swift
//  TasksCall19092025 (أنجز)
//
//  مزامنة البيانات مع Firebase Firestore
//

import SwiftUI
import Combine
import FirebaseFirestore

@MainActor
final class CloudSyncManager: ObservableObject {
    @Published var isSyncing: Bool = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    /// رفع البيانات إلى Firestore
    func uploadPages(_ pages: [TaskPage]) async {
        guard let userID = FirebaseManager.shared.userID,
              FirebaseManager.shared.syncEnabled else { return }

        isSyncing = true
        syncError = nil

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(pages)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw NSError(domain: "sync", code: -1, userInfo: [NSLocalizedDescriptionKey: "تعذر تحويل البيانات"])
            }

            try await db.collection("users").document(userID).setData([
                "pages": json,
                "updatedAt": FieldValue.serverTimestamp(),
                "deviceName": deviceName()
            ], merge: true)

            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate!.timeIntervalSince1970, forKey: "lastSyncDate")
        } catch {
            syncError = error.localizedDescription
        }

        isSyncing = false
    }

    /// تحميل البيانات من Firestore
    func downloadPages() async -> [TaskPage]? {
        guard let userID = FirebaseManager.shared.userID,
              FirebaseManager.shared.syncEnabled else { return nil }

        isSyncing = true
        syncError = nil

        do {
            let doc = try await db.collection("users").document(userID).getDocument()

            guard let data = doc.data(),
                  let pagesArray = data["pages"] as? [[String: Any]] else {
                isSyncing = false
                return nil
            }

            let jsonData = try JSONSerialization.data(withJSONObject: pagesArray)
            let decoder = JSONDecoder()
            let pages = try decoder.decode([TaskPage].self, from: jsonData)

            lastSyncDate = Date()
            isSyncing = false
            return pages
        } catch {
            syncError = error.localizedDescription
            isSyncing = false
            return nil
        }
    }

    /// الاستماع للتغييرات في الوقت الحقيقي
    func startListening(onUpdate: @escaping ([TaskPage]) -> Void) {
        guard let userID = FirebaseManager.shared.userID,
              FirebaseManager.shared.syncEnabled else { return }

        stopListening()

        listener = db.collection("users").document(userID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    Task { @MainActor in
                        self.syncError = error.localizedDescription
                    }
                    return
                }

                guard let data = snapshot?.data(),
                      let pagesArray = data["pages"] as? [[String: Any]] else { return }

                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: pagesArray)
                    let decoder = JSONDecoder()
                    let pages = try decoder.decode([TaskPage].self, from: jsonData)

                    Task { @MainActor in
                        self.lastSyncDate = Date()
                        onUpdate(pages)
                    }
                } catch { }
            }
    }

    /// إيقاف الاستماع
    func stopListening() {
        listener?.remove()
        listener = nil
    }

    /// حذف بيانات المستخدم من السحابة
    func deleteUserData() async {
        guard let userID = FirebaseManager.shared.userID else { return }
        try? await db.collection("users").document(userID).delete()
    }

    private func deviceName() -> String {
        #if targetEnvironment(macCatalyst)
        return Host.current().localizedName ?? "Mac"
        #else
        return UIDevice.current.name
        #endif
    }

    init() {
        if let ts = UserDefaults.standard.object(forKey: "lastSyncDate") as? Double {
            lastSyncDate = Date(timeIntervalSince1970: ts)
        }
    }

    deinit {
        listener?.remove()
    }
}

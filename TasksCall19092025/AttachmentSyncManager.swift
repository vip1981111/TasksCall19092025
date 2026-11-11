import Foundation
import Combine

/// حالة ملف المرفق من منظور المزامنة.
enum AttachmentSyncState: Equatable {
    case available, uploading, downloading, missing
    case failed(String)
}

/// عملية التخزين السحابي لملف مرفق — تُستبدل بطبقة بديلة في الاختبارات.
@MainActor
protocol AttachmentCloudStore: AnyObject {
    func uploadAttachment(id: UUID, fileName: String, fileURL: URL) async throws
    func downloadAttachment(id: UUID, to destination: URL) async throws
    func deleteAttachment(id: UUID) async throws
    func listAttachmentIDs() async throws -> Set<UUID>
}

enum AttachmentCloudError: LocalizedError {
    case unavailable, missingAsset
    var errorDescription: String? {
        switch self {
        case .unavailable: return "مزامنة iCloud غير متاحة أو غير مفعّلة"
        case .missingAsset: return "ملف المرفق غير موجود في السحابة"
        }
    }
}

@MainActor
final class AttachmentSyncManager: ObservableObject {
    @Published private(set) var states: [UUID: AttachmentSyncState] = [:]
    private var uploadedIDs: Set<UUID>
    private var inFlight: Set<UUID> = []
    private var deleting: Set<UUID> = []
    private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
    private var locations: [UUID: URL] = [:]
    private let cloud: AttachmentCloudStore
    private let defaults: UserDefaults
    private let sleep: (UInt64) async throws -> Void

    init(cloudStore: AttachmentCloudStore, defaults: UserDefaults = .standard,
         sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        cloud = cloudStore
        self.defaults = defaults
        self.sleep = sleep
        uploadedIDs = Set((defaults.stringArray(forKey: "synced_attachment_ids") ?? []).compactMap(UUID.init(uuidString:)))
    }

    func state(for attachment: TaskAttachment) -> AttachmentSyncState {
        if let state = states[attachment.id], state != .available && state != .missing { return state }
        return isUsableFile(at: locations[attachment.id] ?? attachment.fileURL) ? .available : .missing
    }

    /// الملف متاح فقط إذا كان موجوداً وحجمه أكبر من صفر.
    /// ملف بحجم صفر يفتح معاينة فارغة، فيُعامَل كغائب ويُعاد تنزيله.
    private func isUsableFile(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        var currentURL = url
        currentURL.removeAllCachedResourceValues()
        let size = (try? currentURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 0
    }

    private func persistUploadedIDs() {
        defaults.set(uploadedIDs.map(\.uuidString).sorted(), forKey: "synced_attachment_ids")
    }

    private func finish(_ id: UUID) {
        inFlight.remove(id)
        let pending = waiters.removeValue(forKey: id) ?? []
        pending.forEach { $0.resume() }
    }

    private func waitForTransfer(_ id: UUID) async {
        while inFlight.contains(id) {
            await withCheckedContinuation { waiters[id, default: []].append($0) }
        }
    }

    // Initial attempt plus three retries, after 1, 2 and 4 seconds.
    private func withRetries<T>(_ operation: () async throws -> T) async throws -> T {
        for attempt in 0...3 {
            try Task.checkCancellation()
            do { return try await operation() }
            catch {
                if error is CancellationError || error is AttachmentCloudError || attempt == 3 { throw error }
                try await sleep(UInt64(1 << attempt) * 1_000_000_000)
            }
        }
        throw CancellationError()
    }

    func uploadIfNeeded(_ attachment: TaskAttachment, at url: URL) async {
        locations[attachment.id] = url
        guard !deleting.contains(attachment.id), !inFlight.contains(attachment.id) else { return }
        guard isUsableFile(at: url) else { states[attachment.id] = .missing; return }
        guard !uploadedIDs.contains(attachment.id) else { states[attachment.id] = .available; return }
        inFlight.insert(attachment.id)
        defer { finish(attachment.id) }
        states[attachment.id] = .uploading
        do {
            try await withRetries { try await cloud.uploadAttachment(id: attachment.id, fileName: attachment.fileName, fileURL: url) }
            uploadedIDs.insert(attachment.id)
            persistUploadedIDs()
            states[attachment.id] = .available
        } catch { states[attachment.id] = .failed("تعذّر رفع المرفق؛ أعد المحاولة") }
    }

    func ensureLocalFile(for attachment: TaskAttachment, at url: URL) async -> Bool {
        locations[attachment.id] = url
        await waitForTransfer(attachment.id)
        guard !deleting.contains(attachment.id) else { return false }
        if isUsableFile(at: url) { states[attachment.id] = .available; return true }
        inFlight.insert(attachment.id)
        defer { finish(attachment.id) }
        states[attachment.id] = .downloading
        // Preserve usable local files; replace only an unusable destination after validating the download.
        let staging = url.deletingLastPathComponent().appendingPathComponent(".attachment-download-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try await withRetries {
                try? FileManager.default.removeItem(at: staging)
                try await cloud.downloadAttachment(id: attachment.id, to: staging)
            }
            guard !deleting.contains(attachment.id) else { return false }
            guard isUsableFile(at: staging) else { throw AttachmentCloudError.missingAsset }
            if !isUsableFile(at: url) {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.moveItem(at: staging, to: url)
            }
            guard isUsableFile(at: url) else { throw AttachmentCloudError.missingAsset }
            uploadedIDs.insert(attachment.id)
            persistUploadedIDs()
            states[attachment.id] = .available
            return true
        } catch { states[attachment.id] = .failed("تعذّر تنزيل المرفق؛ أعد المحاولة"); return false }
    }

    func deleteFromCloud(_ attachment: TaskAttachment) async {
        await deleteIDFromCloud(attachment.id)
    }

    private func deleteIDFromCloud(_ id: UUID) async {
        guard deleting.insert(id).inserted else { return }
        defer { deleting.remove(id) }
        await waitForTransfer(id)
        inFlight.insert(id)
        defer { finish(id) }
        do {
            try await withRetries { try await cloud.deleteAttachment(id: id) }
            uploadedIDs.remove(id)
            persistUploadedIDs()
            states[id] = nil
        } catch { states[id] = .failed("تعذّر حذف المرفق من السحابة؛ أعد المحاولة") }
    }

    func syncPendingUploads(_ attachments: [(TaskAttachment, URL)]) async {
        for (attachment, url) in attachments {
            guard !Task.isCancelled else { return }
            await uploadIfNeeded(attachment, at: url)
        }
    }

    /// Call only with an authoritative, merged ID set; never with a stale device snapshot.
    func reconcileDeletions(localIDs: Set<UUID>) async {
        do {
            let remote = try await withRetries { try await cloud.listAttachmentIDs() }
            for id in remote.subtracting(localIDs) { await deleteIDFromCloud(id) }
        } catch { /* No deletions when listing fails. */ }
    }

    func retry(_ attachment: TaskAttachment, at url: URL) async {
        if isUsableFile(at: url) {
            await uploadIfNeeded(attachment, at: url)
        } else { _ = await ensureLocalFile(for: attachment, at: url) }
    }
}

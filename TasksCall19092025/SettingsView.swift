//
//  SettingsView.swift
//  TasksCall19092025 (أنجز)
//
//  واجهة الإعدادات
//

import SwiftUI
import QuickLook

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TasksStore
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var firebaseManager: FirebaseManager
    @State private var showPaywall: Bool = false
    @State private var showSyncAlert: Bool = false
    @State private var syncAlertMessage: String = ""
    @State private var showSignInSheet: Bool = false
    @State private var signInEmail: String = ""
    @State private var signInPassword: String = ""
    @State private var isSignUp: Bool = false
    @State private var authError: String = ""

    private struct ShareItem: Identifiable { let id = UUID(); let url: URL }
    @State private var shareItem: ShareItem? = nil
    @State private var isImporterPresented: Bool = false
    @State private var importError: Bool = false
    @State private var importErrorMessage: String = ""
    @State private var importSuccess: Bool = false
    @State private var exportError: Bool = false
    @State private var exportErrorMessage: String = ""
    @State private var showDocumentsBrowser: Bool = false

    @State private var previewURLsFromDocs: [URL] = []
    @State private var showPreviewFromDocs: Bool = false

    @State private var showCleanupConfirm: Bool = false
    @State private var showCleanupResult: Bool = false
    @State private var cleanupResultMessage: String = ""
    @State private var unusedAttachmentsCount: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                premiumSection
                cloudSyncSection
                ThemePickerView(themeManager: themeManager, showPaywall: $showPaywall)
                notificationsSection
                backupSection
                attachmentDeletionSection
                cleanupSection
                aboutSection
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .navigationTitle("الإعدادات")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
            .onAppear {
                updateUnusedAttachmentsCount()
                themeManager.validateTheme(isPremium: subscriptionManager.isPremium)
            }
            .sheet(item: $shareItem) { item in
                ShareLink(item: item.url) { Label("مشاركة الملف", systemImage: "square.and.arrow.up") }
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showPreviewFromDocs) {
                previewSheet
            }
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section("الإشعارات") {
            Toggle("تفعيل الإشعارات", isOn: $store.notificationsEnabled)
            DatePicker("وقت التذكير اليومي", selection: $store.dailyReminderTime, displayedComponents: .hourAndMinute)
            Button("اختبار إشعار الآن") { store.scheduleTestNotification() }
        }
        .onChange(of: store.notificationsEnabled) { _, newVal in
            if newVal {
                store.requestNotificationAuthorizationIfNeeded()
                store.scheduleDailyReminder(at: store.dailyReminderTime)
            } else {
                store.cancelScheduledDailyAtTime()
            }
        }
        .onChange(of: store.dailyReminderTime) { _, new in
            if store.notificationsEnabled { store.scheduleDailyReminder(at: new) }
        }
    }

    // MARK: - Backup Section

    private var backupSection: some View {
        Section("النسخ الاحتياطي والاستعادة") {
            exportButtons
            importButtons
            helpText
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            handleImportResult(result)
        }
        .alert("فشل الاستيراد", isPresented: $importError) {
            Button("حسنًا", role: .cancel) { }
        } message: {
            Text(importErrorMessage.isEmpty ? "تعذر استيراد الملف. تأكد أن الصيغة JSON أو ZIP صحيحة." : importErrorMessage)
        }
        .alert("نجح الاستيراد", isPresented: $importSuccess) {
            Button("حسنًا", role: .cancel) { }
        } message: {
            Text("تم استعادة البيانات والمرفقات بنجاح!")
        }
        .alert("فشل التصدير", isPresented: $exportError) {
            Button("حسنًا", role: .cancel) { }
        } message: {
            Text(exportErrorMessage.isEmpty ? "حدث خطأ غير معروف أثناء التصدير." : exportErrorMessage)
        }
    }

    private var exportButtons: some View {
        Group {
            HStack {
                Text("عدد المرفقات في النظام:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(totalAttachmentsCount)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            if subscriptionManager.isPremium {
                Button("نسخة احتياطية كاملة (ZIP)") {
                    if let url = store.exportFullBackupZIP() {
                        shareItem = ShareItem(url: url)
                    } else {
                        exportErrorMessage = "تعذر إنشاء ملف ZIP. تأكد من إضافة ZIPFoundation."
                        exportError = true
                    }
                }
                .disabled(store.pages.isEmpty)

                Button("تصدير البيانات فقط (JSON)") {
                    if let url = store.exportData() {
                        shareItem = ShareItem(url: url)
                    } else {
                        exportErrorMessage = "تعذر إنشاء ملف JSON للتصدير."
                        exportError = true
                    }
                }
                .disabled(store.pages.isEmpty)
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack {
                        Image(systemName: "lock.fill").foregroundStyle(.orange)
                        Text("نسخة احتياطية كاملة (ZIP)")
                        Spacer()
                        Text("PRO")
                            .font(.caption2).fontWeight(.bold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }

                Button {
                    showPaywall = true
                } label: {
                    HStack {
                        Image(systemName: "lock.fill").foregroundStyle(.orange)
                        Text("تصدير البيانات فقط (JSON)")
                        Spacer()
                        Text("PRO")
                            .font(.caption2).fontWeight(.bold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var totalAttachmentsCount: Int {
        var count = 0
        for page in store.pages {
            for task in page.tasks { count += task.attachments.count }
        }
        return count
    }

    private var importButtons: some View {
        Group {
            Button("استيراد نسخة احتياطية") { isImporterPresented = true }
                .buttonStyle(.borderedProminent)

            Button("فتح مجلد الحفظ في الملفات") { showDocumentsBrowser = true }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .sheet(isPresented: $showDocumentsBrowser) {
                    DocumentsBrowserView { pickedURL in handleDocumentsBrowserPick(pickedURL) }
                        .ignoresSafeArea()
                }
        }
    }

    private var helpText: some View {
        Text("• النسخة الكاملة (ZIP) تحتوي على البيانات والمرفقات\n• تصدير JSON يحفظ البيانات فقط بدون المرفقات\n• يمكنك تصفح جميع الملفات من خلال مجلد التطبيق")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    // MARK: - Attachment Deletion Section

    private var attachmentDeletionSection: some View {
        Section {
            Toggle(isOn: $store.deleteAttachmentFilesOnRemove) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("حذف ملف المرفق عند الإزالة")
                    Text("عند التفعيل: سيُحذف الملف الفعلي من التخزين عند إزالة المرفق من المهمة.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } footer: {
            Text("يساعد هذا الخيار على توفير المساحة ومنع تراكم ملفات غير مستخدمة داخل التطبيق.")
        }
    }

    // MARK: - Cloud Sync Section

    private var cloudSyncSection: some View {
        Section {
            if firebaseManager.isSignedIn {
                // حالة تسجيل الدخول
                HStack {
                    Image(systemName: "icloud.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("متصل بالسحابة")
                            .fontWeight(.medium)
                        if let email = firebaseManager.userEmail {
                            Text(email).font(.caption).foregroundStyle(.secondary)
                        } else if firebaseManager.isAnonymous {
                            Text("حساب مجهول").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if store.cloudSync.isSyncing {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }

                Toggle("المزامنة التلقائية", isOn: $firebaseManager.syncEnabled)
                    .onChange(of: firebaseManager.syncEnabled) { _, newVal in
                        if newVal {
                            store.startCloudListener()
                            Task { await store.syncNow() }
                        } else {
                            store.stopCloudListener()
                        }
                    }

                if let lastSync = store.cloudSync.lastSyncDate {
                    HStack {
                        Text("آخر مزامنة")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(lastSync, style: .relative)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Button("مزامنة الآن") {
                    Task {
                        await store.syncNow()
                        syncAlertMessage = "تمت المزامنة بنجاح"
                        showSyncAlert = true
                    }
                }

                Button("تحميل من السحابة") {
                    Task {
                        let success = await store.pullFromCloud()
                        syncAlertMessage = success ? "تم تحميل البيانات من السحابة" : "لا توجد بيانات في السحابة"
                        showSyncAlert = true
                    }
                }

                // ربط حساب مجهول بإيميل
                if firebaseManager.isAnonymous {
                    Button("ربط بحساب إيميل") {
                        isSignUp = false
                        showSignInSheet = true
                    }
                    .foregroundStyle(.blue)
                }

                Button("تسجيل خروج", role: .destructive) {
                    store.stopCloudListener()
                    try? firebaseManager.signOut()
                }
            } else {
                // غير مسجل دخول
                HStack {
                    Image(systemName: "icloud.slash")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("المزامنة السحابية")
                            .fontWeight(.medium)
                        Text("زامن مهامك بين أجهزتك")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Button("دخول سريع (بدون حساب)") {
                    Task {
                        do {
                            try await firebaseManager.signInAnonymously()
                            store.startCloudListener()
                            await store.syncNow()
                        } catch {
                            syncAlertMessage = "فشل الاتصال: \(error.localizedDescription)"
                            showSyncAlert = true
                        }
                    }
                }

                Button("تسجيل دخول بالإيميل") {
                    isSignUp = false
                    showSignInSheet = true
                }

                Button("إنشاء حساب جديد") {
                    isSignUp = true
                    showSignInSheet = true
                }
            }

            if let error = store.cloudSync.syncError {
                Text(error)
                    .font(.caption).foregroundStyle(.red)
            }
        } header: {
            Label("المزامنة السحابية", systemImage: "icloud")
        }
        .alert("المزامنة", isPresented: $showSyncAlert) {
            Button("حسنًا", role: .cancel) { }
        } message: {
            Text(syncAlertMessage)
        }
        .sheet(isPresented: $showSignInSheet) {
            signInSheet
        }
    }

    private var signInSheet: some View {
        NavigationStack {
            Form {
                Section(isSignUp ? "إنشاء حساب جديد" : (firebaseManager.isAnonymous ? "ربط الحساب بإيميل" : "تسجيل الدخول")) {
                    TextField("البريد الإلكتروني", text: $signInEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("كلمة المرور", text: $signInPassword)
                        .textContentType(isSignUp ? .newPassword : .password)
                }

                if !authError.isEmpty {
                    Text(authError).font(.caption).foregroundStyle(.red)
                }

                Button(isSignUp ? "إنشاء حساب" : (firebaseManager.isAnonymous ? "ربط الحساب" : "تسجيل دخول")) {
                    Task {
                        authError = ""
                        do {
                            if firebaseManager.isAnonymous && !isSignUp {
                                try await firebaseManager.linkAnonymousAccount(email: signInEmail, password: signInPassword)
                            } else if isSignUp {
                                try await firebaseManager.signUp(email: signInEmail, password: signInPassword)
                            } else {
                                try await firebaseManager.signIn(email: signInEmail, password: signInPassword)
                            }
                            store.startCloudListener()
                            await store.syncNow()
                            showSignInSheet = false
                            signInEmail = ""
                            signInPassword = ""
                        } catch {
                            authError = error.localizedDescription
                        }
                    }
                }
                .disabled(signInEmail.isEmpty || signInPassword.count < 6)
            }
            .navigationTitle(isSignUp ? "حساب جديد" : "تسجيل دخول")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { showSignInSheet = false }
                }
            }
        }
    }

    // MARK: - Cleanup Section

    private var cleanupSection: some View {
        Section {
            cleanupDescription
            cleanupButton
        } header: {
            Text("صيانة المرفقات")
        } footer: {
            Text("الملفات غير المستخدمة: \(unusedAttachmentsCount)")
        }
        .alert("تأكيد التنظيف", isPresented: $showCleanupConfirm) {
            Button("حذف", role: .destructive) { performCleanup() }
            Button("إلغاء", role: .cancel) { }
        } message: {
            Text("سيتم حذف \(unusedAttachmentsCount) ملف غير مرتبط بأي مهمة بشكل نهائي. هل أنت متأكد؟")
        }
        .alert("نتيجة التنظيف", isPresented: $showCleanupResult) {
            Button("حسنًا", role: .cancel) { }
        } message: {
            Text(cleanupResultMessage)
        }
    }

    private var cleanupDescription: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("تنظيف المرفقات غير المستخدمة")
                Text("حذف الملفات الموجودة في المجلد لكنها غير مرتبطة بأي مهمة")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if unusedAttachmentsCount > 0 {
                Text("\(unusedAttachmentsCount)")
                    .font(.caption).fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
        }
    }

    private var cleanupButton: some View {
        Button(role: .destructive) { showCleanupConfirm = true } label: {
            Label("تنظيف الآن", systemImage: "trash.circle.fill")
        }
        .disabled(unusedAttachmentsCount == 0)
    }

    // MARK: - Premium Section

    private var premiumSection: some View {
        Section {
            if subscriptionManager.isPremium {
                HStack {
                    Image(systemName: "crown.fill").foregroundStyle(.orange)
                    Text("أنت مشترك في أنجز PRO").fontWeight(.medium)
                    Spacer()
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
            } else {
                Button { showPaywall = true } label: {
                    HStack {
                        Image(systemName: "crown.fill")
                            .font(.title2)
                            .foregroundStyle(
                                LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ترقية إلى أنجز PRO").font(.headline).foregroundStyle(.primary)
                            Text("ثيمات حصرية • بدون إعلانات • مميزات متقدمة")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.left").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("حول التطبيق") {
            HStack {
                Text("الإصدار").foregroundStyle(.primary)
                Spacer()
                Text(appVersion).foregroundStyle(.secondary)
            }
            Link("سياسة الخصوصية", destination: URL(string: "https://vip1981111.github.io/anjaz-support/privacy.html")!)
            Text("البيانات تحفظ محليًا على جهازك. لا توجد خوادم.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Preview Sheet

    private var previewSheet: some View {
        NavigationStack {
            QLPreview(urls: previewURLsFromDocs)
                .ignoresSafeArea()
                .navigationTitle("معاينة")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let url = previewURLsFromDocs.first {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("إغلاق") { showPreviewFromDocs = false }
                        }
                    }
                }
        }
    }

    // MARK: - Helper Methods

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    try store.importBackup(from: url)
                    importSuccess = true
                } catch {
                    importErrorMessage = error.localizedDescription
                    importError = true
                }
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
            importError = true
        }
    }

    private func handleDocumentsBrowserPick(_ pickedURL: URL) {
        let ext = pickedURL.pathExtension.lowercased()
        if ["png","jpg","jpeg","heic"].contains(ext) {
            previewURLsFromDocs = [pickedURL]
            showPreviewFromDocs = true
        } else {
            shareItem = ShareItem(url: pickedURL)
        }
    }

    private func performCleanup() {
        let result = store.cleanUnusedAttachments()
        let sizeInKB = result.freedSpace / 1024
        let sizeInMB = Double(result.freedSpace) / (1024 * 1024)

        if result.deletedCount > 0 {
            if sizeInMB >= 1 {
                cleanupResultMessage = "تم حذف \(result.deletedCount) ملف غير مستخدم\nتم تحرير \(String(format: "%.2f", sizeInMB)) MB"
            } else {
                cleanupResultMessage = "تم حذف \(result.deletedCount) ملف غير مستخدم\nتم تحرير \(sizeInKB) KB"
            }
        } else {
            cleanupResultMessage = "لا توجد ملفات غير مستخدمة للحذف"
        }

        showCleanupResult = true
        updateUnusedAttachmentsCount()
    }

    private func updateUnusedAttachmentsCount() {
        unusedAttachmentsCount = store.countUnusedAttachments()
    }
}

//
//  UIKitWrappers.swift
//  TasksCall19092025 (أنجز)
//
//  أغلفة UIKit (معاينة، ماسح ضوئي، منتقي صور، RTL، إلخ)
//

import SwiftUI
import PhotosUI
import QuickLook

#if !targetEnvironment(macCatalyst)
import VisionKit
#endif

// MARK: - Documents Browser

struct DocumentsBrowserView: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
            picker.allowsMultipleSelection = false
            picker.delegate = context.coordinator
            return UINavigationController(rootViewController: picker)
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
        picker.directoryURL = docs
        picker.shouldShowFileExtensions = true
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return UINavigationController(rootViewController: picker)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            onPick(url)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Force RTL

private struct ForceRTLViewController: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        vc.view.semanticContentAttribute = .forceRightToLeft
        vc.view.tintColor = UIColor.label
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        uiViewController.view.semanticContentAttribute = .forceRightToLeft
    }
}

private struct ForceRTLModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(ForceRTLViewController().ignoresSafeArea()).environment(\.layoutDirection, .rightToLeft)
    }
}

extension View {
    func forceRTL() -> some View { self.modifier(ForceRTLModifier()) }
}

// MARK: - QuickLook wrapper

struct QLPreview: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(urls: urls) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let urls: [URL]
        init(urls: [URL]) { self.urls = urls }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { urls.count }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { urls[index] as QLPreviewItem }
    }
}

// MARK: - Document Scanner wrapper (iOS only — غير متوفر على الماك)

#if !targetEnvironment(macCatalyst)
struct DocumentScannerView: UIViewControllerRepresentable {
    var onScan: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([UIImage]) -> Void

        init(onScan: @escaping ([UIImage]) -> Void) { self.onScan = onScan }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            controller.dismiss(animated: true)
            onScan(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true)
        }
    }
}
#endif

// MARK: - PHPicker wrapper (iOS 14+)

struct PhotoPickerView: UIViewControllerRepresentable {
    enum Filter { case images }
    var filter: Filter = .images
    var selectionLimit: Int = 1
    var onImagePicked: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = selectionLimit
        configuration.filter = .images
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImagePicked: onImagePicked) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImagePicked: (UIImage?) -> Void
        init(onImagePicked: @escaping (UIImage?) -> Void) { self.onImagePicked = onImagePicked }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { onImagePicked(nil); return }
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    DispatchQueue.main.async { self.onImagePicked(object as? UIImage) }
                }
            } else { onImagePicked(nil) }
        }
    }
}

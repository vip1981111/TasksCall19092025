import Foundation
import QuickLook
import UIKit
import Testing
@testable import TasksCall19092025

@MainActor
struct PreviewCoordinatorTests {
    // هذا الاختبار يحرس السبب الجذري — منسّق لا يعكس urls الجديدة يعني معاينة فارغة.
    @Test("المنسّق يعكس عناوين المعاينة الجديدة")
    func reflectsUpdatedURLs() {
        let controller = QLPreviewController()
        let coordinator = QLPreview.Coordinator(urls: [])
        let url1 = URL(fileURLWithPath: "/tmp/preview-test-image.jpg")
        let url2 = URL(fileURLWithPath: "/tmp/preview-test-document.pdf")

        #expect(coordinator.numberOfPreviewItems(in: controller) == 0)

        coordinator.urls = [url1]
        #expect(coordinator.numberOfPreviewItems(in: controller) == 1)
        #expect(coordinator.previewController(controller, previewItemAt: 0).previewItemURL == url1)

        coordinator.urls = [url1, url2]
        #expect(coordinator.numberOfPreviewItems(in: controller) == 2)
        #expect(coordinator.previewController(controller, previewItemAt: 1).previewItemURL == url2)
    }
}

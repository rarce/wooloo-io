import SwiftUI
import PhotosUI
import VisionKit
import AVFoundation
import CoreImage

struct QRImportView: View {
    @Environment(\.dismiss) private var dismiss
    let onImport: (String) -> Void
    @State private var cameraAllowed = false
    @State private var photo: PhotosPickerItem?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if cameraAllowed && DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    Scanner { text in onImport(text); dismiss() }.clipShape(RoundedRectangle(cornerRadius: 20))
                } else {
                    ContentUnavailableView("Scan Wooloo's Remote Access QR", systemImage: "qrcode.viewfinder", description: Text("Allow camera access on a supported device, choose a QR image, or paste a machine link in the editor."))
                    Button("Enable camera") {
                        Task { cameraAllowed = await AVCaptureDevice.requestAccess(for: .video) }
                    }
                }
                PhotosPicker(selection: $photo, matching: .images) { Label("Choose QR image", systemImage: "photo") }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                Text("The QR only fills connection details. Review the destination and server fingerprint before saving.").font(.caption).foregroundStyle(.secondary)
            }.padding()
            .navigationTitle("Import machine")
            .toolbar { Button("Cancel") { dismiss() } }
            .onAppear { cameraAllowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
            .onChange(of: photo) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { error = "Could not read this image."; return }
                    let text = await Task.detached {
                        guard let image = CIImage(data: data), let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return String?.none }
                        return detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
                    }.value
                    if let text { onImport(text); dismiss() } else { error = "No QR code found in this image." }
                }
            }
        }
    }
}
private struct Scanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onCode) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        do { try scanner.startScanning() } catch { context.coordinator.failure = error.localizedDescription }
        return scanner
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        var handled = false
        var failure: String?
        init(_ onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !handled else { return }
            for case .barcode(let barcode) in addedItems {
                if let payload = barcode.payloadStringValue { handled = true; dataScanner.stopScanning(); onCode(payload); return }
            }
        }
    }
}

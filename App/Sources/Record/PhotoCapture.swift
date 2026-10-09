import EngramCapture
import EngramCore
import ImageIO
import SwiftUI
import UIKit

/// P12 — un texte lu sur une photo, à vérifier avant de le classer.
struct PhotoDraft: Identifiable {
    let id = UUID()
    let text: String
}

/// Lit le texte d'une photo sur l'iPhone et le remet au propre. nil s'il n'y a aucun texte.
enum PhotoReading {
    static func text(in image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        // L'image n'est lue que par la reconnaissance de texte, hors du fil de l'interface.
        nonisolated(unsafe) let pixels = cgImage
        let lines = await Task.detached(priority: .userInitiated) {
            (try? PhotoTextReader.lines(in: pixels, orientation: orientation)) ?? []
        }.value
        let text = OCRText.clean(lines: lines)
        return text.isEmpty ? nil : text
    }
}

extension CGImagePropertyOrientation {
    /// L'orientation d'une photo prise de côté, pour que le texte soit lu à l'endroit.
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// L'appareil photo de l'iPhone (la photo n'est pas gardée : seul son texte l'est).
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

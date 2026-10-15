import CoreGraphics
import Foundation
import ImageIO
import Vision

/// P12 — le texte d'une photo (un papier, une étiquette, un tableau blanc), lu **sur l'iPhone** par la reconnaissance
/// de texte d'Apple. Rien n'est envoyé ; la photo n'est pas gardée, seulement le texte.
public enum PhotoTextReader {
    /// Les lignes lues, de haut en bas ; une ligne vide là où un grand espace sépare deux blocs.
    public static func lines(in image: CGImage, orientation: CGImagePropertyOrientation = .up) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["fr-FR", "en-US"]
        try VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:]).perform([request])
        // Repère de Vision : l'origine est en bas ; on lit donc du plus haut au plus bas.
        let observations = (request.results ?? []).sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
        guard !observations.isEmpty else { return [] }
        let averageHeight = observations.map(\.boundingBox.height).reduce(0, +) / CGFloat(observations.count)
        var lines: [String] = []
        var previous: CGRect?
        for observation in observations {
            guard let text = observation.topCandidates(1).first?.string else { continue }
            if let previous, previous.minY - observation.boundingBox.maxY > averageHeight * 1.2 { lines.append("") }
            lines.append(text)
            previous = observation.boundingBox
        }
        return lines
    }
}

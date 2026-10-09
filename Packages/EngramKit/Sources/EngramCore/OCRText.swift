import Foundation

/// P12 — le texte lu sur une photo (reconnaissance de texte de l'iPhone), remis au propre avant d'en faire une note.
public enum OCRText {
    /// Les lignes lues, dans l'ordre. Une ligne vide sépare deux paragraphes.
    public static func clean(lines: [String]) -> String {
        var paragraphs: [[String]] = [[]]
        for raw in lines {
            let line = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if line.isEmpty {
                if !(paragraphs.last?.isEmpty ?? true) { paragraphs.append([]) }
                continue
            }
            // Un trait, une barre, un point isolé : du bruit de la photo.
            guard line.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            paragraphs[paragraphs.count - 1].append(line)
        }
        return paragraphs.filter { !$0.isEmpty }.map(join).joined(separator: "\n\n")
    }

    /// Recolle une phrase coupée en fin de ligne (la suite commence par une minuscule) ; une césure (« rendez- »
    /// + « vous ») est recollée sans espace. Une ligne qui commence par une majuscule reste une ligne à part.
    static func join(_ lines: [String]) -> String {
        var text = ""
        for line in lines {
            guard let last = text.last, let next = line.first else {
                text = line
                continue
            }
            if last == "-", next.isLowercase {
                text += line
            } else if !".!?:;".contains(last), next.isLowercase {
                text += " " + line
            } else {
                text += "\n" + line
            }
        }
        return text
    }
}

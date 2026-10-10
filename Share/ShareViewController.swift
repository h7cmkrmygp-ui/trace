import EngramCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// « Partager › Engram » depuis Safari, Notes… : le texte ou le lien est déposé dans le dossier partagé ; Engram
/// l'enregistre et le classe à sa prochaine ouverture (rien n'est envoyé ailleurs).
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let text = items.compactMap { $0.attributedContentText?.string }.first { !$0.isEmpty } ?? ""
        let providers = items.flatMap { $0.attachments ?? [] }
        show(text: text, link: nil)
        // Lien (Safari) ou texte (Notes) : lus en arrière-plan, puis affichés.
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { @Sendable value, _ in
                let link = (value as? URL)?.absoluteString
                Task { @MainActor in self.show(text: text, link: link) }
            }
        } else if text.isEmpty,
                  let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { @Sendable value, _ in
                let shared = (value as? String) ?? (value as? NSString).map { $0 as String } ?? ""
                Task { @MainActor in self.show(text: shared, link: nil) }
            }
        }
    }

    private func show(text: String, link: String?) {
        children.forEach { child in
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        let view = ShareSheet(initialText: text, link: link, onSave: { [weak self] note in self?.save(note, link: link) },
                              onCancel: { [weak self] in self?.close() })
        let host = UIHostingController(rootView: view)
        addChild(host)
        host.view.frame = self.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func save(_ text: String, link: String?) {
        let item = SharedItem(text: text, link: link, createdAt: Date())
        guard let inbox = SharedContainer.inbox, (try? inbox.add(item)) != nil else {
            let alert = UIAlertController(title: "Engram n'a pas pu recevoir cet élément",
                                          message: "Ouvre Engram une fois, puis réessaie.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.close() })
            present(alert, animated: true)
            return
        }
        close()
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

/// La feuille de partage : le texte à garder (modifiable), le lien, et « Ajouter ».
struct ShareSheet: View {
    @State private var text: String
    let link: String?
    let onSave: (String) -> Void
    let onCancel: () -> Void

    init(initialText: String, link: String?, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _text = State(initialValue: initialText)
        self.link = link
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .accessibilityLabel("Texte de la note")
                } footer: {
                    Text("Engram le classera tout seul à sa prochaine ouverture.")
                }
                if let link {
                    Section("Lien") {
                        Text(link).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            }
            .navigationTitle("Ajouter à Engram")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { onSave(text) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && link == nil)
                }
            }
        }
    }
}

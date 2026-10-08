import SwiftUI

/// Saisie au clavier : même traitement qu'une pensée dictée.
struct TextCaptureSheet: View {
    /// Texte et choix « Garder sur l'iPhone ».
    let onSubmit: (String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var keepLocal = false
    @FocusState private var isFocused: Bool

    private var canSubmit: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Écris ta pensée…", text: $text, axis: .vertical)
                    .lineLimit(5...12)
                    .focused($isFocused)
                Toggle("Garder sur l'iPhone", isOn: $keepLocal)
                    .tint(.green)
                    .font(.subheadline)
                Spacer()
            }
            .padding()
            .navigationTitle("Écrire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Classer") {
                        guard canSubmit else { return }
                        onSubmit(text, keepLocal)
                        dismiss()
                    }
                    .disabled(!canSubmit)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
    }
}

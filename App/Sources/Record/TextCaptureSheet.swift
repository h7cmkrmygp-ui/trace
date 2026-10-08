import SwiftUI

/// Saisie au clavier : même traitement qu'une pensée dictée.
struct TextCaptureSheet: View {
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var canSubmit: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            VStack {
                TextField("Écris ta pensée…", text: $text, axis: .vertical)
                    .lineLimit(5...12)
                    .focused($isFocused)
                    .padding()
                Spacer()
            }
            .navigationTitle("Écrire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Classer") {
                        guard canSubmit else { return }
                        onSubmit(text)
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

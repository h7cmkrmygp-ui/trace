import SwiftUI
import UniformTypeIdentifiers

/// Réglages › Sécurité : verrouillage Face ID et sauvegardes chiffrées (dossier, mot de passe, chaque semaine,
/// maintenant, restaurer).
struct SecuritySettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var lockOn = false
    @State private var weekly = false
    @State private var password = ""
    @State private var confirmation = ""
    @State private var passwordMessage: String?
    @State private var backupMessage: String?
    @State private var isChoosingFolder = false
    @State private var isChoosingBackup = false
    @State private var restoreFile: URL?
    @State private var restorePassword = ""
    @State private var restoreMessage: String?

    var body: some View {
        Section {
            Toggle("Verrouiller avec Face ID", isOn: $lockOn)
                .tint(.green)
                .onChange(of: lockOn) { _, value in
                    guard value != model.lock.isEnabled else { return }
                    Task {
                        if !(await model.lock.setEnabled(value)) { lockOn = model.lock.isEnabled }
                        await model.syncReminders()
                    }
                }
        } header: {
            Text("Verrouillage")
        } footer: {
            Text("Engram demande Face ID (ou le code de l'iPhone) à chaque retour dans l'app. Les widgets et les notifications n'affichent plus les titres de tes notes.")
        }

        Section {
            Button {
                isChoosingFolder = true
            } label: {
                LabeledContent("Dossier", value: model.backups.folderName ?? "À choisir")
            }
            if model.backups.hasPassword {
                LabeledContent("Mot de passe", value: "Enregistré sur l'iPhone")
                Button("Changer le mot de passe", role: .destructive) { model.backups.forgetPassword(); passwordMessage = nil }
                    .tint(.red)
            } else {
                SecureField("Mot de passe (8 caractères ou plus)", text: $password)
                SecureField("Confirmer le mot de passe", text: $confirmation)
                Button("Enregistrer le mot de passe") {
                    passwordMessage = model.backups.setPassword(password, confirmation: confirmation)
                    if passwordMessage == nil {
                        password = ""
                        confirmation = ""
                    }
                }
                .disabled(password.isEmpty)
                if let passwordMessage { Text(passwordMessage).font(.footnote).foregroundStyle(.orange) }
            }
            Toggle("Chaque semaine, automatiquement", isOn: $weekly)
                .tint(.green)
                .onChange(of: weekly) { _, value in model.perform { try model.settings.set(value, for: .backupWeekly) } }
            Button {
                Task { await backupNow() }
            } label: {
                HStack {
                    Label("Sauvegarder maintenant", systemImage: "lock.doc")
                    if model.backups.isWorking {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(model.backups.isWorking)
            if let last = model.backups.lastBackup {
                LabeledContent("Dernière sauvegarde", value: last.formatted(date: .abbreviated, time: .shortened))
            }
            if let backupMessage { Text(backupMessage).font(.footnote).foregroundStyle(.secondary) }
            Button("Restaurer une sauvegarde…", systemImage: "arrow.counterclockwise") { isChoosingBackup = true }
                .disabled(model.backups.isWorking)
            if let restoreMessage { Text(restoreMessage).font(.footnote).foregroundStyle(.secondary) }
            if let aside = model.restoredAside {
                Text("Restauration faite. Tes anciennes données sont gardées dans « \(aside.lastPathComponent) ».")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Sauvegarde chiffrée")
        } footer: {
            Text("Ta mémoire (notes et enregistrements) est chiffrée avec ton mot de passe, puis rangée dans le dossier choisi (iCloud Drive conseillé). Les 4 dernières sont gardées. Note bien ce mot de passe : sans lui, personne, pas même toi, ne peut ouvrir la sauvegarde.")
        }
        .onAppear {
            lockOn = model.lock.isEnabled
            weekly = (try? model.settings.bool(.backupWeekly, default: false)) ?? false
        }
        // Un seul sélecteur de fichiers (deux sur le même écran se gênent) : un dossier, ou une sauvegarde.
        .fileImporter(isPresented: Binding(get: { isChoosingFolder || isChoosingBackup },
                                           set: { if !$0 { isChoosingFolder = false; isChoosingBackup = false } }),
                      allowedContentTypes: isChoosingFolder ? [.folder] : [.item]) { result in
            let choosingFolder = isChoosingFolder
            isChoosingFolder = false
            isChoosingBackup = false
            guard case .success(let url) = result else { return }
            if choosingFolder {
                model.perform { try model.backups.setFolder(url) }
            } else {
                restoreFile = url
            }
        }
        .alert("Mot de passe de la sauvegarde", isPresented: Binding(get: { restoreFile != nil }, set: { if !$0 { restoreFile = nil } })) {
            SecureField("Mot de passe", text: $restorePassword)
            Button("Annuler", role: .cancel) {
                restoreFile = nil
                restorePassword = ""
            }
            Button("Restaurer") {
                let file = restoreFile
                let secret = restorePassword
                restorePassword = ""
                restoreFile = nil
                if let file { Task { await restore(file, password: secret) } }
            }
        } message: {
            Text("Tes données actuelles seront mises de côté, jamais effacées.")
        }
    }

    private func backupNow() async {
        do {
            let name = try await model.backups.backupNow(model: model)
            backupMessage = "Sauvegarde faite : \(name)"
        } catch {
            backupMessage = error.localizedDescription
        }
    }

    private func restore(_ file: URL, password: String) async {
        do {
            let count = try await model.backups.prepareRestore(from: file, password: password, model: model)
            restoreMessage = "Sauvegarde vérifiée (\(count) note\(count > 1 ? "s" : "")). Ferme Engram (glisse-le vers le haut dans le sélecteur d'apps), puis rouvre-le pour terminer la restauration."
        } catch {
            restoreMessage = "Impossible d'ouvrir cette sauvegarde : mauvais mot de passe, ou fichier abîmé."
        }
    }
}

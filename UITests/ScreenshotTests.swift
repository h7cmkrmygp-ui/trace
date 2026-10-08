import XCTest

/// Captures d'écran de chaque écran, en mode clair et sombre, avec des notes **inventées** (base en mémoire).
/// Elles permettent de vérifier l'apparence sans iPhone : contraste, cartes, corbeille, réglages…
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor func testScreensInLightMode() { captureAll(dark: false) }

    @MainActor func testScreensInDarkMode() { captureAll(dark: true) }

    /// Bug signalé sur l'iPhone : l'app se fermait en touchant « Classer » sur la carte « Vérifie ta note » de l'écran
    /// Enregistrer (la note était pourtant enregistrée et classée au redémarrage).
    @MainActor func testConfirmingAReviewOnTheRecordScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-engramUITestSeed", "-engramUITestRecordReview", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_CA"]
        app.launch()
        let editor = app.textViews["Transcription à vérifier"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8), "Carte « Vérifie ta note » absente de l'écran Enregistrer")
        editor.tap()
        editor.typeText(" svp")
        snap(app, "19-verifie-enregistrer-clair")
        XCTAssertTrue(tap(app.buttons["Classer"]), "Bouton « Classer » introuvable")
        sleep(4)
        XCTAssertEqual(app.state, .runningForeground, "L'app s'est fermée après « Classer »")
        XCTAssertFalse(app.textViews["Transcription à vérifier"].exists, "La carte devrait avoir disparu")
        snap(app, "19b-apres-classer-enregistrer-clair")
    }

    /// Bug signalé : « Ton cerveau est vide » s'affichait par-dessus des points. Mémoire vide : seulement le message.
    @MainActor func testEmptyMemory() {
        let app = XCUIApplication()
        app.launchArguments = ["-engramUITestSeed", "-engramUITestEmpty", "-engramUITestDark",
                               "-AppleLanguages", "(fr)", "-AppleLocale", "fr_CA"]
        app.launch()
        tapTab(app, "Cerveau")
        XCTAssertTrue(app.staticTexts["Ton cerveau est vide"].waitForExistence(timeout: 5), "Cerveau vide : message absent")
        snap(app, "17-cerveau-vide-sombre")
        tapTab(app, "Notes")
        XCTAssertTrue(app.staticTexts["Aucune note pour l'instant"].waitForExistence(timeout: 5), "Notes vides : message absent")
        snap(app, "18-notes-vides-sombre")
    }

    @MainActor
    private func captureAll(dark: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-engramUITestSeed", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_CA"]
            + (dark ? ["-engramUITestDark"] : [])
        app.launch()
        let mode = dark ? "sombre" : "clair"

        snap(app, "01-enregistrer-\(mode)")

        tapTab(app, "Notes")
        snap(app, "02-notes-\(mode)")

        if tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Maison")).firstMatch) {
            snap(app, "03-categorie-maison-\(mode)")
            if tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Tailler la haie")).firstMatch) {
                snap(app, "03b-detail-note-\(mode)")
                app.swipeUp()
                snap(app, "03c-detail-classement-\(mode)")
                goBack(app)
            }
            goBack(app)
        }

        if tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "À faire")).firstMatch) {
            snap(app, "03d-a-faire-\(mode)")
            goBack(app)
        }

        if tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "À vérifier")).firstMatch) {
            snap(app, "04-a-verifier-\(mode)")
            if tap(app.cells.firstMatch) {
                snap(app, "05-verifie-ta-note-\(mode)")
                // Confirmer la dictée : elle quitte « À vérifier » et va au classement (sur le simulateur, sans
                // service en ligne, elle reste sur l'iPhone). L'écran se ferme alors tout seul.
                if tap(app.buttons["Classer"]) {
                    XCTAssertTrue(app.staticTexts["Rien à vérifier"].waitForExistence(timeout: 10),
                                  "La dictée confirmée devrait quitter « À vérifier »")
                    snap(app, "05b-apres-classer-\(mode)")
                } else {
                    goBack(app)
                }
            }
            goBack(app)
        }

        if tap(app.buttons["Plus"]) {
            snap(app, "06-menu-\(mode)")
            if tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Corbeille")).firstMatch) {
                snap(app, "07-corbeille-\(mode)")
                let cell = app.cells.firstMatch
                if cell.waitForExistence(timeout: 3) {
                    cell.swipeLeft()
                    // Bug signalé : seul « Restaurer » apparaissait. Les deux actions doivent être là. Vérifié avant
                    // la capture : l'audit d'accessibilité qui la suit change la taille du texte et referme le balayage.
                    let restore = app.buttons["Restaurer"]
                    let delete = app.buttons["Supprimer"]
                    if !(restore.waitForExistence(timeout: 3) && delete.exists) {
                        attachTree(app, "arbre-08-corbeille-balayage-\(mode)")
                    }
                    XCTAssertTrue(restore.exists, "Restaurer manquant dans la corbeille")
                    XCTAssertTrue(delete.exists, "Supprimer manquant dans la corbeille")
                    snap(app, "08-corbeille-balayage-\(mode)")
                    app.navigationBars.firstMatch.tap()
                }
                if tap(app.buttons["Tout supprimer"]) {
                    snap(app, "09-tout-supprimer-\(mode)")
                    // Bug signalé : pas de « Tout supprimer ». On vide la corbeille pour de vrai (notes inventées).
                    if tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Supprimer 1 note")).firstMatch) {
                        XCTAssertTrue(app.staticTexts["Corbeille vide"].waitForExistence(timeout: 5), "La corbeille ne s'est pas vidée")
                        snap(app, "09b-corbeille-vide-\(mode)")
                    } else {
                        attachTree(app, "arbre-09-tout-supprimer-\(mode)")
                        XCTFail("Confirmation « Supprimer 1 note définitivement » introuvable")
                        dismissDialog(app)
                    }
                }
                goBack(app)
            }
        }

        if tap(app.buttons["Nouvelle note"]) {
            snap(app, "10-ecrire-\(mode)")
            tap(app.buttons["Annuler"])
        }

        if tap(app.buttons["Plus"]), tap(app.buttons["Réglages"]) {
            snap(app, "11-reglages-\(mode)")
            app.swipeUp()
            snap(app, "12-reglages-transcription-\(mode)")
            app.swipeUp()
            snap(app, "13-reglages-intelligence-\(mode)")
            app.swipeUp()
            snap(app, "14-reglages-cles-\(mode)")
            app.swipeDown()
            app.swipeDown()
            if tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Banc d'essai")).firstMatch) {
                snap(app, "14b-banc-d-essai-\(mode)")
                goBack(app)
            }
            goBack(app)
        }

        tapTab(app, "Cerveau")
        snap(app, "15-cerveau-\(mode)")

        tapTab(app, "Calendrier")
        snap(app, "16-calendrier-\(mode)")

        // Retrouver : une question floue retrouve la vraie note, qu'on ouvre d'un toucher.
        tapTab(app, "Retrouver")
        snap(app, "20-retrouver-\(mode)")
        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 4) {
            field.tap()
            field.typeText("C'était quoi déjà le rendez-vous chez le dentiste ?\n")
            let hit = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Dentiste vendredi")).firstMatch
            XCTAssertTrue(hit.waitForExistence(timeout: 20), "Retrouver n'a pas trouvé la note du dentiste")
            snap(app, "21-retrouver-reponse-\(mode)")
            if tap(hit) {
                snap(app, "22-retrouver-note-\(mode)")
                goBack(app)
            }
        } else {
            XCTFail("Champ de question de Retrouver introuvable")
        }
    }

    // MARK: - Outils

    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        sleep(1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        audit(app, name)
    }

    /// Audit d'accessibilité d'iOS (contraste, libellés, zones touchables, taille du texte) : les problèmes sont
    /// notés dans un rapport joint, sans faire échouer le test (certains viennent du système).
    @MainActor
    private func audit(_ app: XCUIApplication, _ name: String) {
        var lines: [String] = []
        try? app.performAccessibilityAudit(for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription,
                                                 .textClipped, .trait]) { issue in
            let element = issue.element.map { "\($0.elementType.rawValue) « \($0.label) »" } ?? "?"
            lines.append("\(issue.auditType.rawValue) | \(issue.compactDescription) | \(element)")
            return true
        }
        let report = XCTAttachment(string: lines.isEmpty ? "aucun problème" : lines.joined(separator: "\n"))
        report.name = "audit-\(name).txt"
        report.lifetime = .keepAlways
        add(report)
    }

    /// Arbre des éléments de l'écran (types, libellés), joint au rapport pour comprendre un échec.
    @MainActor
    private func attachTree(_ app: XCUIApplication, _ name: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name).txt"
        tree.lifetime = .keepAlways
        add(tree)
    }

    @MainActor @discardableResult
    private func tap(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 4) else { return false }
        // Une feuille ou un menu en cours d'animation n'est pas encore touchable : on lui laisse un peu de temps.
        for _ in 0..<4 where !element.isHittable { sleep(1) }
        guard element.isHittable else { return false }
        element.tap()
        return true
    }

    @MainActor
    private func tapTab(_ app: XCUIApplication, _ name: String) {
        if !tap(app.tabBars.buttons[name]) { tap(app.buttons[name]) }
    }

    /// Retour à l'écran précédent, seulement par le vrai bouton « retour » (jamais un autre bouton de la barre).
    @MainActor
    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons["BackButton"]
        if back.waitForExistence(timeout: 2), back.isHittable { back.tap() }
    }

    @MainActor
    private func dismissDialog(_ app: XCUIApplication) {
        for label in ["Annuler", "Cancel"] where tap(app.buttons[label]) { return }
        app.swipeDown()
    }
}

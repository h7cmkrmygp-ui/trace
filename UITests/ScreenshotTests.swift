import XCTest

/// Captures d'écran de chaque écran, en mode clair et sombre, avec des notes **inventées** (base en mémoire).
/// Elles permettent de vérifier l'apparence sans iPhone : contraste, cartes, corbeille, réglages…
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor func testScreensInLightMode() { captureAll(dark: false) }

    @MainActor func testScreensInDarkMode() { captureAll(dark: true) }

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
                // service en ligne, elle reste sur l'iPhone).
                if tap(app.buttons["Classer"]) {
                    sleep(3)
                    snap(app, "05b-apres-classer-\(mode)")
                }
                goBack(app)
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
                    snap(app, "08-corbeille-balayage-\(mode)")
                    // Bug signalé : seul « Restaurer » apparaissait. Les deux actions doivent être là.
                    XCTAssertTrue(app.buttons["Restaurer"].exists, "Restaurer manquant dans la corbeille")
                    XCTAssertTrue(app.buttons["Supprimer"].exists, "Supprimer manquant dans la corbeille")
                    app.navigationBars.firstMatch.tap()
                }
                if tap(app.buttons["Tout supprimer"]) {
                    snap(app, "09-tout-supprimer-\(mode)")
                    // Bug signalé : pas de « Tout supprimer ». On vide la corbeille pour de vrai (notes inventées).
                    if tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Supprimer 1 note")).firstMatch) {
                        XCTAssertTrue(app.staticTexts["Corbeille vide"].waitForExistence(timeout: 5), "La corbeille ne s'est pas vidée")
                        snap(app, "09b-corbeille-vide-\(mode)")
                    } else {
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

    @MainActor @discardableResult
    private func tap(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 4), element.isHittable else { return false }
        element.tap()
        return true
    }

    @MainActor
    private func tapTab(_ app: XCUIApplication, _ name: String) {
        if !tap(app.tabBars.buttons[name]) { tap(app.buttons[name]) }
    }

    @MainActor
    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 2), back.isHittable { back.tap() }
    }

    @MainActor
    private func dismissDialog(_ app: XCUIApplication) {
        for label in ["Annuler", "Cancel"] where tap(app.buttons[label]) { return }
        app.swipeDown()
    }
}

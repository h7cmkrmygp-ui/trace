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
            goBack(app)
        }

        if tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "À vérifier")).firstMatch) {
            snap(app, "04-a-verifier-\(mode)")
            if tap(app.cells.firstMatch) {
                snap(app, "05-verifie-ta-note-\(mode)")
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
                    app.navigationBars.firstMatch.tap()
                }
                if tap(app.buttons["Tout supprimer"]) {
                    snap(app, "09-tout-supprimer-\(mode)")
                    dismissDialog(app)
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

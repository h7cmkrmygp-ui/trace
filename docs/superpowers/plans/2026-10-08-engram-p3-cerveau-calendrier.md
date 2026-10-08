# Engram P3 — « Cerveau et Calendrier » : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (exécution en ligne, TDD via la CI).

- **Goal :** des échéances calculées sans invention à partir des dates dictées, un Calendrier (mois + jour) qui ajoute automatiquement les rendez-vous au calendrier de l'iPhone, et un écran Cerveau en nuage de points.
- **Spec :** `docs/superpowers/specs/2026-10-08-engram-p3-cerveau-calendrier-design.md`
- **Forme (ruling, comme P2) :** les tâches fixent les fichiers, interfaces et tests ; le code est écrit une seule fois, en TDD.

## Global Constraints
- Contraintes P1 et P2 inchangées.
- **Migration v2 :** ajout seul (`ALTER TABLE … ADD COLUMN`, nouvelles tables), sans jamais modifier v1.
- **Dates :**
  - calculées par `DateResolver` relativement à `source.captured_at` ;
  - fuseau et calendrier injectés (`Calendar`), calendrier grégorien en CI ;
  - une expression vague ne donne aucune date.
- **Rendez-vous ajoutés au calendrier :** 1 h si l'heure est connue (note « Durée estimée par Engram »), sinon journée entière. Jamais de modification ni de suppression d'un événement existant.

## Review Focus
1. Une expression vague (« bientôt », « la semaine prochaine ») ne donne aucune date, plutôt qu'une date inventée.
2. Une date du jour déjà passée cette année (« 3 janvier » dit en octobre) va à l'année suivante.
3. Une base v1 réelle (celle de l'iPhone) migre en v2 sans perte.
4. Un souvenir déjà relié à un événement n'en crée pas un second, même s'il est retraité.
5. Sans accès au calendrier, les échéances restent visibles dans Engram et aucune erreur ne bloque.

## Tâches
1. **`DateResolver` (Core) et ses tests.** `resolve(_ expression:, relativeTo:, calendar:) -> ResolvedDate?` et `firstDate(in:excerpt:relativeTo:calendar:)`.
2. **Migration v2 et échéances (Store).**
   - `Memory.dueAt` et `dueHasTime` ;
   - `ThoughtFiler` calcule l'échéance de chaque pensée ;
   - `memoriesStream(dueFrom:to:)` ;
   - `SettingStore` (get, set, bool) ;
   - `CalendarLinkStore` (link, link(for:), unlinkedAppointments).
   - Tests : migration v1 → v2 avec données, échéance au classement, réglages, liens.
3. **`BrainLayout` (Core) et `BrainSnapshot` (Store), avec leurs tests.**
4. **`EngramCalendar` (EventKit)**, vérifié par la compilation seulement.
5. **App.**
   - 4 onglets ;
   - `BrainView` ;
   - `CalendarView` (mois et jour) ;
   - ajout automatique des rendez-vous après classement ;
   - section Calendrier des Réglages ;
   - `NSCalendarsFullAccessUsageDescription`.
6. **`LanguageModelError`** à la place de `GenerationError` dans `AppleThoughtAnalyzer`.
7. **Relecture finale indépendante de la branche** (P2 + P3) et corrections.
8. **Documents et liste de contrôle groupée** pour le propriétaire.

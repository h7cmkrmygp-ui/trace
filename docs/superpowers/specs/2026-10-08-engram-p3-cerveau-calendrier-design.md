# Engram — Spécification · P3 « Cerveau et Calendrier »

- **Date :** 2026-10-08
- **Statut :** décidée par Claude sur mandat du propriétaire (« continue le développement, je testerai tout d'un coup », 2026-10-08), dans la continuité des choix déjà validés : captures de référence, onglets Enregistrer · Cerveau · Calendrier · Notes, calendrier relié à Google par le Calendrier de l'iPhone.
- **S'appuie sur :** spec Phase 1 et spec P2.

## 1. Intention
- **Cerveau.** Un écran qui montre la mémoire comme un nuage de points : les catégories, et autour d'elles leurs pensées. Toucher un point l'ouvre. Une recherche met en évidence les points correspondants.
- **Calendrier.** Quand une pensée contient une date (« dentiste vendredi à 14 h », « congé le 29 octobre »), elle reçoit une **échéance** et apparaît dans le Calendrier d'Engram.
  - Les **rendez-vous** datés sont **ajoutés automatiquement** au calendrier de l'iPhone choisi par le propriétaire. Un compte Google ajouté dans iOS est un calendrier comme les autres.
  - L'option se désactive dans les Réglages.
- **Aujourd'hui.** Le Calendrier s'ouvre sur le jour courant : les échéances d'Engram et les événements du calendrier de l'iPhone.

## 2. Règles
- **Aucune date inventée.** L'IA relève seulement les expressions de date (`mentionedDates`, P2). La date réelle est calculée par un **analyseur déterministe** (`DateResolver`, testé en CI) relativement au moment de la capture. Une expression vague comme « bientôt » ou « la semaine prochaine » ne donne **aucune** échéance.
- **Formes reconnues** (français et anglais) :
  - aujourd'hui / today, demain / tomorrow, après-demain ;
  - jours de la semaine : prochaine occurrence, 1 à 7 jours après la capture ;
  - « le 29 », « 29 octobre », « 29 oct. », « October 29 », « 29/10 », avec année facultative (une date déjà passée cette année va à l'année suivante) ;
  - « dans 3 jours » / « in 3 days », « dans 2 semaines » ;
  - heures : « 14 h », « 14h30 », « 14:30 », « à 9 h », « 2 pm », « midi », « minuit ».

  Une heure seule s'applique au jour de la capture.
- **Durée d'un rendez-vous ajouté** : 1 h si une heure est connue, avec la note « Durée estimée par Engram » dans l'événement ; sinon un événement « journée entière ». La durée n'est jamais présentée comme certaine.
- **Pas de doublon d'événement.** Une table `calendar_link` relie un souvenir à l'événement créé, et un souvenir déjà relié n'en crée pas un second.
- **Le calendrier du propriétaire n'est jamais modifié silencieusement.** Engram n'ajoute que des événements nouveaux. Supprimer ou archiver un souvenir ne touche pas son événement.

## 3. Données (migration v2, la première vraie migration)
- `memory.due_at DATETIME` (nul par défaut) et `memory.due_has_time INTEGER` (0 ou 1), avec un index sur `due_at`.
- Index `memory_trashed_at`, remarque mineure de la relecture P1.
- Table `calendar_link(memory_id PK → memory ON DELETE CASCADE, event_identifier, calendar_identifier, created_at)`.
- Réglages (table `setting`) :
  - `calendar.autoAdd` (« 1 » par défaut) ;
  - `calendar.targetIdentifier` (vide = calendrier par défaut d'iOS).
- Une base v1 existante migre sans perte (test).

## 4. Architecture
| Module | Ajout | Testé en CI |
|---|---|---|
| `EngramCore` | `DateResolver` (expressions → `ResolvedDate { date, hasTime }`), `BrainLayout` (positions déterministes) | oui |
| `EngramStore` | migration v2 ; `Memory.dueAt` et `dueHasTime` ; échéance calculée par `ThoughtFiler` ; `SettingStore` ; `CalendarLinkStore` ; `memoriesStream(dueFrom:to:)` ; `BrainSnapshot` | oui |
| `EngramCalendar` (nouveau) | `CalendarService` (EventKit : accès, calendriers modifiables, événements d'une période, ajout) | compilation seulement |
| App | onglets **Enregistrer · Cerveau · Calendrier · Notes** ; `BrainView`, `CalendarView`, ajout automatique après classement, section Calendrier des Réglages | compilation et iPhone |

## 5. Cerveau (`BrainLayout`)
- **Centre :** un nœud « toi ».
- **Catégories racines :** réparties sur un cercle de rayon 0,32 × taille, triées par nom. Les sous-catégories sont un peu plus loin, dans l'angle de leur parent.
- **Pensées :** placées autour de leur catégorie la plus précise selon une spirale à angle d'or, déterministe et sans hasard. Les pensées « À classer » sont près du centre.
- **Taille des nœuds :** catégorie = 6 + √(nombre de pensées) × 2 points ; pensée = 3 points.
- **Vue :** SwiftUI `Canvas`, avec pincer pour zoomer, glisser pour déplacer et toucher pour ouvrir. Les lignes vers la catégorie sont très fines. Recherche : les pensées correspondantes sont mises en évidence.
- **Accessibilité :** une liste VoiceOver des catégories avec leur nombre de pensées.

## 6. Calendrier
- **Grille du mois :** 7 colonnes de lundi à dimanche, en français, avec un point sous les jours qui ont une échéance ou un événement. Des flèches changent de mois.
- **Sous la grille :** la liste du jour choisi (aujourd'hui par défaut), avec les échéances d'Engram (cercle à cocher = « Fait », qui archive) et les événements de l'iPhone en lecture seule.
- **Accès :** sans accès au calendrier, un bouton « Autoriser l'accès au calendrier » s'affiche. Les échéances d'Engram restent visibles sans accès.

## 7. Modifications annexes
- `AppleThoughtAnalyzer` attrape `LanguageModelError` (iOS 27 : `contextSizeExceeded`, `rateLimited`, `guardrailViolation`, `refusal`, `unsupportedLanguageOrLocale`, `timeout`…) à la place de `GenerationError`, déprécié. Les autres erreurs sont traitées selon leur description.
- `project.yml` : ajout de `NSCalendarsFullAccessUsageDescription`.

## 8. Tests
- **CI :**
  - `DateResolver` : plus de 20 cas FR et EN, des cas vagues sans date, le passage à l'année suivante, les heures ;
  - `BrainLayout` : déterminisme, chaque pensée placée, pas de NaN, pensées proches de leur catégorie ;
  - migration v2 depuis une base v1 ;
  - échéance calculée au classement ;
  - `SettingStore` et `CalendarLinkStore` ;
  - flux par période.
- **iPhone :** liste de contrôle groupée avec P2 (le propriétaire teste tout d'un coup).

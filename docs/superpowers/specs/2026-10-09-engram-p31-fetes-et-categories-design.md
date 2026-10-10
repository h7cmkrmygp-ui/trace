# P31 — Les fêtes bien retenues, des catégories qui viennent du sens de la note

**Signalé sur l'iPhone par le propriétaire** :

- Une fête dictée (ici avec un prénom inventé : « Retiens l'anniversaire de Inès c'est le 13 octobre ») s'est retrouvée
  dans **Santé › Poids**.
- Il veut des catégories qui ne sont pas « pré-écrites » : l'IA doit chercher dans les catégories existantes, réutiliser
  celle qui convient vraiment, et sinon en créer une nouvelle.
- Dans Retrouver, « C'est quand déjà la fête à Inès ? » répondait « Je ne trouve rien là-dessus dans ta mémoire. »

## Causes trouvées

- **Les consignes de l'IA donnaient des listes toutes faites.**
  - Les consignes envoyées à Gemini et à Groq, et celles du modèle d'Apple, citaient des exemples : « Santé, Travail,
    Finance… » et « Santé › Poids, Finance › Assurances… ».
  - Elles obligeaient presque à mettre une sous-catégorie, et ne disaient rien des fêtes.
  - L'IA collait donc la note au premier dossier qui ressemblait.
- **L'indice des « catégories probables » trompait le modèle d'Apple.** Quand le sens n'était pas disponible, il
  recevait les 5 premières catégories par ordre alphabétique, présentées comme les plus probables.
- **Aucun garde-fou pour les suivis.** Un dossier de mesure (« Poids ») acceptait n'importe quelle note.
- **Des façons de dire une fête n'étaient pas reconnues** :
  - « la fête **à** Inès » ;
  - un jour en lettres (« le treize octobre », « le premier mars ») ;
  - « Inès fête ses 30 ans le 13 octobre » ;
  - « C'est la fête de Marc le 1er mars ».
- **Les fêtes des anciennes notes n'étaient jamais relues.**
- **Retrouver** :
  - ne savait pas que « fête » et « anniversaire » veulent dire la même chose ;
  - ne lisait pas les fêtes gardées sur la page des personnes.

## Ce qui change

- **Des catégories qui viennent du sens.**
  - Les consignes ne contiennent plus aucune liste de catégories.
  - Elles demandent de lire les catégories existantes et d'en réutiliser une seulement si le sujet de la note y
    appartient vraiment. Sinon, l'IA crée une nouvelle catégorie : un domaine de vie, en français.
  - La sous-catégorie est facultative.
  - Une fête va avec la famille ou les amis, jamais en santé ni en argent.
  - Un dossier de mesure ne reçoit que cette mesure.
- **Ce qu'Engram a déjà reconnu est dit à l'IA** (`NoteFacts`). Exemples : « la fête d'Inès, le 13 octobre (une date
  pour une personne, pas une mesure de santé) », « une mesure de poids », « un ajout à la liste d'épicerie ».
  - Rien de plus que la note elle-même ne part.
  - Le choix du service (Gemini, Groq, iPhone) ne change pas.
- **Les indices du modèle d'Apple** ne donnent que les catégories vraiment proches du sens, et aucune quand le sens
  n'est pas disponible.
- **Garde-fou des suivis.** Une note proposée dans un dossier de mesure (Poids, Sommeil, Tension, Pouls, Pas,
  Glycémie) qui ne contient ni cette mesure ni ses mots reste « À classer » plutôt que mal rangée.
- **Les fêtes** :
  - nouvelles tournures reconnues ;
  - l'âge fêté donne l'année de naissance ;
  - si l'extrait de l'IA est incomplet, la note entière est relue.
- **Une seule fois, au lancement** :
  - les anciennes notes sont relues pour y trouver les fêtes manquantes ; une fête déjà posée, à la main ou dite,
    est gardée ;
  - les notes rangées par l'IA dans un suivi sans rapport en sont retirées ; une note rangée ou confirmée par le
    propriétaire n'est jamais touchée.
- **Retrouver et Siri.**
  - Pour « C'est quand la fête à Inès ? », la réponse vient de la page de la personne : « La fête d'Inès, c'est le
    13 octobre, dans 4 jours. »
  - Un nom entendu à une lettre près (« Inèz ») est retrouvé s'il n'y en a qu'un.
  - « Fête » trouve aussi « anniversaire ».

## Ce qui ne change pas

- Les catégories existantes ne sont ni renommées ni fusionnées toutes seules : « Automobile › car part » reste là où
  il est, et le propriétaire peut le renommer ou le fusionner.
- Aucune nouvelle migration.

# P14 — Rappels de lieu

**But** : « Rappelle-moi d'acheter du lait quand j'arrive chez Costco » prévient en arrivant chez Costco, pas à une heure.
S'appuie sur les lieux de la P9.

## Ce que le propriétaire voit

- **Dicté** : « quand j'arrive chez / au / à la… », « en arrivant à… », « quand je passe au… », « une fois rendu chez… »,
  « quand je pars du… », « en sortant du… », « quand je quitte le… », « when I get to… », « when I leave… ». La note
  porte la pastille « En arrivant · Costco » (ou « En partant · Bureau »).
- **Dans une note** : … › « Rappel en arrivant à un lieu… » pour en poser un à la main (un lieu connu ou nouveau,
  en arrivant ou en partant) ; appui long sur la pastille : changer pour « en partant », ou retirer.
- **Dans un lieu** (Notes › Lieux › Costco) : « Adresse » avec une petite carte. « Ajouter l'adresse » : ma position
  actuelle, ou une recherche d'adresse ; rayon 100, 200 ou 500 m. « Rappels ici » liste les notes qui attendent ce lieu.
- **En arrivant** : notification « Costco » / « Acheter du lait » ; la toucher ouvre la note, « Fait » la coche.
  Tant que la note n'est pas faite, le rappel revient à chaque arrivée.

## Règles

- Seulement les notes vivantes (actives ou « À classer »), dont le lieu est actif et a une adresse.
- iOS surveille au plus 20 lieux par app : les 20 rappels les plus récents.
- Note privée (gardée sur l'iPhone ou jugée secrète), ou Engram verrouillé : « Rappel Engram » / « Ouvre Engram pour le
  voir. » sur l'écran verrouillé.
- Pièges : « quand j'arrive à dormir », « je suis à l'aise », « acheter du lait chez Costco » (aucun déclencheur), « au
  bout », « à travers » ne créent rien. Un « à » nu exige un nom propre (« à Laval », « à Costco »).
- « chez nous », « chez moi », « à la maison », « home » → le lieu « Maison ».
- Une décision du propriétaire (pastille posée ou retirée à la main) n'est jamais remplacée par l'IA.
- Fusionner deux lieux garde les rappels et l'adresse (celle du lieu gardé d'abord).

## Technique

- Core `PlaceReminders.swift` : `PlaceEvent`, `ParsedPlaceTrigger`, `PlaceTriggerParser.parse(_:)`,
  `PlaceLocation`, `PlaceTrigger`, `PlaceReminderPlanner` (`Item`, `Planned`, `plan(_:limit:)`).
- Migration v8 : `place_location` (une adresse par lieu) et `place_trigger` (un rappel par note), effacés avec la note
  ou le lieu.
- `EntityStore` : adresse (poser, retirer, lire, flux), rappels (poser, retirer, lire, flux, ceux d'un lieu),
  `placeReminderItems()` ; `ThoughtFiler` pose le rappel dicté ; la fusion le déplace ; l'export l'inclut.
- App : `UNLocationNotificationTrigger` (l'autorisation « Lorsque l'app est active » suffit, iOS réveille la
  notification seul), `CLLocationUpdate` pour la position actuelle, `MKLocalSearch` pour une adresse (la recherche passe
  par Plans d'Apple : seulement le texte cherché, jamais une note), carte `Map` de MapKit.
- Le lieu exact (coordonnées) reste dans la base sur l'iPhone et dans la sauvegarde chiffrée.

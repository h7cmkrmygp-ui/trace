# P30 — L'adresse des lieux, trouvée toute seule

**Demande du propriétaire** : « quand j'arrive au Costco », sans avoir à entrer l'adresse à la main.

## Ce que le propriétaire voit

- Dès qu'un rappel de lieu est dicté (P14) — ou qu'une liste porte le nom d'un lieu (P29) — Engram cherche ce lieu
  autour de lui avec Plans d'Apple et pose l'adresse tout seul. La pastille passe de « adresse à ajouter » à
  « En arrivant · Costco ».
- **N'importe quel Costco** : les 3 succursales les plus proches (à moins de 40 km) sont surveillées ; arriver à
  l'une d'elles prévient. Un mot général (« pharmacie », « dépanneur ») marche aussi : les plus proches.
- **La page du lieu** dit « Trouvée toute seule près de toi. Aussi surveillé : … ». « Changer l'adresse » pour n'en
  garder qu'une ; ce choix l'emporte pour toujours.
- **Réglages › Rappels** › « Trouver l'adresse des lieux tout seul » (activé par défaut).

## Règles

- Jamais un lieu à soi : la maison, le bureau, le travail, le chalet, l'école, la garderie, le garage, le gym, ni
  « chez Julie » (une personne connue). Pour ceux-là : « Ma position actuelle » quand on y est.
- Les noms qui contiennent le lieu passent d'abord (« Costco Laval » pour « Costco ») ; deux résultats à moins de
  100 m n'en font qu'un.
- Une recherche sans résultat attend une semaine ; sans réseau, elle se refait au prochain retour dans l'app.
- La position est demandée (« Lorsque l'app est active ») au moment où elle sert, juste après la dictée ; au
  lancement, jamais de demande.
- Ce qui part chez Apple : le nom du lieu et la zone autour de toi (60 km), jamais une note.
- Toutes les succursales comptent dans les 20 régions qu'iOS surveille (les rappels les plus récents d'abord).

## Technique

- Core `PlaceFinder` (`canSearch`, `choose`, `distance`) ; `PlaceReminderPlanner.Item.branches`, une région par
  succursale.
- Migration v15 : `place_branch`, `place_lookup` (dernière recherche, choix manuel). `EntityStore` :
  `placesNeedingLocation`, `recordLookup`, `branches`, `isAutoLocated` ; `setLocation`/`removeLocation` marquent le
  choix du propriétaire. Export : `place_branches`.
- App : `PlaceSearch` (MKLocalSearch), `AppModel.locateMissingPlaces` après chaque dictée et au retour dans l'app.

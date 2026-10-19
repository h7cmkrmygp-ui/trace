# P29 — La liste t'attend au magasin

**But** : une liste qui porte le nom d'un lieu (« Liste de Costco ») prévient en arrivant à ce lieu, sans rien régler :
« Costco » / « Liste de Costco : piles et papier de toilette ».

## Règles

- Le lieu doit exister dans Engram (P9) et avoir une adresse (P14) ; la liste doit avoir quelque chose à prendre.
- Une liste toute cochée ne prévient plus ; une liste reliée à la main à un lieu (P14) garde ce rappel-là, jamais en
  double.
- Au plus 3 choses nommées (« … et 2 autres »). Une liste privée, ou Engram verrouillé : « Rappel Engram ».
- Comme tout rappel de lieu, c'est iOS qui surveille (20 lieux au plus).

## Technique

- Core : `ListSpeech.waitingTitle`. Store : `EntityStore.listsWaitingAtPlaces` ajouté à `placeReminderItems`
  (le nom de la liste comparé à la clé du lieu, `EntityName.key`).

# P26 — Les listes avec Siri

**But** : au magasin, les mains pleines : « Dis Siri, lis ma liste dans Engram » ; « Dis Siri, ajoute à ma liste dans
Engram » (Siri demande quoi).

## Ce que le propriétaire voit (et entend)

- **Lire** : « Sur ta liste d'épicerie : lait, pain et œufs. » ; « Tout est coché sur ta liste d'épicerie. » ;
  « Ta liste d'épicerie est vide. » ; plus de 8 choses : « … et 3 autres choses ». Une liste nommée (« la liste de
  Costco », « mes courses ») est cherchée par son nom. iPhone déverrouillé exigé.
- **Ajouter** : Siri demande « Qu'est-ce que j'ajoute ? », Engram classe « Ajoute … à ma liste d'épicerie » comme une
  dictée (P15), puis répond « C'est ajouté à ta liste d'épicerie. »
- Aussi dans l'app Raccourcis : « Lire une liste Engram », « Ajouter à une liste Engram ».

## Règles

- Une liste privée ne dit que le nombre (« Ta liste privée a 2 choses. Ouvre Engram pour les voir. »).
- Une liste introuvable : « Je ne trouve pas ta liste « … ». »
- Rien ne part de l'iPhone.

## Technique

- Core `ListSpeech.swift` : `read`, `addCommand`, `added(to:)`, `matches`.
- App : `ReadListIntent`, `AddToListIntent`, deux raccourcis Siri ; `AppModel.readList(named:)`.

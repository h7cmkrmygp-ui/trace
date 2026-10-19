# P25 — Widget « Liste »

**But** : au magasin, voir sur l'écran d'accueil ce qui reste sur la liste d'épicerie, sans ouvrir Engram.

## Ce que le propriétaire voit

- Un widget « Liste » (petit, moyen, grand) : la liste d'épicerie d'abord (sinon la plus récemment complétée), les
  choses qui restent (4 en petit, 6 en moyen sur deux colonnes ; le grand montre deux listes), « et 3 de plus ».
- Toucher le widget ouvre la liste dans Engram ; cocher se fait dans Engram (ou à la voix, P19), et le widget suit.

## Règles

- Une liste privée (dictée gardée sur l'iPhone, ou jugée secrète) s'appelle « Liste privée » et ne montre que le nombre.
- Engram verrouillé : seulement les nombres. Écran verrouillé ou mode En veille : les noms des choses sont masqués.
- Au plus 4 listes et 8 choses par liste dans le dossier partagé. Seulement avec l'installation complète (avec les
  widgets) ; l'installation simple n'a pas de widget.

## Technique

- Core `ListsSnapshot.swift` (`Source`, `List`, `make`) ; `ListStore.widgetSources()`.
- `SharedContainer.writeLists`/`readLists` (`widget-lists.json`) ; l'app réécrit à chaque changement de liste et à
  chaque recalcul des rappels ; `ListsWidget` (« engram.lists ») ; `engram://list/<id>` et `engram://lists`.

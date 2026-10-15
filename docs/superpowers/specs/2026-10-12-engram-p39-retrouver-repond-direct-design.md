# P39 — Retrouver répond direct

Troisième des quatre améliorations choisies par le propriétaire.

## Pourquoi

Retrouver trouvait la bonne note, mais répondait souvent seulement « J'ai trouvé ceci : … », ou laissait le modèle d'Apple
(sur l'iPhone, assez faible) rédiger une phrase. Pour une question de fait, on veut la réponse elle-même.

## Ce qui change

- **La réponse exacte** (`DirectAnswer`), pour une question de fait sur la meilleure note (score d'au moins 0,8) :
  - **un montant** (« Combien j'ai payé pour les pneus ? ») : « 640 $ — dans ta note « Pneus d'hiver » du 3 mars. » ;
  - **un numéro** (« le numéro de ma police », « mon code ») : le nombre de la note, d'au moins 4 chiffres, pris dans la
    phrase qui répond ;
  - **une date** (« C'est quand… ? », « À quelle heure… ? ») : la date prévue de la note, « Le mardi 20 octobre à
    14 h — dans ta note « Dentiste ». » ;
  - **un endroit** (« Où j'ai mis… ? ») : la phrase de la note qui le dit, entre guillemets.
- **Rien d'inventé.** Sans valeur dans la note, ou avec une note peu sûre, pas de réponse directe : la réponse habituelle
  prend le relais. Les fêtes gardent leur réponse (P31).
- **Le passage en gras** : sous chaque note trouvée, la phrase qui répond à la question, mots en gras, comme dans la
  recherche (P36).
- Siri (« Demande à Engram ») donne la même réponse directe.

Tout se calcule sur l'iPhone. Aucune migration.

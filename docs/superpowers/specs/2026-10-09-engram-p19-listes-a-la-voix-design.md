# P19 — Listes à la voix

**But** : au magasin, cocher ou retirer des cases de la liste en parlant, sans créer de note : « coche le lait »,
« j'ai acheté le pain pis le beurre », « enlève les bananes de ma liste d'épicerie ». Et partager une note (la liste,
par Messages).

## Ce que le propriétaire voit

- **Cocher** : « coche le lait (sur ma liste d'épicerie) », « j'ai acheté le pain », « I bought milk ». La case est
  cochée dans la liste qui la contient (l'épicerie d'abord), sans nouvelle note.
- **Retirer** : « enlève / retire / efface les bananes de ma liste (de cadeaux) », « remove bread from my grocery
  list ».
- **Partager** : dans une note, … › « Partager » (Messages, Courriel…). Rien n'est envoyé sans ton choix.

## Règles

- « lait » trouve « Lait 2 % » ; « bananes » trouve « Banane » ; « œufs » trouve « oeufs » ; jamais « Laitue ».
- « J'ai acheté une tondeuse », sans case qui corresponde, reste une note ordinaire. Une demande claire (« coche le
  café ») sans case qui corresponde ne devient pas une note.
- « Enlève tes souliers en entrant » n'est pas une liste. « Check the oil » non plus.
- Chaque changement est une version de la liste (« coché à la voix : Lait, Bananes »).

## Technique

- Core `ListActions.swift` : `ListAction`, `ListActionParser`, `ListMerge.matches`, `checking`, `removing`.
- `ListStore.apply` (la liste nommée, sinon celle qui contient les choses, l'épicerie d'abord) ; `ThoughtFiler` coche
  ou retire avant de compléter ou de créer une note. `ShareLink` dans le menu d'une note.

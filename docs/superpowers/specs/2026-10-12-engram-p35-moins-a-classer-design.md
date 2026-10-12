# P35 — Moins de « À classer »

Étape 2 du plan validé par le propriétaire (« b » : garder les dossiers créés par l'IA, avec les améliorations). Il
avait constaté : « Il met beaucoup dans À classer ; les erreurs, c'est pas souvent, mais ça arrive. » Ce sont à la fois
des copies en double et des notes seules.

## Causes

1. **Une copie de toute la dictée.** Quand les extraits couvraient moins de 60 % des mots (les « euh », « genre »,
   « ok » comptaient), ou qu'une pensée était rejetée, toute la dictée restait « À classer » en plus des notes rangées.
2. **Un échec définitif.** Si l'IA reformulait au lieu de recopier deux fois de suite, la note restait « À classer »
   pour toujours.
3. **Pas de dossier proposé**, ou un dossier refusé (un suivi sans sa mesure).
4. **Aucune explication** sur la note.

## Ce qui change

1. **Seule la partie oubliée reste** (`AnalysisValidator.leftover`) :
   - les propositions dont moins de la moitié des mots porteurs de sens sont repris ailleurs, sans les hésitations ni
     les liaisons (« euh », « genre », « pis », « faut »…) ;
   - seulement s'il reste au moins 3 mots porteurs de sens ;
   - la note provisoire est réduite à cette partie (`p35-reste`) et ne contient plus jamais toute la dictée.
2. **Une réponse reformulée classe quand même** (`AnalysisValidator.salvage`). Au second essai, la dictée entière
   devient une seule note :
   - avec les mots exacts du propriétaire, et le dossier, le type, les dates et les personnes choisis par l'IA ;
   - rien d'inventé n'est gardé : pas de texte rédigé, et le titre de l'IA seulement s'il parle de la note.
3. **Pas de dossier ? Les notes semblables décident** (P34), quand elles sont d'accord : au moins 2 notes, ou 1 rangée
   par le propriétaire, et un suivi qui ne la refuse pas. La raison le dit : « Rangée comme tes notes semblables… ».
4. **Les classements ratés sont réessayés** tout seuls, 3 fois au plus (migration v17, `source.analysis_attempts`).
5. **« Pourquoi elle est ici »** sous « À classer », sur chaque note : partie oubliée, pas encore classée, échec réessayé,
   échec après plusieurs essais (« range-la toi-même »), dossier retiré par le propriétaire, pas de dossier sûr.
6. **Une seule fois, au lancement** :
   - une ancienne copie déjà couverte par les notes rangées va à la corbeille, où elle se récupère ;
   - une copie qui contient autre chose est réduite à cette partie ;
   - les anciens échecs sont réessayés.
   Une note touchée par le propriétaire n'est jamais modifiée.

## Ce qui ne change pas

Le texte d'origine de chaque dictée reste dans la note (Détails › Texte d'origine) : rien ne se perd.

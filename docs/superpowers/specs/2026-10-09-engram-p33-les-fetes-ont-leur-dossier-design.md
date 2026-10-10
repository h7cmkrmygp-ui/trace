# P33 — Les fêtes ont leur dossier

**Signalé par le propriétaire** : « Quand je mentionne un anniversaire, ça met la personne dans une catégorie famille et
ça met sa fête dans tâche à faire. Il n'y a pas de catégorie anniversaire ni rien qui a été créé. »

## Causes

- Les consignes P31 disaient à l'IA de ranger une fête « avec la famille ou les amis » : elle obéissait.
- Rien ne disait qu'une fête est une chose à retenir. « Retiens… » faisait une tâche, avec une échéance au jour de la
  fête. Cette échéance faisait une seconde série de rappels, puis une tâche « en retard » pour toujours.
- Rien ne demandait un dossier pour les fêtes.

## Ce qui change

- **Une note qui dit seulement une fête** (« Retiens l'anniversaire de Inès c'est le 13 octobre », « C'est la fête de
  Marc le premier mars ») est reconnue sur l'iPhone, sans IA (`BirthdayParser.isOnlyABirthday`). Les mots autour
  (« retiens », « n'oublie pas que », « c'est ») ne comptent pas. Une telle note :
  - est une chose à retenir (`info`), jamais une tâche ;
  - n'a pas d'échéance : la page de la personne rappelle la fête la veille à 19 h et le jour même à 9 h, chaque année
    (P20) ;
  - va dans **Anniversaires**, créé avec sa description s'il n'existe pas. Si le propriétaire a déjà un dossier de
    fêtes (« Fêtes », « Famille › Anniversaires »…), c'est celui-là qui sert ;
  - affiche dans « Pourquoi ce dossier » : « La fête d'Inès, le 13 octobre : une date à retenir, rangée avec les
    anniversaires ; Engram te la rappelle chaque année. »
- **Une tâche autour d'une fête** (« Acheter un cadeau pour la fête de Julie le 12 mars ») reste une tâche, classée par
  l'IA.
- **Les consignes de l'IA** (`p33-cloud-v1`, `p33-v1`) disent la même chose : une fête seule est une chose à retenir
  dans le dossier des fêtes du propriétaire, ou « Anniversaires », jamais dans Famille.
- **Une seule fois, au lancement**, les anciennes notes qui disent seulement une fête vont dans ce dossier : elles
  quittent « À faire » et perdent leur échéance. Une note modifiée par le propriétaire, ou rangée ou confirmée par lui,
  n'est jamais touchée.
- **L'évaluation sur l'iPhone** attend « Anniversaires » (ou « Fêtes ») pour les fêtes.

Aucune migration.

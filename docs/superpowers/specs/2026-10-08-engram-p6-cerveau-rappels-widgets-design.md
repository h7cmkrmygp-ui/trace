# Engram P6 — Cerveau vivant, tâches qui avancent, widgets

Date : 2026-10-08. Demande du propriétaire : rendre le Cerveau beau et animé (« comme dans un vrai cerveau », avec
les catégories), des notifications qui font avancer les tâches, des widgets, les idées proposées en fin de P5
(partage vers Engram, résumé de la semaine, conversation gardée), et une app plus belle partout.

## 1. Cerveau vivant
- Fond en dégradé profond, silhouette de cerveau (symbole système) très légère qui « respire ».
- Chaque catégorie est un neurone lumineux de **sa couleur** (couleur stable, tirée de son nom), qui pulse doucement.
  Sa taille suit le nombre de notes.
- Les notes sont des étincelles **en orbite** autour de leur catégorie.
- Connexions courbes (synapses) ; des **signaux** lumineux les parcourent de temps en temps.
- Rangée de catégories (couleur, nombre) sous le titre : un toucher centre et agrandit la catégorie, un deuxième
  l'ouvre. Toucher un neurone ou une note : léger retour haptique, puis ouverture.
- « Réduire les animations » : tout reste immobile (même rendu, sans mouvement).
- Les mêmes couleurs de catégorie reviennent dans les Notes et dans Retrouver.

## 2. Des tâches qui se font
- Notifications de rappel avec boutons **« Fait »** (la tâche est rangée), **« Dans 1 h »**, **« Demain »**
  (9 h). Le report est gardé sur l'iPhone et repris à chaque recalcul.
- **Résumé du matin** (8 h) les jours où il y a quelque chose : les tâches du jour et celles **en retard**.
- **Pastille** sur l'icône : nombre de choses à faire aujourd'hui ou en retard.
- **Résumé de la semaine** (dimanche 18 h) : notes de la semaine, choses faites, choses à faire ; le toucher ouvre
  Retrouver avec « Résume ce que j'ai noté cette semaine ».
- Réglages : résumé du matin et résumé de la semaine, activés par défaut.
- Notes secrètes : jamais leur titre dans une notification ni dans un résumé.

## 3. Widgets
- **Aujourd'hui** (petit et moyen) : les choses à faire du jour, titres masqués écran verrouillé (`privacySensitive`),
  « Rappel privé » pour une note secrète.
- **Enregistrer** : un bouton qui ouvre Engram et commence à enregistrer (accueil, écran verrouillé, Centre de
  contrôle).
- Les widgets lisent un **petit résumé** (titres du jour, sans les notes secrètes) que l'app écrit dans un dossier
  partagé (App Group) ; la base reste dans l'app.

## 4. Idées de fin de P5
- **Partager vers Engram** (texte ou lien depuis Safari, Notes…) : l'extension dépose l'élément dans le dossier
  partagé ; l'app l'enregistre et le classe à l'ouverture suivante.
- **Conversation de Retrouver gardée** sur l'iPhone (30 derniers échanges) ; « Nouvelle recherche » l'efface.

## 5. Installation (AltStore, compte gratuit)
- Les extensions (widgets, partage) et le dossier partagé sont nouveaux pour AltStore. Pour ne jamais bloquer
  l'installation, la CI produit **deux IPA** : `Engram.ipa` (complète) et `Engram-simple.ipa` (sans extensions).
- Le dossier partagé est lu depuis `ALTAppGroups` (mis à jour par AltStore), sinon l'identifiant par défaut. Sans
  dossier partagé, l'app fonctionne normalement : seuls widgets et partage n'ont rien à afficher.

## 6. Vérification
Tests unitaires (couleurs, orbites, reports, résumés, partage), captures sur simulateur (Cerveau, widgets non
capturables), CI. Rien n'est déclaré vérifié sur l'iPhone sans le propriétaire.

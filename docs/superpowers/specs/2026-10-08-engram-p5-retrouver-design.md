# Engram P5 — « Je parle, c'est enregistré ; je demande, ça revient »

Date : 2026-10-08. Demande du propriétaire : audit complet, plantage à la sauvegarde, enregistrement vocal sans
confirmation, fonction « Retrouver », chat, simplicité. Le propriétaire a autorisé le travail autonome sans
confirmation détail par détail (consigne 13 de sa demande) ; les règles de base de `CLAUDE.md` restent en vigueur.

## 1. Constats de départ (lecture du code)

- **Plantage à « Classer »** (« Sauvegarder » pour le propriétaire). La carte « Vérifie ta note » de l'écran
  Enregistrer reçoit `Binding($model.review)`. Ce lien **force** la valeur : quand « Classer » ou « Annuler » remet
  `review` à `nil`, le champ de texte encore à l'écran relit le lien et l'app s'arrête. La note était déjà
  confirmée : au redémarrage, la reprise du travail en attente la classe. C'est exactement ce que le propriétaire voit.
- **Chat** : aucun écran de chat n'existe dans le code. Il n'a jamais été construit. Il est créé ici, réuni avec
  « Retrouver » : un seul endroit pour interroger sa mémoire.
- La sauvegarde elle-même est sûre : l'audio est écrit au fil de l'eau, la note existe avant la transcription,
  les enregistrements orphelins sont repris, une analyse échouée laisse la note « À classer ».

## 2. Décisions

### 2.1 Plantage
La carte garde sa propre copie du texte (`@State`) et rend le brouillon par ses rappels. Plus aucun lien forcé.
Test de non-régression : un test d'interface ouvre la carte sur l'écran Enregistrer (base inventée), écrit dans le
champ, touche « Classer » et vérifie que l'app tourne toujours et affiche le résultat.

### 2.2 Enregistrement sans confirmation
- « Vérifier avant de classer » passe **désactivé par défaut**. L'option reste dans les Réglages, et la file
  « À vérifier » reste en place pour qui l'active.
- Confirmation discrète : retour haptique de réussite et carte « Enregistré » avec le dossier.
- **Arrêt automatique quand on se tait** (réglage, activé par défaut) : détecteur de silence sur le niveau du micro,
  relatif au bruit ambiant. Il ne s'arrête qu'après au moins 1 s de parole et **4 s** de silence continu : une pause
  pour réfléchir (1 à 3 s) ne coupe pas. Dans un lieu bruyant, il ne coupe pas du tout (arrêt manuel ou 5 min).
- Interruptions (appel), changement d'app, fermeture : comportement existant conservé (l'audio est sauvegardé et
  traité ensuite).

### 2.3 « Retrouver » (et chat)
- Onglet **Retrouver** (rôle « recherche » d'iOS : bouton loupe à part dans la barre d'onglets).
- Conversation : on écrit ou on dicte une question ; Engram répond par une phrase courte **et** les notes trouvées
  (titre, date, dossier), qu'on touche pour les ouvrir avec leur texte d'origine.
- Moteur entièrement **sur l'iPhone** :
  1. Compréhension de la question, déterministe : période (« aujourd'hui », « cette semaine », « il y a quelques
     jours »…), type (tâche, idée, rendez-vous…), intention (lister, résumer, retrouver), mots utiles.
  2. Score de chaque note : mots (insensible aux accents, préfixes, pluriels), sens (plongements de phrases d'Apple),
     mots proches (« voiture » ≈ « auto », dossier « Automobile »), type, période, état (actives d'abord).
  3. Réponse rédigée par l'IA d'Apple **à partir des seules notes trouvées** ; sinon, phrase modèle. Aucune note
     trouvée : « Je ne trouve rien là-dessus dans ta mémoire. »
- **Confidentialité** : la question et les notes ne quittent jamais l'iPhone (ni Gemini ni Groq). La corbeille et les
  dictées pas encore vérifiées sont exclues.

### 2.4 Notes liées
Le détail d'une note montre jusqu'à 3 notes proches (même moteur), seulement au-dessus d'un seuil de ressemblance :
aucun lien inventé.

### 2.5 Rappels
Notifications locales pour les tâches et rendez-vous datés (réglage « Me rappeler mes tâches », activé par défaut) :
à l'heure dite, sinon à 9 h le jour même ; 1 h avant un rendez-vous à heure précise. Autorisation demandée après la
première note datée. Une note « Gardée sur l'iPhone » (secrète) affiche « Rappel Engram » sans son titre sur l'écran
verrouillé. « Fait », corbeille ou date changée : la notification est retirée ou recalculée.

### 2.6 Siri, raccourcis, bouton Action
- « Enregistrer une pensée » : ouvre Engram et lance l'enregistrement (assignable au bouton Action).
- « Noter dans Engram » (texte dicté à Siri) : la note est enregistrée et classée, sans ouvrir l'app.
- « Demander à Engram » : Siri répond avec le même moteur que « Retrouver » ; iPhone déverrouillé exigé.

## 3. Hors de cette version (à valider plus tard)
- Partager une note vers Engram depuis d'autres apps (extension de partage : nouvelle cible et App Group).
- Résumé hebdomadaire automatique.
- Conversation conservée entre deux ouvertures (aujourd'hui : effacée à la fermeture, plus simple et plus discret).

## 4. Vérification
Tests unitaires (compréhension de la question, score, détecteur de silence, rappels), tests d'interface sur
simulateur (plantage, Retrouver, mémoire vide), CI à chaque étape. Rien n'est déclaré vérifié sur l'iPhone sans le
propriétaire.

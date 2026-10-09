# Engram — Liste de vérification sur l'iPhone (P2, P3 et P4)

À faire d'un seul coup, dans l'ordre. Note les **numéros** qui ne marchent pas, avec ce que tu as vu : c'est tout ce dont j'ai besoin pour corriger.
Rien n'est noté « vérifié sur iPhone » tant que tu ne l'as pas confirmé.

Toutes les phrases ci-dessous sont **inventées** : tu peux les dire telles quelles.

## Avant de commencer

- Installe le nouvel IPA avec AltStore : `build/ipa/Engram.ipa`, dans le dossier du projet sur le PC.
- Apple Intelligence doit être activé (Réglages › Apple Intelligence et Siri).
- Mets-toi en Wi-Fi : le modèle Whisper fait 626 Mo, et Large V3 947 Mo.
- **Clés gratuites** (18 ans ou plus, aucune carte de crédit demandée) :
  - **Gemini** : https://aistudio.google.com/apikey. N'associe **jamais** de compte de facturation à ton projet Google : sans facturation, aucun frais n'est possible.
  - **Groq** : https://console.groq.com/keys. Dans https://console.groq.com/settings/data-controls, active « Zero Data Retention » si l'option est proposée.
  - Tu colles toi-même chaque clé dans Engram (étapes 15 et 16). Elle est rangée dans le trousseau de l'iPhone, jamais ailleurs.

## A. Notes, Corbeille, Cerveau (les bugs que tu as signalés)

1. **Notes** : seulement des dossiers qui contiennent quelque chose, chacun avec une courte description ou son nombre de notes. Aucune ligne vide.
2. **Menu « … » en haut des Notes** : Archives, Corbeille, Réglages.
   - Le bouton **« + »** à côté ouvre « Écrire » : la note est classée toute seule.
   - Tes anciennes catégories reçoivent une courte description après une ou deux réouvertures de l'app. Elle est écrite par l'IA d'Apple, sur l'iPhone.
3. **Balayer une note active** : le bouton « Corbeille » est rouge et son icône est visible.
4. **Dans la Corbeille, balayer une note** : « Restaurer » et « Supprimer ». « Supprimer » demande une confirmation.
5. **Corbeille › « Tout supprimer »** (en haut à droite) : confirmation, puis la corbeille est vide.
6. **Après avoir tout supprimé**, l'onglet Cerveau affiche « Ton cerveau est vide », **sans aucun point** derrière.

## B. Transcription Whisper

7. **Onglet Enregistrer** : une carte propose « Télécharger Whisper ».
   - Le téléchargement se fait, puis « Préparation du modèle… » apparaît. Ça peut prendre quelques minutes la première fois : garde l'app ouverte.
   - Ensuite, la carte disparaît.
8. **Dis** : « Faut que je call mon manager demain pour changer mon shift, pis après je vais au gym. »
   - La carte « Vérifie ta note » apparaît.
   - Les mots anglais (call, manager, shift, gym) doivent être écrits tels quels, sans traduction.
9. **Corrige un mot, puis « Classer »** : dans le détail de la note, la section « Source » montre toujours le texte d'origine.
10. **Dicte une note, puis touche « Annuler » sur la carte** : la note va à la Corbeille et n'est pas classée.
11. **Dicte une note, puis ferme l'app sans confirmer** : à la réouverture, Notes › « À vérifier » la contient.
12. **« Réécouter » sur la carte** : l'enregistrement se rejoue.
13. **Mode avion** : dicte une note. Whisper transcrit quand même (il fonctionne sans Internet).
14. **Réglages › Transcription › « Retranscrire mes anciennes notes »** : les vieilles notes mal comprises sont relues par Whisper. Celles que tu as corrigées à la main ne changent pas.

## C. Classement et confidentialité

15. **Réglages › Intelligence › Gemini** : colle ta clé, puis « Enregistrer et tester ». Tu dois voir « Clé valide. Modèles : … ».
16. **Même chose pour Groq**. Tu dois voir « Clé valide ».
17. **Dis** : « Acheter du lait et du pain ».
    - Ouvre la note : « Classée par Gemini », confidentialité « Neutre ».
18. **Dis** : « Je pèse 75 kg ce matin ».
    - Catégorie Santé.
    - « Classée par Groq », confidentialité « Personnelle ».
    - Elle ne doit **jamais** être classée par Gemini.
19. **Dis** : « Rappelle-moi de réserver la salle le 24 novembre, rappelle-moi ça demain ».
    - **Une seule** note, avec demain pour échéance.
    - **Dis aussi** : « Idée de cadeau : un livre de cuisine, rappelle-moi ça samedi ». Une seule note, rangée dans « À faire », pour samedi.
20. **Dis** : « Appeler le garage pour les pneus, pis acheter du lait en revenant ».
    - **Deux** notes, dans deux catégories différentes.
21. **Active « Garder sur l'iPhone » sur la carte**, puis classe la note : elle est « Classée sur l'iPhone ».
22. **Dis** : « Mon code de casier est 4821 » : « Gardée sur l'iPhone » (Secret).
23. **Écris une note au clavier** (bouton Écrire) avec « Garder sur l'iPhone » activé : elle est classée sur l'iPhone.
24. **Réseau coupé** :
    - En mode avion, dicte « Acheter des piles » : la note est classée sur l'iPhone.
    - Remets le réseau, ferme puis rouvre l'app : la note est reclassée par Gemini, si tu n'y as pas touché.
25. **Réglages › Intelligence › « Santé : garder sur l'iPhone »**, puis redis la phrase du poids : elle reste sur l'iPhone.
    - **« Tout garder sur l'iPhone »** : plus rien n'est envoyé. Le détail de chaque note dit « Réglage « Tout garder sur l'iPhone » activé ». Désactive-le ensuite.
26. **Réglages › Intelligence** : la ligne « Ce mois-ci » montre la répartition Gemini · Groq · iPhone, et les analyses du jour.
27. **Réglages › Intelligence › « Évaluer le classement sur l'iPhone »** : lance l'évaluation et note le score (sur 43).

## D. Banc d'essai Whisper (quand tu as 15 minutes)

28. **Réglages › Transcription** : télécharge aussi **Large V3** (947 Mo).
29. **Banc d'essai** : lis les 40 phrases, une à la fois.
30. **« Lancer la comparaison »**, iPhone débranché et app ouverte.
    - Note les erreurs, les mots anglais gardés, la vitesse et la batterie de chaque ligne.
    - Engram ne propose un changement qu'avec assez de preuves : les 40 phrases et au moins 20 notes que tu as corrigées.
    - Rien ne change sans ton accord.

## E. Calendrier et le reste (P3)

31. **Dis** : « Dentiste vendredi à 14 h » : le rendez-vous est ajouté au calendrier de l'iPhone (1 h).
    - **Dis aussi** : « Dentiste mardi à 10 h, rappelle-moi ça lundi ». Une seule note ; le rendez-vous est au calendrier **mardi à 10 h**, pas lundi.
32. **Onglet Calendrier** :
    - le rendez-vous apparaît le bon jour, **une seule fois** (pas en double avec l'événement de l'iPhone) ;
    - un événement de plusieurs jours apparaît chaque jour.
33. **Onglet Cerveau** : les points des catégories et des notes s'affichent. Pince pour zoomer, touche pour ouvrir.
34. **Recherche dans les Notes** : un mot d'une note la retrouve.
35. **Réglages › « Exporter toute ma mémoire »** : un fichier ZIP est créé.

## F. P5 — enregistrer sans y penser, retrouver en demandant

36. **Le plantage** : Réglages › Transcription › active « Vérifier avant de classer », puis dicte « Acheter des piles ».
    - La vérification s'ouvre dans une feuille. Touche le texte : « Classer » reste visible en haut, au-dessus du clavier.
    - Corrige un mot, touche « Classer » : l'app **ne se ferme plus**, et « Enregistré » apparaît.
    - « Plus tard » (ou glisser la feuille vers le bas) : la dictée attend dans Notes › À vérifier.
    - Désactive ensuite l'option : c'est le réglage par défaut.
37. **Sans confirmation** : touche le micro, dis « Faut que je pense à appeler l'assurance pour une réévaluation », puis tais-toi.
    - Après environ 4 s de silence, l'enregistrement s'arrête tout seul (vibration).
    - « Enregistré » et le dossier s'affichent, sans aucun bouton à toucher.
38. **Une pause pour réfléchir** : dis une phrase, attends 2 s, dis-en une autre. L'enregistrement continue ; il s'arrête après le dernier silence.
39. **Deux idées d'un coup** : « Demain, il faut que j'appelle mon garagiste, et j'ai aussi eu une idée pour améliorer la page d'accueil de mon app ». Deux notes, dans deux dossiers.
40. **Retrouver** (loupe en bas à droite) :
    - « Je me rappelle que j'avais quelque chose à faire cette semaine, mais je ne sais plus quoi » : la note de l'assurance apparaît.
    - « C'était quoi l'affaire avec l'assurance ? » : même note, avec la date où tu l'as dite.
    - Touche le micro et pose une question à voix haute : elle s'écrit, puis la réponse arrive.
    - Une question sur un sujet jamais noté : « Je ne trouve rien là-dessus dans ta mémoire. »
    - Touche une note trouvée : son détail s'ouvre, avec le texte d'origine.
41. **Notes liées** : ouvre une note qui parle d'un sujet déjà noté (par exemple deux notes sur le garage) : « Notes liées » les relie.
42. **Rappels** : dis « Rappelle-moi d'arroser les plantes dans 5 minutes »… ou plus simplement « Appeler la banque aujourd'hui à » + une heure dans 10 minutes.
    - Engram demande la permission d'envoyer des notifications (une seule fois).
    - À l'heure dite, la notification arrive ; la toucher ouvre la note.
    - Marque une autre tâche datée « Fait » : son rappel ne vient pas.
43. **Siri** : « Dis Siri, note dans Engram » puis « acheter du café » : Siri répond « C'est noté », la note apparaît classée.
    - « Dis Siri, demande à Engram » puis « qu'est-ce que j'ai à faire aujourd'hui » : Siri répond (iPhone déverrouillé).
44. **Bouton Action** : Réglages de l'iPhone › Bouton Action › Raccourci › Engram › « Enregistrer une pensée ». Un appui : Engram s'ouvre et enregistre déjà.
45. **Détail d'une tâche** : le type et l'échéance s'affichent sous le texte ; « … › Marquer comme fait » la range dans les Archives.

## G. P6 — Cerveau vivant, tâches qui avancent, widgets

46. **Installation** : installe `Engram.ipa` (avec widgets). Si AltStore refuse, installe `Engram-simple.ipa` (sans widgets ni partage) et dis-moi l'erreur affichée.
47. **Cerveau** : les catégories sont des neurones de couleur qui respirent, les notes tournent autour, des signaux passent sur les connexions.
    - Touche une catégorie dans la rangée du haut : le Cerveau la centre et l'agrandit ; touche-la encore pour l'ouvrir.
    - Réglages de l'iPhone › Accessibilité › Mouvement › « Réduire les animations » : tout reste immobile.
48. **Couleurs** : chaque dossier des Notes a la couleur de son neurone ; les résultats de Retrouver aussi.
49. **Rappel avec boutons** : dicte « Rappelle-moi d'arroser les plantes dans 10 minutes ». À la notification, appuie longtemps : « Fait », « Dans 1 h », « Demain ». Essaie « Dans 1 h » : le rappel revient une heure plus tard.
50. **Résumé du matin** : avec une tâche datée de demain, une notification « Aujourd'hui » arrive demain à 8 h. La toucher ouvre « À faire ».
51. **Pastille** : l'icône d'Engram affiche le nombre de choses à faire aujourd'hui ou en retard.
52. **Résumé de la semaine** : dimanche à 18 h, « Ta semaine » ; le toucher ouvre Retrouver avec le résumé.
53. **Widgets** : appui long sur l'écran d'accueil › « + » › Engram : « Aujourd'hui » et « Enregistrer ». Le bouton Enregistrer ouvre Engram qui écoute déjà.
    - Centre de contrôle › « + » › Engram › « Enregistrer une pensée ».
54. **Partager** : dans Safari, Partager › Engram › « Ajouter ». À la réouverture d'Engram, la note est là, classée.
55. **Conversation gardée** : pose une question dans Retrouver, ferme l'app, rouvre-la : la conversation est toujours là ; « Nouvelle recherche » l'efface.

## H. P7 — Sauvegarde chiffrée et Face ID

56. **Réglages › Sauvegarde chiffrée** : choisis un dossier dans iCloud Drive, puis un mot de passe (8 caractères ou plus) que tu notes ailleurs.
57. **« Sauvegarder maintenant »** : un fichier « Engram-Sauvegarde-… » apparaît dans ce dossier (app Fichiers).
58. **Restaurer** (sur une copie de test) : « Restaurer une sauvegarde… », choisis le fichier, entre le mot de passe. Engram dit combien de notes il contient ; ferme l'app et rouvre-la : tes notes sont là, et l'ancien état est gardé.
    - Avec un mauvais mot de passe : « Impossible d'ouvrir cette sauvegarde », rien ne change.
59. **Chaque semaine** : active l'option ; la sauvegarde se refait seule une fois par semaine à l'ouverture d'Engram.
60. **Face ID** : active « Verrouiller avec Face ID ». Quitte l'app et reviens : Face ID est demandé. Dans le sélecteur d'apps, le contenu est masqué. Les widgets n'affichent plus les titres.

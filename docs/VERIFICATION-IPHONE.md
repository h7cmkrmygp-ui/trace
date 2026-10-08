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
  - Tu colles toi-même chaque clé dans Engram (étapes 14 et 15). Elle est rangée dans le trousseau de l'iPhone, jamais ailleurs.

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
32. **Onglet Calendrier** :
    - le rendez-vous apparaît le bon jour, **une seule fois** (pas en double avec l'événement de l'iPhone) ;
    - un événement de plusieurs jours apparaît chaque jour.
33. **Onglet Cerveau** : les points des catégories et des notes s'affichent. Pince pour zoomer, touche pour ouvrir.
34. **Recherche dans les Notes** : un mot d'une note la retrouve.
35. **Réglages › « Exporter toute ma mémoire »** : un fichier ZIP est créé.

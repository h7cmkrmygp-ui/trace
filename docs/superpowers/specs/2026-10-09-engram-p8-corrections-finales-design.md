# Engram P8 — Corrections finales : bruit, franglais, navigation, Cerveau, vraie note

*9 octobre 2026. Demandes du propriétaire après ses essais sur l'iPhone (message « Corrections et améliorations
finales », puis quatre ajouts en cours de route).*

## Ce que le propriétaire a constaté

1. L'arrêt automatique ne marche qu'une fois sur deux avec de la musique, un ventilateur ou des conversations.
2. « Faut que je call mon manager demain pour changer mon shift, pis après je vais au gym. » n'est parfois pas
   transcrit, et rien n'est classé ; il attend deux notes.
3. Notes › Réglages, onglet Cerveau, retour sur Notes : Réglages est encore affiché.
4. Le Cerveau fait « jeu vidéo » : il le veut sobre, élégant, à la Apple, et utile pour retrouver.
5. Il veut savoir si ChatGPT et Claude peuvent lire et écrire dans Engram (MCP).
6. Ajouts : classement plus précis ; fiche d'une note trop encombrée (garder catégorie et notes liées) ; retirer les
   « euh » ; « aujourd'hui » remplacé par la vraie date ; une vraie note comme dans Notes d'Apple.

## Causes trouvées

- **Phrase jetée** : c'était mot pour mot l'amorce donnée à Whisper. Le filtre anti-écho (Whisper recopie parfois
  l'amorce sur un silence) la prenait pour un écho et la jetait : transcription vide, note « À classer ».
- **Rien de classé** parfois : l'IA recopiait l'extrait avec un mot changé (« puis » pour « pis ») ; la règle
  anti-invention rejetait alors la pensée.
- **Arrêt automatique** : le silence était jugé par rapport au bruit de fond le plus bas ; une musique qui varie
  dépassait sans cesse ce seuil.
- **Navigation** : chaque onglet gardait sa pile d'écrans.

## Décisions

- **Voix ou bruit** : le détecteur apprend le niveau de ta voix (tes syllabes les plus fortes) ; ce qui reste 10 dB
  sous ta voix est du silence, même si ça bouge. Un bruit bref (≤ 0,15 s) précédé d'au moins 0,5 s de silence est
  ignoré. Un son fort à l'instant présent retarde toujours l'arrêt. Limite connue : un bruit aussi fort que ta voix
  empêche l'arrêt seul (le bouton reste là).
- **Amorce Whisper** : une phrase que le propriétaire ne dira jamais telle quelle.
- **Hésitations** : retirées de la transcription (« euh », « euhmmm », « hum », « mmm »…, jamais « eu »), avec
  l'élision refaite (« de euh appeler » → « d'appeler »). L'audio reste entier.
- **Extraits presque mot pour mot** : acceptés s'ils retrouvent les trois quarts de leurs mots porteurs de sens dans
  une proposition du texte (ou deux qui se suivent) ; l'extrait devient alors les vrais mots du texte.
- **Consignes des IA (p8)** : un élément par sujet ou action, même dans une seule phrase (« pis après » commence
  souvent un nouvel élément et en hérite la date) ; titres en français clair, l'action d'abord, anglais et joual
  traduits, sans « euh » ni « rappelle-moi de » ; le résumé devient le texte de la note, rédigé comme dans Notes,
  avec « ☐ » pour plusieurs étapes ; sous-catégories durables et précises (Finance › Assurances…) ; jamais
  « aujourd'hui » ni « demain » dans un titre. Le modèle d'Apple reçoit aussi la date du jour.
- **Vraie date** : au classement, « aujourd'hui », « demain », « hier », « ce soir »… du titre et du texte rédigé
  deviennent la date de la dictée (« le 9 octobre », l'année si elle change). Les mots exacts restent dans la note.
- **Navigation** : les piles de chaque onglet vivent dans le modèle de l'app ; quitter un onglet vide la sienne.
- **Vraie note** : titre et texte modifiables sur place, cases à cocher (« ☐ »/« ☑ », Markdown compris),
  enregistrement en quittant un champ (une version de plus). « Ce que tu as dit » replié, pastilles de catégories,
  notes liées. Classement, texte d'origine, versions : dans « Détails ». « Modifier tes mots… » garde l'ancien éditeur.
- **Cerveau** : fond doux, fines connexions, neurones éclairés d'en haut avec une membrane, notes en petits points,
  flottement de quelques points sur 6 à 10 s, apparition en douceur. Toucher un neurone le centre et ouvre un panneau
  de verre avec ses notes récentes ; la recherche y montre les résultats. Titres des notes visibles de près.
  Plus de poussière, de signaux, d'orbites ni de silhouette.
- **MCP** : un serveur MCP en ligne (exigé par Claude et ChatGPT) voudrait dire une copie de la mémoire hors de
  l'iPhone : mis de côté, décision du propriétaire. Partie sûre faite : l'action Raccourcis « Trouver dans Engram pour
  un assistant » (texte des notes trouvées, notes privées exclues, rien si « Tout garder sur l'iPhone », iPhone
  déverrouillé). Détails : `docs/ASSISTANTS-MCP.md`.

## Tests

Paquet (CI) : bruit de fond (musique, ventilateur, voix au loin, coup à la porte, pauses), écho de Whisper,
hésitations, extraits presque mot pour mot, vraie date (titre et texte), cases à cocher, consignes p8, notes privées
marquées et exclues pour un assistant. Interface (simulateur) : retour sur un onglet, recherche dans le Cerveau,
captures de la nouvelle note.

Non testable sans l'iPhone : la qualité réelle des IA sur le franglais, le micro dans un vrai bruit, Face ID, le
raccourci avec ChatGPT.

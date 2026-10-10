# Engram P7 — Sauvegarde chiffrée et verrouillage Face ID

Date : 2026-10-09. Proposé au propriétaire en fin de P6 (« ce que j'ajouterais ensuite », points 1 et 2), lancé pendant
qu'il n'a pas accès à son PC pour tester.

## 1. Sauvegarde automatique chiffrée
- **Contenu** : une copie cohérente de la base (sauvegarde SQLite pendant que l'app tourne) et les enregistrements
  audio. Pas les modèles Whisper (ils se retéléchargent).
- **Chiffrement** : clé tirée du mot de passe du propriétaire (PBKDF2-SHA256, 600 000 tours, sel aléatoire), puis
  AES-GCM par morceaux de 1 Mo. Chaque morceau est lié à son rang et le dernier est marqué : un fichier tronqué,
  modifié ou ouvert avec le mauvais mot de passe est refusé.
- **Format** : fichier `.engrambackup` lisible par Engram seul (pas de ZIP : iOS ne sait pas le décompresser).
- **Où** : un dossier choisi une fois par le propriétaire (iCloud Drive conseillé, ou Fichiers). Accès gardé par un
  signet sécurisé. Les 4 dernières sauvegardes sont gardées, les plus vieilles d'Engram sont effacées.
- **Quand** : « Sauvegarder maintenant », et automatiquement une fois par semaine à l'ouverture de l'app.
- **Mot de passe** : choisi par le propriétaire, gardé dans le trousseau de l'iPhone (pour les sauvegardes
  automatiques). Oublié : la copie ne peut plus être ouverte, personne ne peut l'ouvrir — Engram le dit clairement.
- **Restaurer** : choisir un fichier, entrer le mot de passe ; la copie est vérifiée, préparée, puis appliquée au
  prochain lancement. Les données actuelles sont **mises de côté** (dossier « Avant-restauration »), jamais effacées.

## 2. Verrouillage Face ID
- Réglage « Verrouiller avec Face ID » (désactivé par défaut) ; l'activer demande une première authentification.
- Au retour dans l'app, un écran verrouillé demande Face ID (ou le code de l'iPhone). Dans le sélecteur d'apps, le
  contenu est masqué.
- Verrou actif : widgets et notifications n'affichent plus les titres (« Rappel privé », « Rappel Engram »).
- Les raccourcis Siri gardent leurs règles (« Demander à Engram » exige déjà l'iPhone déverrouillé).

## 3. Vérification
Tests unitaires : aller-retour chiffré, mauvais mot de passe, fichier tronqué ou modifié, copie de la base,
restauration qui garde les anciennes données. Face ID ne se teste que sur l'iPhone.

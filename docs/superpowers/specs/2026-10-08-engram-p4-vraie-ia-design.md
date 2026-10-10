# Engram P4 — « Vraie IA » : Whisper sur l'iPhone, Gemini pour classer, Notes simplifiées

Statut : **approuvé le 2026-10-08, avec les corrections de la section 11**, qui priment sur tout ce qui les contredit plus haut.

## 1. Ce que le propriétaire a demandé

- Une transcription aussi proche que possible de celle de ChatGPT, **sans frais d'API** : WhisperKit avec un grand modèle Whisper multilingue, exécuté sur l'iPhone.
- Garder fidèlement les mots prononcés : français québécois, anglicismes, phrases bilingues. Ne jamais traduire. Améliorer la ponctuation sans reformuler. Pouvoir vérifier et corriger la transcription avant le classement.
- **Google Gemini API, version gratuite**, comme IA principale pour comprendre et classer. Les modèles d'Apple restent le secours hors ligne.
- Gemini doit comprendre l'intention, trouver les bonnes catégories, extraire les tâches, dates et rappels, éviter les classements absurdes, ne pas découper une pensée au hasard, garder le texte original, et ne pas recevoir tout l'historique à chaque analyse.
- 0 $ de frais d'API, comportement prévu quand le quota gratuit est atteint, aucun service facturable activé.
- Dépôt public : aucune clé, aucune donnée personnelle, rien dans l'historique Git, dans l'app distribuée ou dans les journaux.
- Notes plus simples, comme la capture SecondBrain : seulement des dossiers qui contiennent quelque chose, chacun avec une courte description.
- Corbeille : supprimer d'un geste et « Tout supprimer ». Le bouton Corbeille n'a plus d'icône.
- Cerveau : le message « Ton cerveau est vide » se superpose à des points de notes supprimées.
- Ne supprimer aucune fonctionnalité existante.

## 2. Analyse de l'existant

| Sujet | Aujourd'hui | Conséquence |
|---|---|---|
| Transcription | `FileTranscriber` : moteur d'Apple récent (`SpeechAnalyzer` / `SpeechTranscriber`), **verrouillé sur une seule langue** (fr-CA). Ce n'est ni Whisper ni l'ancienne dictée, mais il ne gère pas le mélange des langues. | Les mots anglais et l'accent sont mal compris. |
| Format audio | CAF PCM 16 kHz mono, écrit au fil de l'eau. | Déjà le format natif de Whisper : aucun changement. |
| Analyse | `AppleThoughtAnalyzer` : petit modèle d'Apple sur l'iPhone. Ses consignes disent « une seule phrase peut contenir plusieurs pensées ». | Il **découpe trop** : une phrase devient deux notes, une pesée part en « Rendez-vous » et en « Finance ». |
| Garde-fous | `AnalysisValidator` : chaque extrait doit exister mot pour mot dans le texte, et chaque date mentionnée aussi. `DateResolver` calcule les dates de façon déterministe. | À garder tels quels : ils protègent contre l'invention, quelle que soit l'IA. |
| Branchement | Protocole `MemoryAnalyzer`, `ThoughtProcessor` (une analyse à la fois par note, nouvel essai, « occupé » → en attente), `ThoughtFiler` (ne remplace jamais une note touchée par le propriétaire). | Gemini se branche comme un nouvel analyseur, sans toucher au reste du pipeline. |
| Catégories | `EngramCategory` a déjà un champ `description`. L'IA crée catégories et sous-catégories. | Les descriptions peuvent venir de l'IA, sans changer le schéma. |
| Cerveau et Notes | `brainSnapshot` et `librarySummary` renvoient **toutes** les catégories actives, même vides. | Cause des deux bugs : catégories vides affichées, points visibles sous « Ton cerveau est vide ». |
| Corbeille | `MemorySwipeActions` ne propose que « Restaurer » pour une note supprimée. La couleur de l'app est `.primary` (blanc en mode sombre). | Pas de suppression d'un geste. Le bouton rouge devient blanc et son icône blanche disparaît (hypothèse à confirmer sur l'iPhone). |
| Données | Tout est sur l'iPhone (SQLite). Il n'y a **ni serveur, ni compte, ni autre utilisateur**. | Le cloisonnement des comptes côté serveur n'a pas d'objet tant qu'Engram reste personnel. |

## 3. Faisabilité (vérifiée le 2026-10-08)

**WhisperKit 1.1.0** (publié le 2026-08-06). La table officielle d'Argmax des modèles pris en charge sur la puce **A19 (iPhone 17)** inclut :

| Modèle | Taille | Caractère |
|---|---|---|
| `openai_whisper-large-v3_947MB` | 947 Mo | Whisper Large V3 complet (décodeur de 32 couches) : le plus précis, plus lent. |
| `openai_whisper-large-v3-v20240930_626MB` | 626 Mo | Whisper Large V3 Turbo d'OpenAI (décodeur de 4 couches) : plusieurs fois plus rapide, précision proche. |

Les versions non compressées (environ 3 Go) ne sont pas proposées sur iPhone. Le modèle est téléchargé une seule fois depuis Hugging Face (gratuit), puis tout fonctionne hors ligne. Ce n'est pas un modèle trop petit : ce sont les plus grands modèles Whisper qui tournent sur un iPhone.

**Gemini API, version gratuite.**
- Sans compte de facturation, le projet reste au palier gratuit : **aucun frais n'est possible**. Le palier payant exige d'associer soi-même un compte de facturation dans AI Studio. Engram ne le fera jamais et ne le demandera jamais.
- Modèles stables avec palier gratuit : famille `gemini-3.x-flash` et `gemini-3.x-flash-lite`. Les identifiants exacts sont vérifiés à la mise en œuvre et testés par l'app avec la liste des modèles.
- **Quotas** : Google ne les publie plus dans sa documentation. Ils sont **par projet** et visibles dans AI Studio. Les blogues de 2026 se contredisent (de 20 à 1 500 requêtes par jour pour Flash). On conçoit donc pour un quota bas : **une seule requête par note**, sans historique. Le quota quotidien se réinitialise à minuit, heure du Pacifique (3 h au Québec). Un dépassement renvoie une erreur 429.
- **Point important des conditions** (mises à jour le 2026-04-28) : en version gratuite, Google utilise le contenu pour améliorer ses produits, et des évaluateurs humains peuvent le lire (détaché du compte). Le propriétaire l'a accepté. **Mais les conditions disent aussi de ne pas envoyer d'informations sensibles, confidentielles ou personnelles aux services gratuits**, et exigent d'avoir 18 ans ou plus. Un « deuxième cerveau » contient par nature des informations personnelles. Ce point demande une décision explicite du propriétaire (voir la section 9).

## 4. Transcription (Phase B)

- **Moteurs** : Whisper (par défaut), puis Apple en secours (modèle Whisper pas encore téléchargé, ou erreur). L'option OpenAI préparée plus tôt est **retirée** (elle était payante) avec ses tests.
- **Modèles** : Réglages › Transcription propose Large V3 Turbo (626 Mo, par défaut) et Large V3 (947 Mo). Le téléchargement se fait en Wi-Fi, avec une barre de progression. Le modèle va dans Application Support, exclu de la sauvegarde iCloud.
- **Banc d'essai** sur l'iPhone : on choisit des enregistrements récents, on les transcrit avec les deux modèles et on affiche, côte à côte, le texte, la durée de calcul, la vitesse (× temps réel) et la batterie utilisée. Le propriétaire choisit ensuite son modèle. Je n'ai pas d'iPhone : ces mesures ne peuvent être faites que par le propriétaire.
- **Fidélité** :
  - tâche `transcribe` uniquement, jamais `translate` ;
  - langue : Whisper détecte d'abord la langue. On n'utilise l'anglais que si la note est nettement en anglais, sinon le français. Avec le français imposé, Whisper garde les anglicismes tels quels (« call », « shift », « gym »). La détection libre risque de basculer en anglais et de traduire le français ;
  - une courte phrase d'amorce (`promptTokens`), dans le style du propriétaire, bilingue et ponctuée, oriente Whisper vers la ponctuation et le vocabulaire québécois sans reformuler. Exemple de référence : « Faut que je call mon manager demain pour changer mon shift, pis après je vais au gym. » ;
  - température 0, avec les replis prévus par WhisperKit, et découpage par détection de la voix pour les notes longues (5 min maximum).
- **Vérifier avant de classer** : après la transcription, une carte « Vérifie ta note » affiche le texte modifiable, avec Classer, Réécouter et Annuler.
  - Le texte original est toujours conservé (`originalText`), la correction est enregistrée à part (`correctedText`).
  - Réglage « Classer sans vérifier » pour passer cette étape.
  - Si l'app se ferme avant la confirmation, la note reste « À vérifier ». L'audio et le texte sont déjà sauvegardés : rien n'est perdu.
- **Retranscrire** : sur une note vocale (et « Tout retranscrire » dans Réglages), Whisper relit l'audio d'origine. Les notes que le propriétaire a modifiées ne sont jamais remplacées. Le stockage est déjà prêt : `retranscribe` et `voiceSources`.
- **Limite connue** : iOS limite le calcul en arrière-plan. La transcription se fait app ouverte. Si l'app passe en arrière-plan, elle reprend à la réouverture.

## 5. Classement avec Gemini (Phase C)

- **Appel** : HTTPS direct de l'iPhone vers `generativelanguage.googleapis.com`, en sortie JSON imposée par un schéma. La clé passe dans l'en-tête `x-goog-api-key`, jamais dans l'adresse.
- **Ce qui est envoyé, et seulement ça** :
  - le texte de **la** note à classer ;
  - la date et le fuseau du jour ;
  - la liste des noms de catégories existantes, avec leur description courte.

  Jamais l'historique des souvenirs. Jamais l'audio : il reste sur l'iPhone.
- **Masquage automatique avant l'envoi** : courriels, numéros de téléphone et longues suites de chiffres (carte, NAS, compte) sont remplacés par des marqueurs, puis remis à leur place au retour.
- **Interrupteur « Garder sur l'iPhone »** sur la carte de vérification : la note est alors classée par Apple uniquement.
- **Réponse attendue** : des notes, chacune avec titre, résumé, extrait mot pour mot, type, catégorie (nom, plus une description courte si elle est nouvelle), sous-catégorie facultative, étiquettes, et dates (expression exacte, date ISO, avec ou sans heure, rôle rappel / événement / échéance).
- **Consignes**, avec des exemples génériques dans la consigne :
  - une note par sujet distinct ;
  - un rappel qui parle de la même chose reste dans la même note (« rappelle-moi d'appeler le garage vendredi, rappelle-moi ça demain » donne une seule tâche, rappel demain) ;
  - ne jamais couper une phrase qui parle d'un seul sujet ;
  - les catégories sont des domaines de vie larges, on réutilise l'existant ;
  - une mesure du corps va en Santé (« je pèse 75 kg » : Santé, info, pas Finance, pas Rendez-vous) ;
  - on garde les mots du propriétaire.
- **Garde-fous inchangés** : le validateur rejette tout extrait ou toute date absents du texte, `DateResolver` recalcule les dates et prime en cas de désaccord, et la couverture minimale reste exigée (sinon la note intérimaire est gardée).
- **Quota et pannes** :
  - erreur 429 sur Flash : nouvel essai sur Flash-Lite, qui a son propre quota ;
  - encore 429, ou pas de réseau : Apple classe tout de suite, et la note est marquée « classée hors ligne ». Dès que le réseau ou le quota revient, Gemini reclasse ces notes **si le propriétaire ne les a pas touchées** ;
  - un compteur local d'analyses du jour est affiché dans Réglages, par exemple « 12 aujourd'hui · quota gratuit atteint, reprise à 3 h ».
- **Réglages › Intelligence** :
  - champ « Clé Gemini », que le propriétaire colle lui-même, enregistrée dans le trousseau (`ThisDeviceOnly`) ;
  - bouton « Tester la clé » (liste des modèles) ;
  - choix Gemini ou Apple seulement ;
  - lien vers AI Studio pour voir le quota exact.
- **Apple en secours, moins bête** : nouvelles consignes (version `p4-v1`). On retire « une phrase peut contenir plusieurs pensées », et on ajoute les mêmes règles et exemples que pour Gemini.

## 6. Notes, Cerveau, Corbeille (Phase A, d'abord)

- **Notes**, comme la capture :
  - recherche, puis des cartes-dossiers (icône, nom, description) pour les catégories qui contiennent au moins une note ;
  - les catégories vides sont masquées (pas supprimées) ;
  - « À faire » et « À classer » deviennent des cartes en tête, seulement si elles ne sont pas vides ;
  - Archives, Corbeille et Réglages passent dans un menu en haut. Rien n'est supprimé, tout est rangé.
- **Dans une catégorie** : la liste des notes. Les sous-catégories éventuelles apparaissent comme de petits intertitres.
- **Cerveau** : seulement les catégories qui contiennent une note (et leurs parents). L'état vide redevient cohérent.
- **Corbeille** :
  - balayer donne « Restaurer » et « Supprimer » (rouge, avec confirmation) ;
  - bouton « Tout supprimer » avec confirmation ;
  - boutons destructifs explicitement rouges, avec icône visible.

## 7. Confidentialité et sécurité

- **Aucune clé dans le code, Git, l'IPA ou la CI.** La clé n'existe que dans le trousseau de l'iPhone du propriétaire. L'IPA construite par GitHub n'en contient aucune. gitleaks bloque déjà les clés Google dans la CI.
- **Aucune note dans les journaux.** Aucun `print` ni journal du contenu des notes ou des réponses de Gemini. Les messages d'erreur affichés ne contiennent jamais la clé. Les tests n'utilisent que des textes inventés.
- **Serveur intermédiaire : recommandé non pour Engram personnel.**
  - Engram n'a ni serveur, ni comptes, ni autre utilisateur : les notes ne vivent que sur l'iPhone.
  - Un relais (par exemple un Worker Cloudflare gratuit) devrait lui-même être protégé par un secret rangé dans l'app : le problème du secret sur l'iPhone ne disparaît pas.
  - Le relais ajouterait un endroit de plus par où passent les notes (et ses journaux), plus de la maintenance.
  - Si un jour Engram est partagé avec d'autres personnes, un relais avec comptes isolés deviendra nécessaire. Ce serait alors un projet à part.

## 8. Ordre de réalisation et tests

1. **Phase A** — Notes, Cerveau, Corbeille. Tests du stockage : catégories vides exclues, vidage de la corbeille.
2. **Phase B** — Whisper, banc d'essai, vérification avant classement, retranscription. Tests : choix de la langue, assemblage du texte, états « À vérifier », non-remplacement des notes touchées.
3. **Phase C** — Gemini et consignes d'Apple. Tests sans réseau :
   - construction de la requête : contenu envoyé, absence d'historique, clé dans l'en-tête ;
   - lecture des réponses et des erreurs (429, 400, 403, 5xx) ;
   - masquage et démasquage ;
   - enchaînement Flash, Flash-Lite, Apple ;
   - reclassement après retour du quota.
4. CI verte, IPA, puis une liste de vérification unique pour l'iPhone. Elle comprend le banc d'essai, des phrases bilingues de référence, le quota et le mode avion.

## 9. Décisions demandées au propriétaire (première version)

1. Conditions de Gemini gratuit.
2. Serveur intermédiaire.
3. Modèle Whisper par défaut.
4. Ordre A → B → C.

## 10. Décisions du propriétaire et révision du plan

Elles remplacent ce qui les contredit plus haut (en particulier les sections 5 et 7).

### 10.1 Confidentialité : rien de personnel n'est envoyé à Gemini gratuit

Le propriétaire veut respecter la clause de Google : aucune information personnelle, sensible ou confidentielle n'est envoyée au service gratuit. Le masquage seul ne suffit pas, et le doute se traite **sur l'iPhone**. La section 5 change donc ainsi.

- **Contrôleur de confidentialité local**, avant tout envoi. Une note n'est envoyée à Gemini que si **toutes** les couches la déclarent sans information personnelle :
  1. **Choix du propriétaire.** Interrupteur « Garder sur l'iPhone » sur la carte de vérification, et réglage global « Tout garder sur l'iPhone ».
  2. **Détecteurs déterministes**, sur l'iPhone :
     - courriels, téléphones, adresses et liens (`NSDataDetector`) ;
     - codes postaux ;
     - numéros de carte (contrôle de Luhn), NAS, comptes bancaires et IBAN ;
     - mots de passe, NIP, codes ;
     - montants d'argent ;
     - noms de personnes, de lieux et d'organisations (`NLTagger`, qui prend en charge le français).
  3. **Lexique** français et anglais des domaines sensibles : santé et corps (poids, mesures, médicaments, médecin…), argent personnel, travail (employeur, salaire, congés, collègues), famille et relations, juridique, identité, opinions, religion, orientation.
  4. **Jugement du modèle d'Apple** sur l'iPhone, en sortie guidée : `nonPersonnel`, `personnel` ou `incertain`, avec le motif.
- **Règle** :
  - seule une note qu'aucune couche ne signale et que le modèle d'Apple juge `nonPersonnel` part chez Gemini ;
  - `incertain`, une erreur ou un modèle d'Apple indisponible donnent toujours un **traitement local** ;
  - la liste des catégories envoyée à Gemini passe par le même filtre, et une catégorie dont le nom est personnel n'est jamais envoyée.
- **Le masquage de la section 5 est retiré.** Une note qui contient un numéro reste sur l'iPhone, elle n'est pas masquée puis envoyée.
- **Transparence** : chaque note indique où elle a été classée (« Gemini » ou « sur l'iPhone ») et pourquoi. Réglages › Intelligence montre la proportion du mois.
- **Conséquence assumée** : dans un deuxième cerveau, une grande partie des notes seront personnelles et resteront sur l'iPhone. Gemini traitera les notes neutres (achats courants, idées, tâches de maison, films…). L'amélioration du classement d'Apple (nouvelles consignes `p4-v1`, exemples, règles) n'est donc pas un simple secours : c'est elle qui classera la majorité des notes.
- **Textes originaux** : la transcription d'origine (`originalText`) et l'audio restent intégralement sur l'iPhone. Aucun remplacement : les corrections et les retranscriptions sont rangées à part.

### 10.2 Architecture : aucun serveur à construire ni à payer

**Pour Engram personnel (maintenant)** :
- clé Gemini collée par le propriétaire dans Réglages, rangée dans le trousseau (`ThisDeviceOnly`) ;
- appel HTTPS direct, clé dans l'en-tête ;
- rien dans le code, Git, la CI ni l'IPA. L'IPA construite par GitHub est téléchargeable par tout utilisateur connecté de GitHub : elle ne doit jamais rien contenir de secret.

**Pour une version distribuée : étude de Firebase AI Logic + App Check + Gemini Developer API (forfait Spark), vérifiée le 2026-10-08.**

| Point | Constat |
|---|---|
| Spark gratuit | Oui : Firebase AI Logic est gratuit, et la Gemini Developer API au palier gratuit ne demande aucun compte de facturation (le projet reste sur Spark). Le palier payant exige d'associer soi-même un compte de facturation. |
| SDK | Bibliothèque `FirebaseAILogic` (dépôt `firebase-ios-sdk`, v12.5.0 ou plus), iOS 15 ou plus, Xcode 26.2 ou plus : compatible avec Engram (iOS 27, Xcode 27). Plus besoin de clé Gemini dans l'app. Il faut en revanche le fichier de configuration Firebase, qui contient une clé de projet Firebase (non secrète par conception, protégée par App Check). |
| App Check | Indispensable. Depuis juillet 2026, la console l'active d'office pour AI Logic. Fournisseurs Apple de production : **App Attest**, DeviceCheck, reCAPTCHA Enterprise. |
| **Blocage** | App Attest et DeviceCheck se configurent avec une équipe de développeur Apple. Avec AltStore et un Apple ID gratuit, aucune source fiable ne confirme qu'App Attest fonctionne, et AltStore ne signe qu'un petit ensemble d'autorisations (à confirmer par un essai réel). reCAPTCHA Enterprise demande la facturation Google Cloud (Blaze). Le fournisseur « debug » est réservé au développement : son jeton serait un secret dans l'app. Sans App Check, la configuration Firebase extraite de l'IPA publique permettrait à n'importe qui d'utiliser le quota du projet. |
| Journaux | « AI monitoring » est **facultatif et désactivé par défaut**. Activé, il enregistre les prompts et les réponses complets dans Cloud Logging. On ne l'active jamais, et on ajoute en plus le filtre d'exclusion `resource.type="firebasevertexai.googleapis.com/Model"` sur le collecteur `_Default`. |
| Données | Au palier gratuit, ce sont les conditions des services non payants de Gemini qui s'appliquent : la règle 10.1 reste nécessaire. |

**Conclusion** : Firebase AI Logic est la bonne voie pour une future version distribuée, **le jour où Engram aura un compte Apple Developer payant** (App Attest fiable, distribution TestFlight). Avec AltStore et un Apple ID gratuit, il serait **moins** sûr que la clé dans le trousseau. Rien de Firebase n'est donc ajouté maintenant.

Pour garder la porte ouverte, Gemini est branché derrière le protocole `MemoryAnalyzer`. Un futur `FirebaseThoughtAnalyzer` remplacera l'appel direct sans toucher au reste.

Si Firebase est ajouté un jour, son fichier de configuration sera injecté par un secret GitHub au moment de la construction, et exclu du dépôt par `.gitignore`.

**Vérification du dépôt public** (historique complet, le 2026-10-08) :
- 48 commits, tous avec l'identité `noreply` ;
- aucune clé, aucun jeton, aucun fichier de configuration, aucune image, aucun audio ;
- gitleaks analyse déjà tout l'historique à chaque CI ;
- **à corriger** : des exemples tirés de la vie réelle du propriétaire (des phrases sur les feux de sa voiture et sur une demande de congé) apparaissent dans les tests, le jeu d'évaluation et les documents. Ils n'identifient personne, mais la règle 1 du dépôt exige des données fictives et neutres. Ils seront remplacés par des exemples inventés dans les fichiers actuels.
- **Réécrire l'historique** pour les effacer des anciens commits demanderait une poussée forcée sur GitHub : c'est une décision séparée du propriétaire.

### 10.3 Transcription : Turbo par défaut, Large V3 si nettement plus précis

- **Par défaut** : Whisper Large V3 Turbo (626 Mo).
- **Comparaison sur de vrais enregistrements, sur l'iPhone uniquement** : les enregistrements ne quittent jamais l'appareil, donc la comparaison ne peut pas se faire dans la CI.
  - **Référence** : la transcription corrigée par le propriétaire (carte « Vérifie ta note »), ou une référence tapée dans le banc d'essai.
  - **Mesures** pour chaque modèle :
    - taux d'erreur sur les mots (WER), avec la casse et la ponctuation ignorées et les accents conservés ;
    - durée de calcul divisée par la durée de l'audio ;
    - batterie et état thermique pendant la série ;
    - réussite du chargement (mémoire).
- **Règle de décision** :
  - **Conditions pour passer à Large V3** :
    - il est nettement plus précis : au moins 2 points de WER de moins **et** au moins 15 % d'erreurs en moins, sur au moins 10 enregistrements ou 5 minutes d'audio ;
    - l'appareil le fait fonctionner correctement : il figure dans la table officielle des modèles pris en charge pour la puce, il se charge sans erreur de mémoire, et il transcrit en au plus 1 × temps réel sans surchauffe sérieuse.
  - Le basculement est **automatique**, avec un message qui l'explique, et le propriétaire peut revenir en arrière.
  - Sinon, Turbo reste.
- **Fidélité** : inchangée par rapport à la section 4 (jamais `translate`, français sauf note nettement en anglais, amorce de style). Aucune « correction » par une IA après Whisper : seule la ponctuation produite par Whisper lui-même est gardée.

### 10.4 Classement, budget et ordre

- **Gemini** reçoit la note entière, et ses consignes exigent de comprendre le sens et non des mots-clés. Le reste de la section 5 tient : une note par sujet, pas de découpage arbitraire, validation des extraits et des dates, et Apple en secours hors ligne.
- **Budget 0 $** : quota atteint, réseau absent ou erreur, et la note est classée sur l'iPhone. Aucune facturation n'est jamais activée ni demandée.
- **Ordre** : A (Notes, Cerveau, Corbeille et remplacement des exemples réels), puis B (Whisper), puis C (contrôleur de confidentialité, Gemini, nouvelles consignes d'Apple). Aucune fonctionnalité existante n'est retirée. Seule l'option de transcription OpenAI, jamais livrée et payante, est abandonnée.

## 11. Corrections du propriétaire (accord de départ, 2026-10-08)

### 11.1 Trois niveaux de confidentialité et un deuxième service en ligne : Groq

Le propriétaire ne veut pas qu'Engram repose surtout sur l'IA locale. Recherche du 2026-10-08 sur les services en ligne gratuits aux meilleures conditions :

| Service | Gratuit | Entraînement sur les notes | Conservation | Infos personnelles |
|---|---|---|---|---|
| Gemini API, palier gratuit | oui | **oui**, avec des évaluateurs humains | — | **interdites** par les conditions |
| **Groq**, forfait gratuit, sans carte | `openai/gpt-oss-120b`, environ 30 req./min et 1 000 req./jour selon des sources tierces (le vrai quota s'affiche dans la console) | **non** : le contrat interdit à Groq d'entraîner un modèle avec les entrées ou les sorties (section 4.2) | rien par défaut ; jusqu'à 30 jours seulement en cas d'incident ou d'abus ; option « Zero Data Retention » | permises (accord de traitement des données), sauf les « PHI » du droit américain (données des cliniques et des assureurs). Avoir 18 ans ou plus |
| Cloudflare Workers AI, gratuit | 10 000 « neurones » par jour, soit environ 80 notes | non | non précisé | non restreintes |
| Mistral, palier gratuit | oui | sources contradictoires | — | — |
| GitHub Models | probablement retiré | — | — | — |

**Choix** : Groq devient le service des notes **personnelles**. Gemini garde les notes **neutres**, comme décidé. Cloudflare reste une solution de rechange documentée, non codée.

**Routage par niveau :**
1. **Neutre → Gemini.**
   - Il faut à la fois : aucun détecteur déclenché, aucun mot du lexique, **et** un jugement `neutre` du modèle d'Apple, avec une confiance élevée.
   - Les mots-clés ne peuvent **jamais** déclarer une note neutre. Ils ne servent qu'à la faire monter d'un niveau.
2. **Personnel → Groq.** Tout le reste, sauf le niveau 3. Le doute entre neutre et personnel donne « personnel ».
3. **Secret → iPhone seulement** :
   - interrupteur « Garder sur l'iPhone » ;
   - mots de passe, NIP et codes ;
   - numéros de carte, de compte et de NAS ;
   - pièces d'identité ;
   - jugement `secret` du modèle d'Apple ;
   - doute entre personnel et secret.

   Réglage « Santé : garder sur l'iPhone », désactivé par défaut. À mon avis, les notes de santé d'un particulier ne sont pas des « PHI » au sens de la loi américaine, mais le propriétaire peut les garder locales.

**Si un service manque** : sans clé, sans réseau, ou quota atteint.
- Neutre : Gemini, puis Groq, puis l'iPhone.
- Personnel : Groq, puis l'iPhone.
- Une note classée sur l'iPhone faute de service est reclassée plus tard par le bon service, si le propriétaire ne l'a pas touchée.
- **Jamais** une note personnelle ne passe chez Gemini.

**Clés :**
- deux champs dans Réglages › Intelligence : Gemini et Groq ;
- les clés sont collées par le propriétaire et rangées dans le trousseau ;
- bouton « Tester » pour chacune ;
- lien vers la console Groq pour activer « Zero Data Retention ».

**Qualité du classement local** (notes secrètes et secours) :
- consignes `p4-v1` ;
- exemples ;
- règles de fusion des rappels ;
- suggestion de catégorie d'après les notes semblables déjà classées, par proximité de sens calculée sur l'iPhone (`NLEmbedding`). Aucune donnée ne quitte l'iPhone.

### 11.2 Firebase App Check en mode développement

- Le fournisseur « debug » ne dépend pas de l'attestation d'Apple. Il peut donc fonctionner sous AltStore avec un Apple ID gratuit.
- Le jeton de développement est créé sur l'iPhone. Normalement, on le lit dans la console de Xcode. Sans Mac, Engram devrait l'afficher lui-même pour qu'on l'enregistre dans la console Firebase : à vérifier dans le SDK au moment voulu.
- Ce jeton est un secret qui ouvre l'accès. Il ne doit jamais être dans l'IPA ni sur GitHub.
- Côté sécurité, c'est l'équivalent de la clé dans le trousseau, sans gain réel pour un usage personnel.
- **Conclusion** : faisable, non prioritaire, non codé pour l'instant.

### 11.3 Whisper multilingue et validation stricte

- **Turbo reste le défaut. Le français n'est plus imposé.**
- **Stratégie bilingue**, appliquée à chaque morceau de parole découpé par détection de la voix :
  1. Whisper mesure la probabilité de chaque langue, limitée au français et à l'anglais.
  2. Si une langue domine nettement (au moins 0,85), on décode dans cette langue.
  3. Sinon (phrase mélangée), on décode **deux fois** (français et anglais) et on garde l'hypothèse la plus probable pour le modèle (log-probabilité moyenne).
  4. Dans tous les cas :
     - une amorce bilingue, écrite à la façon du propriétaire, incite Whisper à garder les mots anglais tels quels ;
     - la tâche est toujours `transcribe`, jamais `translate`.
- **Jeu d'essai représentatif** : une quarantaine de phrases fictives et neutres, lues à voix haute par le propriétaire dans l'app. Les enregistrements restent sur l'iPhone. Le jeu couvre :
  - du français québécois pur et de l'anglais pur ;
  - des changements de langue au milieu d'une phrase ;
  - des verbes anglais conjugués en français (« checker », « booker ») ;
  - des nombres, dates et heures ;
  - des noms de marques ;
  - un débit rapide.
- **Comparaison** :
  - Turbo et Large V3, chacun avec trois stratégies : français imposé, détection libre, stratégie bilingue ;
  - mesures : WER, taux de mots anglais perdus ou traduits, vitesse, batterie.
- **Validation** : aucun changement automatique.
  - Engram ne **propose** Large V3 que si toutes ces conditions sont réunies :
    - tout le jeu d'essai a été lu ;
    - au moins 20 notes réelles ont été corrigées par le propriétaire ;
    - Large V3 fait au moins 2 points et 15 % d'erreurs en moins, avec une marge de confiance qui exclut l'égalité (rééchantillonnage apparié à 95 %) ;
    - la vitesse et la température sont correctes.
  - Le propriétaire valide lui-même le changement.
  - La même règle s'applique au choix de la stratégie.

### 11.4 GitHub

- Les exemples réels sont remplacés par des exemples fictifs dans les fichiers actuels.
- **Aucune réécriture de l'historique, aucune poussée forcée.**

### 11.5 Vérification sur l'iPhone

- Je ne peux pas tester sur l'iPhone. Chaque phase se termine par une IPA et une liste de vérification : transcription, classement et confidentialité, dont le routage visible sur chaque note.
- Rien n'est noté « testé sur iPhone » sans la confirmation du propriétaire.

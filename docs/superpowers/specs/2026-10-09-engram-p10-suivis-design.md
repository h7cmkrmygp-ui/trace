# Engram P10 — Les suivis : poids, sommeil, tension… avec graphiques

*9 octobre 2026. Suite de la demande « passe à l'étape la plus longue… la plus compliquée ». Le propriétaire note
déjà son poids à voix haute (« Je pèse 162,5 livres aujourd'hui ») : Engram en fait des courbes.*

## But

Quand une note contient une mesure, Engram la reconnaît **sur l'iPhone** (aucune IA, aucun envoi) et l'ajoute à un
suivi : un graphique dans le temps, la dernière valeur, l'évolution sur 30 jours, le minimum, le maximum et la moyenne.

## Mesures reconnues

| Suivi | Exemples | Unité | Valeurs plausibles |
|---|---|---|---|
| Poids | « je pèse 162,5 livres », « poids 75 kg », « I weigh 160 lbs » | lb ou kg | 35–250 kg (77–550 lb) |
| Sommeil | « j'ai dormi 7 h 30 », « dormi 7 heures et demie », « 6 h de sommeil », « slept 8 hours » | heures | 0,5–16 h |
| Tension | « tension 120 sur 80 », « pression 118/76 », « blood pressure 120 over 80 » | mmHg | 70–250 sur 40–150 |
| Pouls | « pouls 62 », « fréquence cardiaque 70 », « 64 bpm » | bpm | 30–220 |
| Pas | « 8 000 pas », « 10k pas », « 12000 steps » | pas | 100–100 000 |
| Glycémie | « glycémie 5,6 », « taux de sucre à 6,1 » | mmol/L | 2–30 |

- Nombres à virgule ou à point (« 162,5 », « 162.5 »), milliers avec espace (« 8 000 »).
- Le poids exige le contexte (« pèse », « poids », « pesée », « balance », « weigh ») : « 2 livres de bœuf » n'est
  pas un poids. Tension, pouls et glycémie exigent leur mot. Une valeur hors des limites plausibles est ignorée.
- Plusieurs mesures dans une note : toutes gardées (« J'ai dormi 7 h et je pèse 162 livres »).
- **Date** : celle de la note ; « hier » la recule d'un jour, « avant-hier » de deux.

## Données

Migration `v6_measurements` : table `measurement` (id, memory_id → note, suppression en cascade, metric, value,
second_value pour la tension, unit, measured_at, created_at). Une note à la corbeille sort des graphiques ; supprimée
pour de bon, ses mesures disparaissent. L'export JSON contient les mesures.

Les mesures sont relevées au classement d'une note, et au lancement de l'app pour les notes qui n'en ont pas encore
été relues (et celles modifiées depuis) : les anciennes notes sont donc couvertes sans bouton.

## Écrans

- **Notes** : un dossier « Suivis » (s'il y a des mesures), avec les dernières valeurs.
- **Suivis** : une carte par suivi (icône, nom, dernière valeur en grand, petite courbe, évolution sur 30 jours).
- **Un suivi** : graphique (Mois, 3 mois, Année, Tout), minimum, maximum et moyenne, puis chaque mesure avec sa note.
  Le poids s'affiche en livres ou en kilos (choix gardé).
- **Une note** : « Suivi » en pastilles (« Poids · 162,5 lb ») qui ouvrent le graphique.

## Tests

Reconnaissance (une trentaine de phrases, français du Québec et anglais, y compris les pièges), conversions, résumé
(dernière valeur, évolution sur 30 jours, min, max, moyenne), stockage (classement, relecture au lancement, corbeille,
suppression, export), captures d'écran avec des mesures inventées.

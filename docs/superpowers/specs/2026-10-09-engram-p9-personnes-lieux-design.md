# Engram P9 — Les personnes et les lieux de ta mémoire

*9 octobre 2026. Demande du propriétaire : « passe à l'étape la plus longue… crée des nouvelles fonctionnalités, de
préférence la plus compliquée ». Il avait aussi demandé, en P5, une IA qui fasse des liens entre les notes.*

## But

Engram reconnaît **de qui** et **d'où** parle chaque note, et relie les notes entre elles par ces personnes et ces
lieux. « Julie », « maman », « mon manager », « Costco », « le gym » deviennent des pages : toutes les notes qui en
parlent, les choses à faire avec elles, de la plus récente à la plus ancienne. Rien ne quitte l'iPhone de plus
qu'avant : les noms viennent de la même analyse que le classement (même service, mêmes règles de confidentialité).

## Ce qui compte comme une personne ou un lieu

- **Personne** : un prénom ou un nom (« Julie », « Marc Tremblay »), ou un mot qui désigne une personne précise de
  la vie du propriétaire (« maman », « mon frère », « mon manager »). Jamais « je », « moi », « on », « quelqu'un ».
- **Lieu** : un endroit précis où l'on va (« Costco », « le gym », « le bureau », « Québec », « chez le dentiste » →
  « Dentiste »). Jamais un lieu vague (« dehors », « quelque part », « la maison » du propriétaire).
- Chaque nom doit figurer dans le texte de la note (règle anti-invention), 4 personnes et 4 lieux au plus par note,
  40 caractères au plus.

## Noms et doublons

- **Clé** (pour reconnaître le même) : minuscules, sans accents ni ponctuation, sans les petits mots du début
  (le, la, les, l', un, une, au, aux, à, chez, du, de, des, d', mon, ma, mes, ton, ta, tes, son, sa, ses, notre, nos,
  votre, vos, leur, leurs). « Mon manager », « le manager » et « mon Manager » sont la même personne ; « au gym » et
  « le gym », le même lieu.
- **Nom affiché** : les articles et prépositions du début enlevés (« le gym » → « Gym », « chez le dentiste » →
  « Dentiste ») ; pour une personne, le possessif est gardé (« Mon manager », « Ma sœur ») ; première lettre en
  majuscule.
- **Fusionner** (« Julie T. » dans « Julie ») : les notes passent à la personne gardée, et l'ancien nom devient un
  **alias** : quand l'IA le retrouve plus tard, il va directement à la bonne personne.
- **Renommer** vers un nom qui existe déjà = fusionner.
- **« Ce n'est pas une personne / un lieu »** : la page disparaît, et l'IA ne recrée plus ce nom.
- **Retirer d'une note** : le lien est gardé « rejeté », l'IA ne le remet pas (comme pour les catégories).

## Données

Migration `v5_people_places` (jamais de modification des migrations publiées) :

- `entity` : id, kind (`person`/`place`), name, normalized_name, status (`active`/`hidden`), created_at, updated_at ;
  unique (kind, normalized_name).
- `entity_alias` : kind, normalized_name, entity_id ; clé (kind, normalized_name).
- `memory_entity` : memory_id, entity_id, origin (`ai`/`user`), confirmed, rejected, created_at, updated_at ;
  clé (memory_id, entity_id). Mêmes règles que les catégories : l'IA n'écrase jamais un choix du propriétaire.

L'export (JSON) contient les personnes, les lieux, les alias et les liens. La sauvegarde chiffrée les contient déjà
(copie de la base).

## Où les noms sont trouvés

- **Classement** (Gemini, Groq ou le modèle d'Apple) : deux champs de plus par élément, `people` et `places`, recopiés
  de la note. Consignes `p9`.
- **Anciennes notes** : Réglages › « Retrouver les personnes et les lieux » relit, **sur l'iPhone**, les notes qui
  n'en ont aucun, avec la reconnaissance des noms d'Apple (NaturalLanguage). Rien n'est envoyé.

## Écrans

- **Notes** : deux dossiers de plus, « Personnes » et « Lieux » (s'il y en a). Chaque ligne : une pastille ronde
  (initiales de couleur pour une personne, épingle pour un lieu), le nom, le nombre de notes et la dernière mention,
  le nombre de choses à faire.
- **Page d'une personne ou d'un lieu** : en-tête (grande pastille, nom, chiffres), « À faire avec… », puis toutes les
  notes, par mois. Menu : Renommer, Fusionner avec…, « Ce n'est pas une personne ».
- **Une note** : « Avec » et « Où » en pastilles sous « Rangée dans » ; toucher ouvre la page ; « + » pour ajouter
  un nom, appui long pour le retirer.
- **Retrouver** : les noms comptent comme des mots forts d'une note (« qu'est-ce que je dois dire à Julie ? »).
- **Cerveau** : bouton « Personnes » dans la barre : chaque personne devient un petit nœud blanc relié à ses notes,
  d'une catégorie à l'autre (les liens entre les notes deviennent visibles).

## Tests

Paquet : clés et noms affichés ; validation (nom absent du texte refusé, limites) ; décodage et schéma des services ;
migration ; liens au classement ; alias, fusion, renommage, masquage, rejet ; résumés (nombre, dernière mention,
choses à faire) ; export ; Retrouver ; relecture des anciennes notes avec un faux reconnaisseur. Interface : captures
des pages Personnes et d'une personne, avec des noms inventés.

Non testable sans l'iPhone : la qualité des noms trouvés par les IA et par la reconnaissance d'Apple en français
québécois.

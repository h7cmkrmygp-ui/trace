# P42 — La mémoire du contexte

## But

Comme dans une vraie conversation, Engram comprend un mot qui renvoie à ce qui vient d'être dit :

- « Julie aime les parfums. » puis, cinq minutes plus tard, « Elle adore aussi le chocolat. » : la deuxième note est reliée à Julie.
- « Ajoute un livre à cette liste » : le livre va dans la liste dont on vient de parler.
- « Pour ce projet, il faut aussi acheter du bois » : la note va dans le dossier du projet dont on vient de parler.

Règle d'or : **jamais de lien inventé**. Engram ne fait le lien que s'il y a une seule personne, une seule liste ou un seul projet possible. Sinon, rien n'est relié.

## Ce qui change

- **Le contexte récent** (`RecentContext`, `MemoryStore.recentContext(before:)`) vient de la dictée classée juste avant, il y a moins de 30 minutes. Il contient :
  - ses personnes (toutes ses notes, listes comprises) ;
  - les listes qu'elle a complétées ;
  - les dossiers de ses notes (pas celui des listes).
- **Dans une même dictée**, la phrase d'avant sert de contexte : « Julie aime les parfums. Elle adore aussi le chocolat. »
- **Repérage sans IA** (`ContextReferences`), sur l'iPhone :
  - Ce qu'on dit d'une personne : « lui », « elle aime/adore/voudrait… », « sa fête », « pour elle ». « Elle doit aller au garage » (une voiture) ne compte pas.
  - « Cette liste », « la même liste ».
  - « Ce projet », « ce dossier ».
- **Validation** :
  - Une note qui parle de quelqu'un sans le nommer est reliée à la seule personne du contexte. S'il y a plusieurs personnes, rien n'est relié.
  - « Cette liste » renvoie à la seule liste du contexte. Les choses dites y vont.
  - « Ce projet » renvoie au seul dossier du contexte, ou au seul dont le nom parle d'un projet. La raison est montrée dans « Pourquoi ce dossier ».
- **L'IA reçoit la note précédente**, par exemple : « Note précédente (il y a 5 min) : listes : … ; dossiers : … ».
  - Gemini (palier gratuit) ne reçoit aucune personne, seulement les listes sans nom propre et les grands dossiers.
  - Groq reçoit les listes et les dossiers, mais jamais les personnes d'une autre note. C'est ton choix : seuls des noms de dossiers (et de listes) quittent l'iPhone. Le lien « elle » vers la bonne personne se fait sur l'iPhone.
  - Le modèle d'Apple, sur l'iPhone, reçoit tout.
  - Versions des consignes : `p42-cloud-v1` et `p42-v1`.

## Tests

- `ContextualMemoryTests` : repérage, personne, liste et projet ; cas ambigus.
- `RecentContextStoreTests` : la dictée d'il y a 10 minutes est retenue ; celle d'il y a 2 heures ne l'est plus.
- `ContextPromptTests` : consignes et ce que reçoivent Gemini, Groq et le modèle d'Apple.
- `ContextPipelineTests` : deux dictées ; « elle » est reliée à Julie.

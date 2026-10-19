# P36 — Une recherche qui trouve

**Demande du propriétaire** : « Ça marche mieux. J'améliorerais la fonction recherche, à ta guise. »

## Ce qui n'allait pas

**La barre « Chercher dans ta mémoire »** (recherche par mots de SQLite) :
- elle exigeait que **chaque** mot soit dans la note : « c'est quoi le numéro d'assurance » ne trouvait rien sans le
  mot « quoi » ;
- une faute de frappe suffisait à ne rien trouver ;
- elle ne regardait ni le nom des dossiers, ni les personnes et les lieux liés à une note ;
- pas de synonymes (auto, voiture, char) ;
- les notes faites (« Fait ») n'y étaient pas ;
- elle ne montrait pas où le mot avait été trouvé.

**Retrouver** ne tolérait pas les fautes de frappe : un mot mal écrit qui ne partage pas les 5 premières lettres du bon
mot n'était pas reconnu.

## Ce qui change

1. **Fautes de frappe** (`RecallText.closeTypo`), dans la barre de recherche et dans Retrouver :
   - même première lettre ;
   - mots d'au moins 5 lettres, avec une lettre de différence, ou deux à partir de 8 lettres ;
   - « asurance » trouve « assurance », un prénom entendu à une lettre près est retrouvé ;
   - « pain » ne trouve pas « bain ».
2. **La barre de recherche utilise le moteur de Retrouver** (`RecallRanker.search`), sur l'iPhone, sans IA ni réseau,
   instantanément :
   - les petits mots et les mots de question sont ignorés ;
   - les notes qui ont le plus de mots cherchés viennent d'abord, puis celles qui n'en ont qu'une partie (score minimal
     0,3) ;
   - synonymes, dossiers, étiquettes, personnes et lieux comptent ;
   - le mot en train d'être tapé compte comme un début de mot (« coro » pour « Corolla ») ;
   - les notes faites viennent après les autres, jamais la corbeille ;
   - les notes sont lues une fois au début de la recherche, puis relues à la recherche suivante.
3. **Chaque résultat montre le passage trouvé** (`SearchSnippet`) : la phrase qui contient le plus de mots cherchés, ces
   mots en gras, et le dossier (ou « Fait », « À classer »).

Aucune migration. La recherche par mots de SQLite (`searchText`) reste disponible.

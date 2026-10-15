# P44 — La fête qui approche propose une idée de cadeau

## But

Engram se montre utile au bon moment, sans déranger : la veille d'une fête, le rappel qui existait déjà (depuis P20) propose une idée de cadeau tirée des notes. Par exemple, le rappel « Demain : la fête de Julie » dit « Pense à souhaiter bonne fête. Idées de cadeaux : Foulard. Julie aime les parfums et le chocolat. »

Le propriétaire l'a demandé : **aucune nouvelle notification, aucun rappel qu'il n'a pas demandé.** Seul le texte du rappel de la veille change. Le rappel du jour même ne change pas.

## Ce qui change

- `PersonQuestion.reminderIdeas` : au plus 3 idées de cadeaux (ce qui reste dans les listes à son nom) et 2 goûts (« aime … »), tirés de ses notes. Si les notes ne disent rien, le rappel reste comme avant.
- `EntityStore.birthdayIdeas()` : une ligne par personne dont la fête est connue.
- `BirthdayPlanner.plan(…, ideas:)` : la ligne s'ajoute au rappel de la veille. Quand Engram est verrouillé, rien ne se lit : le rappel dit seulement « Ouvre Engram pour la voir ».

## Tests

- `ProactiveBirthdayTests` : le même nombre de rappels ; le texte de la veille ; celui du jour inchangé ; Engram verrouillé ; la ligne d'idées.
- `ProactiveBirthdayStoreTests` : seules les personnes dont la fête est connue reçoivent une ligne.

# Engram avec ChatGPT et Claude : étude MCP

*Étude faite le 9 octobre 2026, à partir des pages d'aide officielles d'OpenAI et d'Anthropic et de guides récents.
Les offres changent souvent : à revérifier avant de payer quoi que ce soit.*

## Ce que tu voulais

Dire à ChatGPT ou à Claude « Retrouve-moi l'idée que j'avais enregistrée dans Engram la semaine dernière », et
pouvoir aussi y enregistrer quelque chose depuis ces assistants.

## Comment marche MCP

MCP (Model Context Protocol) est une façon standard de brancher un assistant sur un outil : l'assistant appelle un petit
« serveur MCP », qui lui répond (par exemple : les notes qui correspondent à une question).

Le hic pour Engram : **ta mémoire n'existe que sur ton iPhone**, et c'est voulu.

| Assistant | Ce qu'il exige | Prix | Possible pour Engram ? |
|---|---|---|---|
| **Claude** (web, app iPhone, app PC) : « connecteur personnalisé » | un serveur MCP **joignable sur Internet** (adresse HTTPS publique) ; Claude s'y connecte depuis les serveurs d'Anthropic | gratuit, **1 connecteur** sur le forfait gratuit | Pas directement : l'iPhone ne peut pas rester allumé comme serveur sur Internet. Il faudrait une copie de tes notes sur un serveur en ligne. |
| **Claude Desktop** (app Windows) : serveur MCP **local** | un petit programme qui tourne sur ton PC | gratuit | Oui, en théorie : le PC lirait une copie de tes notes (par exemple ta sauvegarde dans iCloud Drive). |
| **ChatGPT** : « mode développeur », applications MCP | un serveur MCP joignable sur Internet ; ajout seulement depuis le site web | réservé aux forfaits payants (surtout Business, Enterprise et Edu ; flou pour Plus et Pro) | Non sans payer, et il faudrait aussi un serveur en ligne. |
| **iPhone (iOS 27)** | Apple n'a pas adopté MCP ; il passe par les App Intents (Siri, Raccourcis) | gratuit | Oui, et c'est déjà en place (voir plus bas). |

## Confidentialité

Dès qu'un assistant en ligne lit une note, le texte de cette note part chez OpenAI ou chez Anthropic. Un serveur MCP
en ligne voudrait dire **une copie de ta mémoire hors de l'iPhone, en permanence**. C'est contraire à tes choix
(pas de serveur, rien ne part sans ton accord, « Garder sur l'iPhone » respecté). Cette partie est donc **mise de côté** :
c'est à toi de décider si tu la veux un jour.

## Ce qui marche dès maintenant, sans payer et sans serveur

### 1. Enregistrer depuis ChatGPT ou Claude → Engram

Dans l'app ChatGPT ou Claude, sélectionne une réponse, touche **Partager**, puis **Engram**. La note arrive dans Engram
et se classe toute seule (extension de partage, depuis la P6).

### 2. Retrouver dans Engram → donner à ChatGPT ou Claude (nouveau)

Nouvelle action dans l'app **Raccourcis** : **« Trouver dans Engram pour un assistant »**.

- Tu lui donnes une question ; elle renvoie **en texte** les notes trouvées (5 au plus : titre, type, date, texte).
- Les notes **gardées sur l'iPhone** (ou jugées secrètes) ne sont **jamais** incluses ; le texte dit combien ont été
  laissées de côté.
- Si « Tout garder sur l'iPhone » est activé, elle ne renvoie rien.
- Il faut que l'iPhone soit déverrouillé (Face ID ou code).
- Rien ne part tout seul : c'est **ton** raccourci qui décide où va ce texte.

Exemple de raccourci à créer (une seule fois) :

1. Ouvre **Raccourcis** › **+**.
2. Ajoute **Demander à l'utilisateur** (texte) : « Qu'est-ce que tu cherches ? ».
3. Ajoute **Trouver dans Engram pour un assistant**, avec la réponse comme question.
4. Ajoute l'action de l'app de ton assistant (par exemple **ChatGPT › Demander à ChatGPT**), ou simplement
   **Copier dans le presse-papiers** pour le coller dans Claude.
5. Nomme le raccourci, par exemple « Mémoire pour ChatGPT », pour le lancer avec Siri.

*Pas encore testé sur ton iPhone : à vérifier (point 70 de la liste de vérification).*

## Prochaine étape possible (à toi de décider)

**Claude Desktop sur ton PC avec un serveur MCP local**, en lecture seule :

- Engram range déjà une sauvegarde chiffrée dans iCloud Drive ; iCloud pour Windows la recopie sur le PC.
- Un petit serveur MCP sur le PC l'ouvrirait avec ton mot de passe, **sans jamais lire les notes gardées sur l'iPhone**,
  et répondrait à Claude Desktop (« Retrouve l'idée de la semaine passée »).
- Gratuit, mais il faut installer Node.js sur le PC, et chaque note trouvée part chez Anthropic pour la réponse.
- Les notes ne seraient à jour qu'à la dernière sauvegarde (chaque semaine, ou « Sauvegarder maintenant »).

Je ne l'ai pas commencé : cela touche à ton mot de passe de sauvegarde et envoie des notes à Anthropic, donc il faut
ton accord.

## Sources

- [Anthropic — Get started with custom connectors using remote MCP](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)
- [Anthropic — Use connectors to extend Claude's capabilities](https://support.claude.com/en/articles/11176164-use-connectors-to-extend-claude-s-capabilities)
- [OpenAI — Developer mode and MCP apps in ChatGPT](https://help.openai.com/en/articles/12584461-developer-mode-and-mcp-apps-in-chatgpt)
- [Apple — WWDC26 iOS guide](https://developer.apple.com/wwdc26/guides/ios/)
- Guides récents (à prendre avec prudence) : [Peliqan — ChatGPT MCP](https://peliqan.io/blog/chatgpt-mcp/),
  [Usecarly — ChatGPT MCP](https://www.usecarly.com/blog/chatgpt-mcp/), [Hjarni — ChatGPT MCP](https://hjarni.com/blog/how-to-use-mcp-with-chatgpt),
  [Coveo — Claude Desktop MCP](https://docs.coveo.com/en/pbpb0442/), [Blake Crosley — App Intents vs MCP](https://blakecrosley.com/blog/app-intents-vs-mcp-tools-frontier)

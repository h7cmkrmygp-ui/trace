# Engram

Application iPhone personnelle de mémoire intelligente : capturer ses pensées, les laisser s'organiser seules, les retrouver.

Projet personnel, non distribué. Le code est public ; **aucune donnée personnelle n'est versionnée**.

- Vision et conception : [`docs/superpowers/specs/`](docs/superpowers/specs/)
- Plans d'implémentation : [`docs/superpowers/plans/`](docs/superpowers/plans/)
- Feuille de route : [`docs/ROADMAP.md`](docs/ROADMAP.md)
- État réel : [`docs/IMPLEMENTATION_PROGRESS.md`](docs/IMPLEMENTATION_PROGRESS.md)
- Vérification sur l'iPhone : [`docs/VERIFICATION-IPHONE.md`](docs/VERIFICATION-IPHONE.md)

## Confidentialité

- Les notes, l'audio et la base restent sur l'iPhone. Le dépôt ne contient que du code et des exemples inventés.
- La transcription (Whisper) se fait sur l'iPhone.
- Avant tout classement en ligne, l'iPhone juge chaque note :
  - **neutre** : Gemini (palier gratuit) ;
  - **personnelle** : Groq (aucun entraînement sur les données) ;
  - **secrète ou douteuse** : uniquement l'IA d'Apple, sur l'iPhone.
- Les clés des services sont collées par le propriétaire dans l'app et rangées dans le trousseau de l'iPhone. Il n'y en a aucune dans ce dépôt, dans la CI ni dans l'IPA.

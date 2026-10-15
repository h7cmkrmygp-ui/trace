#!/usr/bin/env bash
# Usage : bash scripts/fetch-ipa.sh [branche]   (défaut : branche courante)
# Télécharge les .ipa du dernier run CI réussi : build/ipa/Engram.ipa (complète, avec widgets et partage)
# et build/ipa/Engram-simple.ipa (sans extensions, si AltStore refusait la complète).
set -euo pipefail
GH="${GH:-gh}"
command -v "$GH" >/dev/null 2>&1 || GH="/c/Program Files/GitHub CLI/gh.exe"
BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"
RUN_ID="$("$GH" run list --branch "$BRANCH" --limit 30 --json databaseId,workflowName,conclusion \
  --jq '[.[] | select(.workflowName == "CI" and .conclusion == "success")][0].databaseId // empty')"
[ -n "$RUN_ID" ] || { echo "Aucun run CI réussi sur $BRANCH"; exit 2; }
# On vide le contenu sans supprimer le dossier lui-même (OneDrive peut le verrouiller).
mkdir -p build/ipa
rm -rf build/ipa/Engram-ipa-* build/ipa/Engram.ipa build/ipa/Engram-simple.ipa
"$GH" run download "$RUN_ID" --pattern 'Engram-ipa-*' --dir build/ipa
for NAME in Engram.ipa Engram-simple.ipa; do
  FILE="$(find build/ipa -name "$NAME" -type f | head -1)"
  [ -n "$FILE" ] || { [ "$NAME" = "Engram.ipa" ] && { echo "Engram.ipa introuvable dans l'artefact"; exit 3; }; continue; }
  [ "$FILE" = "build/ipa/$NAME" ] || mv "$FILE" "build/ipa/$NAME"
  echo "✅ $(pwd)/build/ipa/$NAME (run $RUN_ID)"
done

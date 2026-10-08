#!/usr/bin/env bash
# Usage : bash scripts/fetch-ipa.sh [branche]   (défaut : branche courante)
# Télécharge le .ipa du dernier run CI réussi dans build/ipa/Engram.ipa.
set -euo pipefail
GH="${GH:-gh}"
command -v "$GH" >/dev/null 2>&1 || GH="/c/Program Files/GitHub CLI/gh.exe"
BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"
RUN_ID="$("$GH" run list --branch "$BRANCH" --limit 30 --json databaseId,workflowName,conclusion \
  --jq '[.[] | select(.workflowName == "CI" and .conclusion == "success")][0].databaseId // empty')"
[ -n "$RUN_ID" ] || { echo "Aucun run CI réussi sur $BRANCH"; exit 2; }
# On vide le contenu sans supprimer le dossier lui-même (OneDrive peut le verrouiller).
mkdir -p build/ipa
rm -rf build/ipa/Engram-ipa-* build/ipa/Engram.ipa
"$GH" run download "$RUN_ID" --pattern 'Engram-ipa-*' --dir build/ipa
IPA="$(find build/ipa -name 'Engram.ipa' -type f | head -1)"
[ -n "$IPA" ] || { echo "Engram.ipa introuvable dans l'artefact"; exit 3; }
[ "$IPA" = "build/ipa/Engram.ipa" ] || mv "$IPA" build/ipa/Engram.ipa
echo "✅ $(pwd)/build/ipa/Engram.ipa (run $RUN_ID)"

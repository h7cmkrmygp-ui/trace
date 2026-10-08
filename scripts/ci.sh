#!/usr/bin/env bash
# Usage : bash scripts/ci.sh [fichier-workflow]   (défaut : ci.yml)
# Pousse la branche courante, attend le run GitHub Actions du commit HEAD et affiche le résultat.
set -euo pipefail
WORKFLOW="${1:-ci.yml}"
GH="${GH:-gh}"
command -v "$GH" >/dev/null 2>&1 || GH="/c/Program Files/GitHub CLI/gh.exe"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
SHA="$(git rev-parse HEAD)"
git push -u origin "$BRANCH"
echo "En attente du run $WORKFLOW pour $SHA…"
RUN_ID=""
for _ in $(seq 1 40); do
  RUN_ID="$("$GH" run list --workflow "$WORKFLOW" --commit "$SHA" --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
  [ -n "$RUN_ID" ] && break
  sleep 5
done
[ -n "$RUN_ID" ] || { echo "Aucun run $WORKFLOW trouvé pour $SHA"; exit 2; }
if "$GH" run watch "$RUN_ID" --exit-status --interval 20 >/dev/null; then
  echo "✅ CI verte (run $RUN_ID)"
else
  echo "❌ CI en échec (run $RUN_ID). Journaux des étapes en échec :"
  "$GH" run view "$RUN_ID" --log-failed | tail -n 200
  exit 1
fi

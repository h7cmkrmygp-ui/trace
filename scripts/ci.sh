#!/usr/bin/env bash
# Usage : bash scripts/ci.sh [nom-du-workflow]   (défaut : CI)
# Pousse la branche courante, attend le run GitHub Actions du commit HEAD et affiche le résultat.
# Le workflow est désigné par son « name: » (ex. "CI", "SDK check") : le filtre par fichier
# de `gh run list --workflow` exige que le workflow existe déjà sur la branche par défaut.
set -euo pipefail
WORKFLOW="${1:-CI}"
GH="${GH:-gh}"
command -v "$GH" >/dev/null 2>&1 || GH="/c/Program Files/GitHub CLI/gh.exe"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
SHA="$(git rev-parse HEAD)"
git push -u origin "$BRANCH"
echo "En attente du run « $WORKFLOW » pour $SHA…"
RUN_ID=""
for _ in $(seq 1 40); do
  RUN_ID="$("$GH" run list --commit "$SHA" --limit 20 --json databaseId,workflowName \
    --jq "[.[] | select(.workflowName == \"$WORKFLOW\")][0].databaseId // empty" || true)"
  [ -n "$RUN_ID" ] && break
  sleep 5
done
[ -n "$RUN_ID" ] || { echo "Aucun run « $WORKFLOW » trouvé pour $SHA"; exit 2; }
if "$GH" run watch "$RUN_ID" --exit-status --interval 20 >/dev/null; then
  echo "✅ CI verte (run $RUN_ID)"
else
  echo "❌ CI en échec (run $RUN_ID). Journaux des étapes en échec :"
  "$GH" run view "$RUN_ID" --log-failed | tail -n 200
  exit 1
fi

#!/bin/sh
# Lance les tests navigateur et en établit le verdict.
#
# Trois choses que ce script fait, et pourquoi :
#
# 1. Il tue les serveurs Playwright orphelins avant de commencer. Le plugin
#    démarre le sien via `Process::fromShellCommandline()`, donc sous un
#    `sh -c 'node …'` : son `stop()` envoie SIGTERM au SHELL, le `node` enfant y
#    survit et se fait réparenter à PID 1. Huit orphelins relevés le 2026-08-06.
#    Ils n'expliquent pas le blocage, mais ils l'aggravent.
#
# 2. Il borne le run. Sans borne, un run bloqué immobilise la CI jusqu'au
#    timeout du job — indiscernable d'une panne d'infrastructure.
#
# 3. Il ne se fie PAS au code de sortie de pest, mais au rapport JUnit.
#    Voir browser-verdict.php pour le raisonnement complet.
#
# Usage : run-browser-tests.sh [timeout_secondes] [chemin_tests]

set -u

TIMEOUT="${1:-300}"
TEST_PATH="${2:-tests/Browser}"
REPORT="${BROWSER_JUNIT_REPORT:-/tmp/browser-junit.xml}"
SCRIPT_DIR="$(dirname "$0")"

# Les crochets empêchent le motif de matcher la ligne de commande de ce script
# lui-même — sans eux, pkill se suiciderait.
pkill -f "[p]laywright run-server" 2>/dev/null

rm -f "$REPORT"

timeout -s KILL "$TIMEOUT" ./vendor/bin/pest "$TEST_PATH" --log-junit "$REPORT"
PEST_EXIT=$?

exec php "$SCRIPT_DIR/browser-verdict.php" "$REPORT" "$PEST_EXIT"

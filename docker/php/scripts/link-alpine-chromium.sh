#!/bin/sh
# Rend le Chromium natif d'Alpine visible par Playwright.
#
# POURQUOI CE SCRIPT EXISTE
# -------------------------
# Playwright ne distribue que des builds `linux64` liés à la glibc. L'image PHP
# de ce projet est Alpine (musl) : le binaire téléchargé est un ELF x86-64
# valide, mais son interpréteur (`ld-linux-x86-64.so.2`) est absent, donc le
# noyau répond « not found » à l'exécution. Vérifié le 2026-08-06, voir ADR-0013.
#
# Le plugin Pest ne permet pas de passer `executablePath` (les options de
# `BrowserFactory::launch()` sont codées en dur). La seule voie est donc de
# placer le Chromium d'Alpine là où Playwright ira le chercher.
#
# POURQUOI LA RÉVISION EST DÉRIVÉE, JAMAIS ÉCRITE EN DUR
# ------------------------------------------------------
# Playwright calcule un chemin versionné (`chromium-<révision>`). Coder « 1217 »
# ici créerait un couplage muet avec la version npm de Playwright : une montée
# de version changerait le chemin attendu et le lien pointerait à côté. On lit
# donc la révision dans `playwright-core/browsers.json`, seule source de vérité.
#
# Si ce fichier est absent, on échoue bruyamment : un runner navigateur qui
# démarre sans navigateur est précisément le genre de garde-fou silencieux que
# ce projet traque.

set -eu

BROWSERS_JSON="${1:-/var/www/html/node_modules/playwright-core/browsers.json}"
DEST="${PLAYWRIGHT_BROWSERS_PATH:-/opt/ms-playwright}"
CHROMIUM_BIN="$(command -v chromium || command -v chromium-browser || true)"

if [ ! -f "$BROWSERS_JSON" ]; then
    echo "ERREUR : $BROWSERS_JSON introuvable." >&2
    echo "        Playwright n'est pas installé. Lancez : make composer / npm install." >&2
    exit 1
fi

if [ -z "$CHROMIUM_BIN" ]; then
    echo "ERREUR : aucun binaire chromium dans le PATH." >&2
    echo "        Ce script doit tourner dans l'image bâtie sur le stage 'test'." >&2
    exit 1
fi

REVISION="$(
    node -e '
        const b = require(process.argv[1]).browsers;
        const c = b.find((x) => x.name === "chromium");
        if (!c) { process.exit(2); }
        process.stdout.write(String(c.revision));
    ' "$BROWSERS_JSON"
)"

if [ -z "$REVISION" ]; then
    echo "ERREUR : révision chromium illisible dans $BROWSERS_JSON." >&2
    exit 1
fi

link_one() {
    dir="$1"
    exe="$2"
    mkdir -p "$DEST/$dir"
    ln -sf "$CHROMIUM_BIN" "$DEST/$dir/$exe"
    # Playwright refuse d'utiliser un dossier sans ce marqueur.
    touch "$DEST/${dir%%/*}/INSTALLATION_COMPLETE"
}

link_one "chromium-$REVISION/chrome-linux64" "chrome"
link_one "chromium_headless_shell-$REVISION/chrome-headless-shell-linux64" "chrome-headless-shell"

# Lisible par l'uid 1000 : le Makefile lance les tests en -u 1000:1000, alors
# que l'image est bâtie en root. Sans ça, Playwright ne trouve rien.
chmod -R a+rX "$DEST"

echo "Chromium $("$CHROMIUM_BIN" --version 2>/dev/null | head -1) lié dans $DEST (révision Playwright $REVISION)."

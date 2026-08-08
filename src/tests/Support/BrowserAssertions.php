<?php

declare(strict_types=1);

namespace Tests\Support;

/**
 * Les aides communes aux tests navigateur — lire une valeur calculée, attendre
 * une condition, refuser de conclure sans preuve.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CETTE CLASSE EXISTE
 *
 * Elles vivaient en closures locales à tests/Browser/LayoutsTest.php (Story
 * 1.13). La Story 1.12 ouvre un SECOND fichier de tests navigateur : les
 * dupliquer, c'est garantir qu'une des deux copies dérivera en silence — et une
 * aide de test qui dérive rend son fichier vert pour la mauvaise raison.
 *
 * C'est exactement le raisonnement qui a fait extraire Tests\Support\RouteTable
 * en 1.13. Extraire d'abord, utiliser ensuite.
 */
final class BrowserAssertions
{
    /**
     * Le <body>, écrit sous une forme que le plugin reconnaît comme du CSS.
     *
     * ⚠️ Piège coûteux, trouvé en Story 1.13 : `keys('body', 'Tab')` échoue sur
     * un « Timeout 5000ms exceeded » qui ne nomme rien. `GuessLocator` ne traite
     * une chaîne comme un sélecteur CSS que si elle COMMENCE par `#`, `.`, `[`
     * ou `internal:`, ou si elle CONTIENT un caractère spécial CSS. `body` n'a
     * rien de tout cela : le plugin cherche donc `[id="body"]`, puis
     * `[name="body"]`, puis un élément dont le TEXTE vaut « body » — et attend
     * cinq secondes qu'il apparaisse. `html > body` contient `>`, donc il est
     * reconnu.
     */
    public const string DOCUMENT_BODY = 'html > body';

    /**
     * Rend un `mixed` lisible DANS UN MESSAGE d'échec, sans prétendre le typer.
     *
     * `script()` renvoie `mixed`. L'interpoler tel quel est une erreur PHPStan
     * au niveau 10, et surtout : un message d'échec qui affiche « Array » ou
     * rien du tout ne dit pas ce qui s'est passé.
     */
    public static function readable(mixed $value): string
    {
        return is_string($value) ? $value : get_debug_type($value);
    }

    /**
     * Expression JS renvoyant une propriété calculée, sous forme de chaîne.
     */
    public static function computed(string $selector, string $property): string
    {
        return sprintf(
            "(() => { const el = document.querySelector('%s'); return el === null ? 'ABSENT' : String(getComputedStyle(el).getPropertyValue('%s')); })()",
            $selector,
            $property,
        );
    }

    /**
     * Expression JS renvoyant le texte d'un élément, sous forme de chaîne.
     *
     * Même contrat que `computed()` — 'ABSENT' plutôt que `null` — pour que
     * `asComputedValue()` distingue « l'élément n'existe pas » de « le texte est
     * vide ». Sans cette distinction, un sélecteur devenu faux passerait pour un
     * libellé vide, et l'assertion suivante mesurerait le vide.
     */
    public static function text(string $selector): string
    {
        return sprintf(
            "(() => { const el = document.querySelector('%s'); return el === null ? 'ABSENT' : String(el.textContent).trim(); })()",
            $selector,
        );
    }

    /**
     * Expression JS renvoyant un attribut de données, sous forme de chaîne.
     */
    public static function dataAttribute(string $selector, string $attribute): string
    {
        return sprintf(
            "(() => { const el = document.querySelector('%s'); return el === null ? 'ABSENT' : String(el.getAttribute('%s')); })()",
            $selector,
            $attribute,
        );
    }

    /**
     * Resserre le `mixed` de script() en chaîne, ICI plutôt qu'à chaque usage.
     *
     * Trois refus explicites, parce que chacun rendrait une assertion vide de
     * sens : non-chaîne (script() n'a rien renvoyé d'exploitable), 'ABSENT' (le
     * sélecteur ne désigne aucun élément) et '' (propriété non résolue, qui
     * passerait tranquillement un `->not->toBe('none')`).
     */
    public static function asComputedValue(mixed $value, string $what): string
    {
        expect(is_string($value))
            ->toBeTrue("Aucune valeur calculée pour {$what} : script() n'a pas renvoyé de chaîne.");

        $string = is_string($value) ? $value : '';

        expect($string)
            ->not->toBe('ABSENT', "L'élément visé par [{$what}] n'existe pas dans la page.");

        expect($string)
            ->not->toBe('', "Valeur calculée vide pour {$what} : la propriété n'a pas été résolue.");

        return $string;
    }

    /**
     * Lit une valeur calculée jusqu'à ce que deux lectures consécutives coïncident.
     *
     * Une temporisation fixe est un pari sur la vitesse de la machine ; un test
     * instable finit désarmé. C'est la raison, pas le confort.
     *
     * @param  callable(): mixed  $read
     */
    public static function settled(callable $read, string $what): string
    {
        $previous = null;

        for ($attempt = 0; $attempt < 15; $attempt++) {
            $current = self::asComputedValue($read(), $what);

            if ($current === $previous) {
                return $current;
            }

            $previous = $current;
            usleep(80_000);
        }

        expect(false)
            ->toBeTrue("La valeur calculée de {$what} ne s'est jamais stabilisée (dernière : [{$previous}]).");

        return (string) $previous;
    }

    /**
     * Attend qu'une lecture renvoie la valeur attendue, avec une BORNE d'attente.
     *
     * ⚠️ `$boundMs` BORNE LE TEMPS DORMI, PAS LE TEMPS MURAL. Chaque `$read()`
     * est un aller-retour Playwright qui n'est pas compté : une borne annoncée à
     * 5 000 ms peut consommer plusieurs dizaines de secondes réelles. C'est
     * volontaire — borner le temps mural rendrait le test dépendant de la
     * vitesse de la machine, ce que la Story 1.11 a payé cher — mais il faut
     * l'écrire, sans quoi le nom promet une garantie qu'il ne donne pas.
     *
     * ⚠️ NE PAS EMPLOYER SUR UNE VALEUR MONOTONE (un compteur qui s'incrémente).
     * L'égalité stricte peut être SAUTÉE si un aller-retour dure plus longtemps
     * que la période d'incrément : la valeur attendue n'est alors jamais
     * observée et le test échoue alors que la production est juste. Employer
     * `waitUntilAtLeast()`, écrite pour ce cas.
     *
     * Le retour (temps dormi) n'est PAS une assertion : la borne l'est déjà,
     * puisque le dépassement lève ici même. Un `expect($retour)->toBeLessThan($borne)`
     * au point d'appel est toujours vrai — trois de ces assertions vides ont été
     * retirées à la revue du 2026-08-08.
     *
     * @param  callable(): mixed  $read
     */
    public static function waitUntilValue(callable $read, string $expected, int $boundMs, string $what): int
    {
        $waited = 0;
        $last = '';

        while ($waited <= $boundMs) {
            /*
             * Resserré ICI, comme dans `waitUntilChanged()`. Sans cela, un
             * sélecteur devenu faux renvoie 'ABSENT', ne vaut jamais l'attendu,
             * et le test dépense toute sa borne avant d'échouer sur « la valeur
             * n'est jamais arrivée » — jamais sur « l'élément n'existe pas ».
             */
            $last = self::asComputedValue($read(), $what);

            if ($last === $expected) {
                return $waited;
            }

            usleep(50_000);
            $waited += 50;
        }

        expect(false)
            ->toBeTrue("{$what} : la valeur attendue [{$expected}] n'est jamais arrivée en {$boundMs} ms d'attente (dernière : ["
                . $last . ']).');

        return $waited;
    }

    /**
     * Attend qu'un compteur MONOTONE atteigne un seuil, avec une BORNE d'attente.
     *
     * ─────────────────────────────────────────────────────────────────────────
     * POURQUOI CETTE MÉTHODE EXISTE, PLUTÔT QU'UN `waitUntilValue($read, '3', …)`
     *
     * `data-time-ticks` s'incrémente toutes les 250 ms et ne repasse jamais par
     * une valeur manquée. La sonde dort 50 ms entre deux lectures, mais chaque
     * lecture est un aller-retour Playwright NON COMPTÉ : dès qu'il dépasse la
     * période d'incrément — WSL2 chargé, CI, second Chromium — le compteur passe
     * de 2 à 4 et la valeur '3' n'est JAMAIS observée. Le test échoue alors que
     * la garde qu'il observe fonctionne parfaitement, sur une suite dont
     * l'ADR-0013 documente déjà qu'elle bloque une fois sur deux : le réflexe
     * suivant est de le désarmer.
     *
     * Un seuil `>=` dit exactement ce que le test veut savoir — « la fenêtre
     * d'observation a bien eu lieu » — sans dépendre d'une valeur exacte que
     * rien ne garantit d'observer.
     *
     * @param  callable(): mixed  $read
     * @return int la valeur atteinte
     */
    public static function waitUntilAtLeast(callable $read, int $threshold, int $boundMs, string $what): int
    {
        $waited = 0;
        $last = '';

        while ($waited <= $boundMs) {
            $last = self::asComputedValue($read(), $what);

            if (is_numeric($last) && (int) $last >= $threshold) {
                return (int) $last;
            }

            usleep(50_000);
            $waited += 50;
        }

        expect(false)
            ->toBeTrue("{$what} : le seuil de {$threshold} n'a jamais été atteint en {$boundMs} ms d'attente (dernière : ["
                . $last . ']).');

        return 0;
    }

    /**
     * Attend qu'une lecture CHANGE par rapport à une valeur de départ, avec une BORNE.
     *
     * Le pendant de `waitUntilValue()` quand on ne connaît pas la valeur
     * d'arrivée — un libellé de durée relative, par exemple, dont on sait
     * seulement qu'il doit bouger.
     *
     * ⚠️ Même réserve que `waitUntilValue()` : `$boundMs` borne le temps DORMI,
     * pas le temps mural.
     *
     * @param  callable(): mixed  $read
     */
    public static function waitUntilChanged(callable $read, string $from, int $boundMs, string $what): string
    {
        $waited = 0;

        while ($waited <= $boundMs) {
            $current = self::asComputedValue($read(), $what);

            if ($current !== $from) {
                return $current;
            }

            usleep(50_000);
            $waited += 50;
        }

        /*
         * Le message ne peut PAS afficher « dernière valeur lue » : sur ce
         * chemin, elle vaut `$from` par définition de la boucle. La première
         * rédaction gardait une variable `$last` pour l'afficher — elle ne
         * pouvait valoir que `$from`, et le message répétait donc deux fois la
         * même chaîne en ayant l'air de diagnostiquer quelque chose.
         */
        expect(false)
            ->toBeTrue("{$what} : la valeur [{$from}] n'a jamais changé en {$boundMs} ms d'attente.");

        return $from;
    }
}

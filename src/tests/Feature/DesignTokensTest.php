<?php

declare(strict_types=1);

/*
 * Design system tokens — single source of truth (UX-DR-40/41/44/45, ADR-0008,
 * docs/architecture/2-stack-technique.md §2.5).
 *
 * Three things are proven here:
 *   1. resources/css/tokens.css declares the 15 canonical tokens with the exact
 *      values pinned by §2.5.
 *   2. resources/css/app.css imports them and bridges them to Tailwind 4 via an
 *      @theme block (Tailwind 4 is CSS-first — there is no tailwind.config.js).
 *   3. ANTI-HEX GUARD: no design-system stylesheet other than tokens.css may
 *      hardcode a hex literal. Every colour must flow through var(--token).
 *
 * On the guard being self-proven (lesson from Stories 1.5/1.6/1.7): a scanner
 * that walks files can pass by vacuity — green because it found nothing to look
 * at, not because the code is clean. The detector is therefore exercised against
 * synthetic fixtures (one that MUST be flagged, one that MUST NOT), and the real
 * scan asserts it actually opened at least one file.
 *
 * SCOPE LIMIT (deliberate): only `resources/css/*.css` is scanned. Blade
 * templates are NOT audited here — hardcoded hex in Blade is covered by the
 * bounded `grep` audit planned in Story 10.4 (`audit-lava-grep-bounded`), and
 * the existence of the `bg-lava` utility makes `bg-[#FF5722]` arbitrary values
 * unnecessary in the first place.
 */

/**
 * The 15 canonical tokens (AC1) — name => exact declared value.
 *
 * @return array<string, string>
 */
$canonicalTokens = static fn (): array => [
    '--bg' => '#0A0A0B',
    '--surface' => '#141416',
    '--border' => '#1F1F22',
    '--text-primary' => 'rgba(255, 255, 255, 0.92)',
    '--text-secondary' => 'rgba(255, 255, 255, 0.60)',
    '--accent-lava' => '#FF5722',
    '--state-ok' => '#22C55E',
    '--state-warn' => '#F59E0B',
    '--state-err' => '#EF4444',
    '--font-sans' => "'IBM Plex Sans', ui-sans-serif, system-ui, sans-serif",
    '--font-mono' => "'IBM Plex Mono', ui-monospace, 'SFMono-Regular', 'Menlo', monospace",
    '--leading-prose' => '1.7',
    '--max-prose' => '720px',
    '--ease-default' => 'cubic-bezier(0.16, 1, 0.3, 1)',
    '--duration-default' => '200ms',
];

/**
 * Read a file under the application root, failing loud if it is missing.
 */
$readCss = static function (string $relativePath): string {
    $absolute = base_path($relativePath);

    expect(file_exists($absolute))->toBeTrue("Expected {$relativePath} to exist.");

    $contents = file_get_contents($absolute);

    expect($contents)->toBeString("Expected {$relativePath} to be readable.");

    return (string) $contents;
};

/**
 * Drop CSS comments so assertions inspect declarations, not documentation.
 *
 * A stylesheet is allowed — encouraged, even — to write about the things it must
 * not do ("no light theme, no prefers-color-scheme"). Matching raw substrings
 * across comments would turn that documentation into a failure.
 */
$stripComments = static fn (string $css): string => (string) preg_replace('#/\*.*?\*/#s', '', $css);

/**
 * Find hex colour literals that are NOT inside a var() reference and NOT inside
 * a CSS comment. Those are the hardcodes the design system forbids.
 *
 * @return list<string>
 */
$findHardcodedHex = static function (string $css) use ($stripComments): array {
    // Comments may legitimately cite a hex (e.g. documenting the Lava value).
    $stripped = $stripComments($css);

    // var(--token) and var(--token, fallback) are the sanctioned way to use a colour.
    $stripped = (string) preg_replace('#\bvar\(\s*--[^)]*\)#', '', $stripped);

    preg_match_all('/#[0-9A-Fa-f]{3,8}\b/', $stripped, $matches);

    return $matches[0];
};

/**
 * Design-system stylesheets subject to the anti-hex guard (tokens.css is the one
 * file allowed to hold raw hex — it is where the values are defined).
 *
 * @return list<string>
 */
$guardedStylesheets = static function (): array {
    $found = glob(base_path('resources/css/*.css'));

    $files = array_values(array_filter(
        $found === false ? [] : $found,
        static fn (string $path): bool => basename($path) !== 'tokens.css',
    ));

    return $files;
};

it('declares the 15 canonical design tokens with the exact values pinned by §2.5', function () use ($readCss, $canonicalTokens): void {
    $css = $readCss('resources/css/tokens.css');

    foreach ($canonicalTokens() as $token => $value) {
        expect($css)->toContain("{$token}: {$value};");
    }
});

it('scopes the tokens to :root and stays dark-only (no light theme, UX-DR-45)', function () use ($readCss, $stripComments): void {
    $css = $readCss('resources/css/tokens.css');

    expect($css)->toContain(':root');

    // A light-mode branch would break the dark-only identity signal. Comments are
    // stripped first: documenting the ban is not the same as implementing it.
    expect($stripComments($css))->not->toContain('prefers-color-scheme');
});

it('documents its own contract: single source of truth, 90/8/2 and the 4 Lava usages', function () use ($readCss): void {
    $css = $readCss('resources/css/tokens.css');

    expect($css)
        ->toContain('single source of truth')
        ->toContain('UX-DR-40')
        ->toContain('ADR-0008')
        ->toContain('2-stack-technique.md')
        ->toContain('90/8/2');
});

it('imports the tokens into app.css and bridges them to Tailwind 4 via @theme', function () use ($readCss): void {
    $css = $readCss('resources/css/app.css');

    expect($css)
        ->toContain("@import './tokens.css'")
        ->toContain('@theme');
});

it('maps every Tailwind theme variable onto a token rather than a literal', function () use ($readCss): void {
    $css = $readCss('resources/css/app.css');

    $bridges = [
        '--color-bg' => '--bg',
        '--color-surface' => '--surface',
        '--color-border' => '--border',
        '--color-text-primary' => '--text-primary',
        '--color-text-secondary' => '--text-secondary',
        '--color-lava' => '--accent-lava',
        '--color-ok' => '--state-ok',
        '--color-warn' => '--state-warn',
        '--color-err' => '--state-err',
        '--font-sans' => '--font-sans',
        '--font-mono' => '--font-mono',
        '--ease-default' => '--ease-default',
    ];

    foreach ($bridges as $themeVariable => $token) {
        expect($css)->toContain("{$themeVariable}: var({$token});");
    }
});

it('imports the tokens UNLAYERED so they outrank Tailwind self-referencing theme vars', function () use ($readCss): void {
    /*
     * Load-bearing, and subtle enough to deserve its own test.
     *
     * Two tokens share a name with the Tailwind theme variable they feed
     * (--font-sans, --ease-default). The bridge therefore emits a literal
     * self-reference into the theme layer:
     *
     *     @layer theme { :root, :host { --font-sans: var(--font-sans) } }
     *
     * That is harmless ONLY because tokens.css is imported without a layer():
     * an unlayered declaration outranks any layered one, so the real value from
     * tokens.css wins the cascade and the self-reference is discarded before
     * custom-property resolution ever runs — no dependency cycle.
     *
     * Put tokens.css inside a layer (e.g. `@import './tokens.css' layer(base);`)
     * and the self-reference wins instead, becoming a cycle: --font-sans and
     * --ease-default compute to the guaranteed-invalid value. Typography and
     * motion would silently fall back with NO build error and NO console error.
     * Story 1.9 (self-hosted IBM Plex) touches exactly these variables.
     */
    $css = $readCss('resources/css/app.css');

    expect($css)->toMatch("#@import\s+'\./tokens\.css'\s*;#");
});

it('no longer ships the Laravel starter kit font (Instrument Sans)', function () use ($readCss): void {
    expect($readCss('resources/css/app.css'))->not->toContain('Instrument Sans');
});

it('keeps the four @source directives that drive Tailwind class detection', function () use ($readCss): void {
    $css = $readCss('resources/css/app.css');

    expect(substr_count($css, '@source '))->toBe(4);
});

it('flags a hardcoded hex (guard self-check — the detector must be able to fail)', function () use ($findHardcodedHex): void {
    $offending = <<<'CSS'
        .promo {
            background-color: #AABBCC;
        }
        CSS;

    expect($findHardcodedHex($offending))->toContain('#AABBCC');
});

it('does not flag hex inside var() references or comments (guard self-check, no false positive)', function () use ($findHardcodedHex): void {
    $clean = <<<'CSS'
        /* Lava is #FF5722 — documented here on purpose. */
        .badge-live {
            background-color: var(--accent-lava);
            color: var(--text-primary, #FFFFFF);
        }
        CSS;

    expect($findHardcodedHex($clean))->toBeEmpty();
});

it('finds no hardcoded hex in any design-system stylesheet (real scan)', function () use ($guardedStylesheets, $findHardcodedHex): void {
    $files = $guardedStylesheets();

    // Anti-vacuity: a scan over zero files would be green and worthless.
    expect($files)->not->toBeEmpty('The anti-hex scan found no stylesheet to inspect.');

    foreach ($files as $file) {
        $contents = (string) file_get_contents($file);

        expect($findHardcodedHex($contents))
            ->toBeEmpty(basename($file) . ' hardcodes a hex colour — use var(--token) instead.');
    }
});

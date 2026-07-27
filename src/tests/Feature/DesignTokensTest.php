<?php

declare(strict_types=1);

/**
 * Design system tokens — single source of truth (UX-DR-40/41/44/45, ADR-0008,
 * docs/architecture/2-stack-technique.md §2.5).
 * Three things are proven here:
 *   1. resources/css/tokens.css declares the 15 canonical tokens with the exact
 *      values pinned by §2.5.
 *   2. resources/css/app.css imports them and bridges them to Tailwind 4 via an
 *      @theme block (Tailwind 4 is CSS-first — there is no tailwind.config.js).
 *   3. ANTI-HEX GUARD: no design-system stylesheet other than tokens.css may
 *      hardcode a hex literal. Every colour must flow through var(--token).
 * On the guard being self-proven (lesson from Stories 1.5/1.6/1.7): a scanner
 * that walks files can pass by vacuity — green because it found nothing to look
 * at, not because the code is clean. The detector is therefore exercised against
 * synthetic fixtures (one that MUST be flagged, one that MUST NOT), and the real
 * scan asserts it actually opened at least one file.
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
    // Variance assumée vs AC1, qui pinnait la valeur sans les familles emoji : sans
    // elles, Tailwind fait perdre les emoji du corps de texte (cf. commentaire dans
    // tokens.css). Corrigé suite au code review de la Story 1.8.
    '--font-sans' => "'IBM Plex Sans', ui-sans-serif, system-ui, sans-serif, 'Apple Color Emoji', 'Segoe UI Emoji', 'Segoe UI Symbol', 'Noto Color Emoji'",
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

    expect(file_exists($absolute))
        ->toBeTrue("Expected {$relativePath} to exist.");

    $contents = file_get_contents($absolute);

    expect($contents)
        ->toBeString("Expected {$relativePath} to be readable.");

    return (string) $contents;
};

/**
 * Drop comments so assertions inspect code, not documentation.
 *
 * A file is allowed — encouraged, even — to write about the things it must not do
 * ("no light theme, no prefers-color-scheme", "never use max-w-prose"). Matching
 * raw substrings across comments would turn that documentation into a failure.
 *
 * Handles CSS (slash-star), Blade ({{-- --}}) and HTML (<!-- -->) so the same
 * helper serves the stylesheet and template scans alike.
 */
$stripComments = static function (string $source): string {
    $patterns = [
        '#/\*.*?\*/#s',
        '#\{\{--.*?--\}\}#s',
        '#<!--.*?-->#s',
    ];

    return (string) preg_replace($patterns, '', $source);
};

/**
 * Assert a needle is absent, with a message that actually reaches the reporter.
 *
 * NOT a style preference — a correctness fix. Pest's `toContain()` is variadic
 * over NEEDLES, so `expect($x)->not->toContain('foo', 'my message')` negates
 * "contains foo AND my message". The message never appears in the file, so the
 * conjunction is always false and the negation always passes: the assertion can
 * never fail. Two guards here shipped vacuous exactly that way and were caught
 * only by mutation-testing them. `toBeFalse()` does take a real message.
 */
$expectAbsent = static function (string $haystack, string $needle, string $message): void {
    expect(str_contains($haystack, $needle))
        ->toBeFalse($message);
};

/**
 * Find hardcoded colours — literals that are NOT inside a var() reference and NOT
 * inside a CSS comment. Those are what the design system forbids.
 *
 * Covers every notation a colour can arrive in, not just hex: `oklch(...)`,
 * `rgb(...)`, `hsl(...)`, `color(...)`, `lab/lch(...)` and the named colours that
 * actually get typed by hand. A guard that only knows `#RRGGBB` would wave
 * `background: oklch(0.7 0.21 41)` straight through — Tailwind's own palette is
 * authored in oklch, so that notation is the likeliest one to be pasted in.
 *
 * `currentColor`, `transparent` and `inherit` are deliberately allowed: they carry
 * no design decision of their own.
 *
 * @return list<string>
 */
$findHardcodedColours = static function (string $css) use ($stripComments): array {
    // Comments may legitimately cite a colour (e.g. documenting the Lava value).
    $stripped = $stripComments($css);

    // var(--token) and var(--token, fallback) are the sanctioned way to use a colour.
    $stripped = (string) preg_replace('#\bvar\(\s*--[^)]*\)#', '', $stripped);

    $patterns = [
        '/#[0-9A-Fa-f]{3,8}\b/',
        '/\b(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch|color|color-mix)\s*\(/i',
        '/\b(?:white|black|red|green|blue|yellow|orange|purple|pink|gray|grey|silver|maroon|navy|teal|olive|lime|aqua|fuchsia)\b/i',
    ];

    $found = [];

    foreach ($patterns as $pattern) {
        preg_match_all($pattern, $stripped, $matches);
        foreach ($matches[0] as $match) {
            $found[] = trim($match);
        }
    }

    return $found;
};

/**
 * Design-system stylesheets subject to the guard (tokens.css is the one file
 * allowed to hold raw colour values — it is where they are defined).
 *
 * The walk is RECURSIVE on purpose: Filament conventionally puts panel themes at
 * `resources/css/filament/<panel>/theme.css` (arriving in Story 1.10). A flat
 * glob would skip them while the anti-vacuity check still passed on app.css —
 * a blind spot that looks exactly like coverage.
 *
 * @return list<string>
 */
$guardedStylesheets = static function (): array {
    $root = base_path('resources/css');

    if (! is_dir($root)) {
        return [];
    }

    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS),
    );

    $files = [];

    foreach ($iterator as $file) {
        if (! $file instanceof SplFileInfo || $file->getExtension() !== 'css') {
            continue;
        }

        if ($file->getFilename() === 'tokens.css') {
            continue;
        }

        $files[] = $file->getPathname();
    }

    sort($files);

    return $files;
};

/**
 * Every Blade template, recursively. Fonts are requested from HTML and utility
 * classes are written in HTML, so template scans are not optional extras here.
 *
 * @return list<string>
 */
$blades = static function (): array {
    $root = base_path('resources/views');

    if (! is_dir($root)) {
        return [];
    }

    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS),
    );

    $files = [];

    foreach ($iterator as $file) {
        if ($file instanceof SplFileInfo && str_ends_with($file->getFilename(), '.blade.php')) {
            $files[] = $file->getPathname();
        }
    }

    sort($files);

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

    expect($css)
        ->toContain(':root');

    // A light-mode branch would break the dark-only identity signal. Comments are
    // stripped first: documenting the ban is not the same as implementing it.
    expect($stripComments($css))
        ->not->toContain('prefers-color-scheme');
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
        // Bridged after the Story 1.8 code review — see the test below for why.
        '--leading-prose' => '--leading-prose',
        '--container-measure' => '--max-prose',
        '--default-transition-duration' => '--duration-default',
        '--default-transition-timing-function' => '--ease-default',
    ];

    foreach ($bridges as $themeVariable => $token) {
        expect($css)->toContain("{$themeVariable}: var({$token});");
    }
});

it('leaves no token declared but ungoverned — every token reaches a utility or a default', function () use ($readCss, $canonicalTokens): void {
    /*
     * The failure this prevents is the one the whole story exists to prevent: a
     * value that LOOKS like the single source of truth while governing nothing.
     *
     * Three tokens shipped that way in the first cut of Story 1.8, because AC2
     * listed only 12 bridges for 15 tokens:
     *   - --leading-prose  : `leading-prose` emitted no rule whatsoever.
     *   - --max-prose      : `max-w-prose` fell through to Tailwind's built-in 65ch.
     *   - --duration-default: `transition` ran at Tailwind's 150ms default.
     * None of it errored. Nothing went red. The stylesheet simply lied.
     *
     * Every token must therefore be reachable, either through the @theme bridge
     * or by being consumed directly (the raw palette values feed --color-*).
     */
    $appCss = $readCss('resources/css/app.css');

    $consumedDirectly = ['--bg', '--surface', '--border', '--text-primary', '--text-secondary'];

    foreach (array_keys($canonicalTokens()) as $token) {
        if (in_array($token, $consumedDirectly, true)) {
            continue;
        }

        expect($appCss)
            ->toContain("var({$token});");
    }
});

it('bans max-w-prose, which silently resolves to Tailwind\'s 65ch instead of the token', function () use ($guardedStylesheets, $blades, $stripComments, $expectAbsent): void {
    /*
     * `max-w-prose` is a HARDCODED Tailwind built-in (65ch). Unlike every other
     * container name it cannot be overridden — verified against the compiled CSS
     * with both `@theme` and `@theme inline`, while the very same namespace
     * generates any other name correctly. So --max-prose is exposed as
     * `max-w-measure`, and typing the intuitive `max-w-prose` would quietly give
     * 65ch instead of the 720px pinned by §2.5.
     *
     * Renaming alone leaves the trap armed. This turns it into a loud failure.
     */
    $sources = array_merge($guardedStylesheets(), $blades());

    expect($sources)
        ->not->toBeEmpty('Nothing was scanned for the max-w-prose ban.');

    foreach ($sources as $source) {
        $code = $stripComments((string) file_get_contents($source));

        $expectAbsent(
            $code,
            'max-w-prose',
            basename($source) . ' uses max-w-prose (65ch); use max-w-measure for the 720px token.',
        );
    }
});

it('imports the tokens UNLAYERED so they outrank Tailwind self-referencing theme vars', function () use ($readCss): void {
    /**
     * Load-bearing, and subtle enough to deserve its own test.
     * Two tokens share a name with the Tailwind theme variable they feed
     * (--font-sans, --ease-default). The bridge therefore emits a literal
     * self-reference into the theme layer:
     *     @layer theme { :root, :host { --font-sans: var(--font-sans) } }
     * That is harmless ONLY because tokens.css is imported without a layer():
     * an unlayered declaration outranks any layered one, so the real value from
     * tokens.css wins the cascade and the self-reference is discarded before
     * custom-property resolution ever runs — no dependency cycle.
     * Put tokens.css inside a layer (e.g. `@import './tokens.css' layer(base);`)
     * and the self-reference wins instead, becoming a cycle: --font-sans and
     * --ease-default compute to the guaranteed-invalid value. Typography and
     * motion would silently fall back with NO build error and NO console error.
     * Story 1.9 (self-hosted IBM Plex) touches exactly these variables.
     */
    $css = $readCss('resources/css/app.css');

    expect($css)
        ->toMatch("#@import\s+'\./tokens\.css'\s*;#");
});

it('serves no Instrument Sans and no third-party font host anywhere in the app', function () use ($blades, $stripComments, $expectAbsent): void {
    /*
     * The first cut of this test only read app.css and was therefore vacuous: the
     * app still shipped Instrument Sans, because welcome.blade.php pulled it from
     * fonts.bunny.net on every page load. The stylesheet was clean; the app was
     * not. Scanning the templates too is the whole point — fonts are requested
     * from HTML, not from CSS.
     *
     * Third-party font hosts are banned outright: IBM Plex is self-hosted in
     * Story 1.9 (SIL OFL), and a remote font is both a privacy leak and a render
     * blocker for every fork-streamer deployment.
     */
    $sources = array_merge(glob(base_path('resources/css/*.css')) ?: [], $blades());

    expect($sources)
        ->not->toBeEmpty('Nothing was scanned for the font ban.');

    $banned = ['Instrument Sans', 'fonts.bunny.net', 'fonts.googleapis.com', 'fonts.gstatic.com'];

    foreach ($sources as $source) {
        $code = $stripComments((string) file_get_contents($source));
        $name = basename($source);

        foreach ($banned as $needle) {
            $expectAbsent($code, $needle, "{$name} references {$needle}; IBM Plex is self-hosted (Story 1.9).");
        }
    }
});

it('keeps the four @source directives that drive Tailwind class detection', function () use ($readCss): void {
    $css = $readCss('resources/css/app.css');

    expect(substr_count($css, '@source '))
        ->toBe(4);
});

it('flags a hardcoded colour in every notation (guard self-check — it must be able to fail)', function () use ($findHardcodedColours): void {
    /*
     * One case per notation. A guard that only knew #RRGGBB would wave the other
     * three through — and oklch() is the likeliest paste of all, since Tailwind's
     * own palette is authored in it.
     */
    expect($findHardcodedColours('.a { background-color: #AABBCC; }'))
        ->toContain('#AABBCC');
    expect($findHardcodedColours('.b { background: oklch(0.7 0.21 41); }'))
        ->not->toBeEmpty();
    expect($findHardcodedColours('.c { color: rgb(255 87 34); }'))
        ->not->toBeEmpty();
    expect($findHardcodedColours('.d { color: white; }'))
        ->not->toBeEmpty();
});

it('does not flag colours inside var() references or comments (guard self-check, no false positive)', function () use ($findHardcodedColours): void {
    $clean = <<<'CSS'
        /* Lava is #FF5722 — documented here on purpose, and white is fine in prose. */
        .badge-live {
            background-color: var(--accent-lava);
            color: var(--text-primary, #FFFFFF);
        }
        CSS;

    expect($findHardcodedColours($clean))
        ->toBeEmpty();
});

it('finds no hardcoded colour in any design-system stylesheet (real scan, recursive)', function () use ($guardedStylesheets, $findHardcodedColours): void {
    $files = $guardedStylesheets();

    // Anti-vacuity: a scan over zero files would be green and worthless.
    expect($files)
        ->not->toBeEmpty('The colour scan found no stylesheet to inspect.');

    foreach ($files as $file) {
        $contents = (string) file_get_contents($file);

        expect($findHardcodedColours($contents))
            ->toBeEmpty(basename($file) . ' hardcodes a colour — use var(--token) instead.');
    }
});

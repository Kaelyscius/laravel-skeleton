<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Spatie\Csp\AddCspHeaders;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // FR3-1: Robust parsing — empty/whitespace string falls back to '*' (skeleton's
        // default-behind-Apache topology), so a misconfigured TRUSTED_PROXIES= line
        // doesn't silently disable HTTPS detection. Operators wanting strict CIDR list
        // set explicit comma-separated values; everything else (including unset env)
        // defaults to wildcard.
        $trustedProxies = trim((string) env('TRUSTED_PROXIES', '*'));
        if ($trustedProxies === '' || $trustedProxies === '*') {
            $at = '*';
        } else {
            $parsed = array_values(array_filter(array_map('trim', explode(',', $trustedProxies))));
            $at = $parsed === [] ? '*' : $parsed;
        }
        $middleware->trustProxies(
            at: $at,
            headers: Request::HEADER_X_FORWARDED_FOR
                | Request::HEADER_X_FORWARDED_HOST
                | Request::HEADER_X_FORWARDED_PROTO
                | Request::HEADER_X_FORWARDED_PORT,
        );

        // FR3-3: Scope CSP to web group only (not global). The default Spatie Basic
        // preset injects strict nonces; applying it globally would break Filament/
        // Horizon/Pulse/Telescope dashboards whose inline <script> blocks don't
        // use @cspNonce. Future story wiring Filament admin (Story 1.10) must
        // either customize the policy or exclude admin routes from CSP.
        $middleware->web(append: [AddCspHeaders::class]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        //
    })->create();

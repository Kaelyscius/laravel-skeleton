<?php

declare(strict_types=1);

namespace App\Core\Support;

/**
 * Turns the operator's `TRUSTED_PROXIES` value into the shape Laravel's
 * TrustProxies middleware expects, and reports separately what it had to refuse.
 *
 * ⛔ PURE AND SIDE-EFFECT FREE ON PURPOSE — do not reintroduce a `throw` here.
 *
 * The refusal of a wildcard buried in a list used to be a `throw` inside
 * `config/proxies.php`. A config file throws while `config/` is being LOADED, so
 * a single typo made `php artisan config:cache` fail at container start — and
 * then every subsequent artisan command, including the ones an operator would
 * reach for to repair it. The refusal is still hard and still visible, but it
 * now happens in `php artisan proxies:check`, which the entrypoint runs BEFORE
 * `config:cache`: the application stays repairable, and the check is testable.
 *
 * Review decision D8, 2026-08-20.
 */
final class TrustedProxies
{
    /**
     * The token Symfony resolves to the connecting peer's address.
     *
     * 🔴 CE JETON N'EST PAS UN DÉFAUT SÛR, ET C'EST MESURÉ — revue de sécurité du
     * 2026-08-20. Il a été le défaut de ce projet entre le 2026-08-09 et cette
     * date, en remplacement de `*`, au motif qu'il ne ferait confiance qu'à
     * « Apache, le pair immédiat ». CETTE PRÉMISSE EST FAUSSE SOUS FastCGI.
     *
     * Apache ne parle pas HTTP à PHP : il transmet la requête à PHP-FPM par
     * FastCGI en posant `REMOTE_ADDR` = l'adresse du CLIENT. Mesuré sur cette
     * pile, requête émise depuis un conteneur voisin :
     *
     *   client      = 172.18.0.3            (conteneur émetteur)
     *   apache      = 172.18.0.11           (SERVER_ADDR)
     *   REMOTE_ADDR                         → 172.18.0.3      ← LE CLIENT
     *   trustedProxies                      → ['172.18.0.3']
     *   X-Forwarded-For: 198.51.100.42      → request()->ip()  = 198.51.100.42  ❌
     *   X-Forwarded-Host: evil.example      → getHost()        = evil.example   ❌
     *
     * `Request::setTrustedProxies()` remplace le jeton par `$_SERVER['REMOTE_ADDR']`,
     * donc le client devient son propre proxy de confiance et son `X-Forwarded-For`
     * est honoré : STRICTEMENT ÉQUIVALENT au `*` qu'il était censé remplacer.
     *
     * Il reste accepté — une topologie où PHP voit réellement le proxy existe —
     * mais `proxies:check` le signale.
     */
    public const string REMOTE_ADDR = 'REMOTE_ADDR';

    /**
     * « Aucun proxy de confiance », exprimé par une valeur que RIEN ne peut satisfaire.
     *
     * 🔴 POURQUOI PAS SIMPLEMENT UN TABLEAU VIDE — LA FAILLE, TROISIÈME ITÉRATION.
     *
     * `TrustProxies::proxies()` est `static::$alwaysTrustProxies ?: $this->proxies`.
     * Un tableau VIDE est **falsy** : la valeur configurée s'effondre donc sur
     * `null`, strictement indiscernable de « jamais configuré ». Or dans cette
     * branche, `setTrustedProxyIpAddresses()` fait :
     *
     *   if (is_null($trustedIps) && (laravel_cloud()
     *       || str_ends_with($request->host(), '.on-forge.com')
     *       || str_ends_with($request->host(), '.on-vapor.com'))) {
     *       $trustedIps = '*';
     *   }
     *
     * `$request->host()` est l'en-tête `Host`, écrit par le CLIENT. Un attaquant
     * envoyant `Host: x.on-vapor.com` obtenait donc `setTrustedProxies(['0.0.0.0/0',
     * '::/0'])` — la faille d'origine, intégralement, sur un seul en-tête.
     *
     * MESURÉ en HTTP réel le 2026-08-20, `TRUSTED_PROXIES=` vide :
     *
     *   Host: localhost        → ip = 172.18.0.3      trusted = []
     *   Host: x.on-vapor.com   → ip = 198.51.100.42   trusted = ['0.0.0.0/0','::/0']  ❌
     *   Host: y.on-forge.com   → ip = 198.51.100.42   trusted = ['0.0.0.0/0','::/0']  ❌
     *
     * `0.0.0.0/32` est l'adresse « non spécifiée » : aucune connexion TCP ne peut
     * en provenir, donc `IpUtils::checkIp()` la refuse pour tout pair réel. La
     * valeur est NON VIDE, donc `proxies()` ne rend plus `null`, donc le pivot
     * `.on-vapor.com` / `.on-forge.com` ne peut plus se déclencher — et elle ne
     * fait confiance à personne. Dire « aucun » exige ici de le dire avec quelque
     * chose ; un vide se fait relire comme un silence.
     *
     * @var list<string>
     */
    public const array TRUST_NOBODY = ['0.0.0.0/32'];

    /**
     * @return array{at: string|array<int, string>, problems: array<int, string>}
     */
    public static function parse(mixed $raw): array
    {
        // `Env` casts `true`, `false` and `null` to real PHP types BEFORE any
        // string cast reaches them: `TRUSTED_PROXIES=true` would otherwise become
        // the literal proxy `'1'`, which matches no address — so nothing is
        // trusted, and nobody is told. Finding Q22.
        if (! is_string($raw)) {
            return [
                'at' => self::TRUST_NOBODY,
                'problems' => [sprintf(
                    'TRUSTED_PROXIES vaut `%s`, qui n\'est pas une chaîne. Laissez la variable VIDE '
                    . '(aucun proxy de confiance, le défaut sûr) ou énumérez des adresses/CIDR '
                    . 'séparées par des virgules.',
                    var_export($raw, true),
                )],
            ];
        }

        $value = trim($raw);

        /*
         * ⛑️ LE DÉFAUT SÛR : AUCUN PROXY DE CONFIANCE.
         *
         * Sans proxy de confiance, `isFromTrustedProxy()` est faux, tout
         * `X-Forwarded-*` est ignoré, et `request()->ip()` rend `REMOTE_ADDR` —
         * que le client ne peut pas forger, puisque c'est l'adresse de sa propre
         * connexion TCP. `getHost()` cesse également d'être injectable.
         *
         * ⚠️ Et la détection HTTPS n'en souffre pas, contrairement à ce que ce
         * projet a affirmé jusqu'au 2026-08-20 : Apache termine TLS et pose
         * `HTTPS=on` dans les variables FastCGI. MESURÉ, liste vide, avec un
         * `X-Forwarded-Proto: http` forgé → `isSecure()` reste `true`.
         *
         * Un déploiement DERRIÈRE un vrai proxy amont (CDN, load-balancer) énumère
         * ce proxy en CIDR : là, `REMOTE_ADDR` est bien l'adresse du LB, et le
         * dépouillement de la chaîne redevient correct.
         */
        if ($value === '') {
            return [
                'at' => self::TRUST_NOBODY,
                'problems' => [],
            ];
        }

        // An EXPLICIT lone wildcard stays honoured. Neutralising it quietly would
        // make the configuration file lie about what is in force — the motif this
        // project hunts. It has legitimate uses (Laravel Cloud, Vapor, where the
        // infrastructure guarantees the header); it is documented as dangerous in
        // `.env.example`, and it is no longer the default.
        if ($value === '*') {
            return [
                'at' => '*',
                'problems' => [],
            ];
        }

        $entries = array_values(array_filter(array_map('trim', explode(',', $value))));

        $problems = [];
        $kept = [];

        foreach ($entries as $entry) {
            // A `*` BURIED IN A LIST (`10.0.0.0/8,*`) is not a wildcard: handed to
            // `IpUtils::checkIp()` it is a literal address that can never match. The
            // operator would believe they had allowed everything and have allowed
            // nothing. We drop it and keep the narrower — therefore safer — list,
            // and `proxies:check` refuses the deployment by name.
            if ($entry === '*') {
                $problems[] = 'TRUSTED_PROXIES contient `*` au milieu d\'une liste : ce n\'est pas un joker, '
                    . 'c\'est une adresse littérale que la comparaison CIDR ne peut jamais satisfaire. '
                    . 'Écrivez `TRUSTED_PROXIES=*` seul pour tout autoriser, ou retirez l\'astérisque. '
                    . 'En attendant, l\'astérisque est ÉCARTÉ et le reste de la liste est appliqué.';

                continue;
            }

            // 🔴 Signalé, pas refusé : voir le docblock de la constante.
            if ($entry === self::REMOTE_ADDR) {
                $problems[] = 'TRUSTED_PROXIES contient `REMOTE_ADDR`. Sous FastCGI (Apache/nginx → PHP-FPM), '
                    . 'ce jeton ne désigne PAS le reverse-proxy : il désigne le CLIENT, qui devient alors son '
                    . 'propre proxy de confiance. Son `X-Forwarded-For` est honoré — exactement comme avec `*`, '
                    . 'et la limitation des tentatives de connexion redevient inopérante. Laissez '
                    . 'TRUSTED_PROXIES VIDE, ou énumérez le CIDR du proxy amont réel.';

                $kept[] = $entry;

                continue;
            }

            if (! self::looksLikeIpOrCidr($entry)) {
                $problems[] = sprintf(
                    'TRUSTED_PROXIES contient `%s`, qui n\'est ni une adresse IP ni un CIDR. '
                    . 'Un nom d\'hôte n\'est jamais résolu par la comparaison CIDR : cette entrée ne correspondra '
                    . 'à aucun client, et `request()->ip()` rendra l\'adresse du proxy.',
                    $entry,
                );
            }

            $kept[] = $entry;
        }

        return [
            // Une liste entièrement écartée (que des `*` noyés) ne doit pas retomber
            // sur le tableau vide, pour la raison écrite sur TRUST_NOBODY.
            'at' => $kept === [] ? self::TRUST_NOBODY : $kept,
            'problems' => $problems,
        ];
    }

    /**
     * Shape check only — `IpUtils::checkIp()` is the authority at request time.
     * This exists so `proxies:check` can name a typo instead of letting it match
     * nothing forever.
     */
    private static function looksLikeIpOrCidr(string $entry): bool
    {
        $address = $entry;
        $prefix = null;

        if (str_contains($entry, '/')) {
            [$address, $prefix] = explode('/', $entry, 2);

            // ⚠️ `/033` n'est pas `/33` : un zéro de tête est une faute de frappe,
            // pas une notation. On refuse plutôt que d'interpréter.
            if ($prefix === '' || ! ctype_digit($prefix) || ($prefix !== '0' && str_starts_with($prefix, '0'))) {
                return false;
            }
        }

        if (filter_var($address, FILTER_VALIDATE_IP) === false) {
            return false;
        }

        // 🔴 LA BORNE DÉPEND DE LA FAMILLE, et ne pas le voir rendait le contrôle muet.
        //
        // La version précédente n'écartait que `> 128`, si bien que `10.0.0.0/64`
        // et `192.168.1.1/99` passaient sans un mot. Mesuré :
        // `IpUtils::checkIp('10.0.0.5', '10.0.0.0/64')` rend `false` — l'entrée ne
        // correspond donc à AUCUN client, `request()->ip()` rend l'adresse du proxy,
        // et tous les clients derrière lui partagent un seul seau. C'est exactement
        // la conséquence que le message de ce contrôle décrit, restée silencieuse
        // parce que la borne était celle de l'autre famille d'adresses.
        $isIpv4 = filter_var($address, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) !== false;

        return $prefix === null || (int) $prefix <= ($isIpv4 ? 32 : 128);
    }
}

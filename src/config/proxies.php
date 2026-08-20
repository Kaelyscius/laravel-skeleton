<?php

declare(strict_types=1);

/*
|--------------------------------------------------------------------------
| Reverse-proxy trust
|--------------------------------------------------------------------------
|
| 🔴 POURQUOI CE FICHIER EXISTE PLUTÔT QU'UN `env()` DANS `bootstrap/app.php`
|
| La lecture vivait dans le callback `withMiddleware()`. Ce callback s'exécute
| APRÈS le bootstrap, et `php artisan config:cache` fait sortir
| `LoadEnvironmentVariables` par la porte de service : `.env` n'est alors JAMAIS
| chargé. Un `env('TRUSTED_PROXIES', …)` posé là retombait donc silencieusement
| sur son défaut EN PRODUCTION — c'est-à-dire exactement dans l'environnement
| que la correction visait, et c'est le seul qui exécute `config:cache`
| (`docker/php/scripts/docker-entrypoint.sh`).
|
| Conséquence mesurable du défaut : un déploiement à proxys en cascade
| (CDN → LB → Apache) qui énumère ses proxys dans `.env`, comme `.env.example`
| le lui demande, aurait vu sa liste ignorée. `request()->ip()` aurait rendu
| l'IP du LB amont, donc UN SEUL SEAU DE LIMITATION POUR TOUS LES CLIENTS —
| le déni de service que le contre-test « still separates two genuinely
| different clients » interdit.
|
| Dans un fichier de `config/`, `env()` est appelé au moment où le cache est
| CONSTRUIT, et la valeur est figée dedans. C'est la seule place où `env()` est
| correct sous Laravel, et c'est la règle générale du framework — appliquée ici
| parce qu'elle a une conséquence de sécurité, pas par orthodoxie.
|
| Trouvé en revue de la Story 1.10a le 2026-08-10, décision D3.
|
|--------------------------------------------------------------------------
|
| 🔴 ET POURQUOI LE DÉFAUT EST VIDE — NI `*`, NI `REMOTE_ADDR`
|
| La même faille a été corrigée DEUX FOIS, et la première correction ne corrigeait
| rien.
|
| `*` (jusqu'au 2026-08-09) : Laravel le traduit par
| `setTrustedProxies(['0.0.0.0/0','::/0'])` — TOUTE adresse d'Internet devient un
| reverse-proxy de confiance. Symfony remonte alors `X-Forwarded-For` de droite à
| gauche en sautant tout ce qui est de confiance, donc jusqu'à l'entrée la plus à
| GAUCHE : celle qu'écrit le client.
|
| `REMOTE_ADDR` (du 2026-08-09 au 2026-08-20) : posé comme correctif, au motif
| qu'il ne ferait confiance qu'« au pair immédiat, c'est-à-dire au conteneur
| Apache ». ⛔ LA PRÉMISSE EST FAUSSE SOUS FastCGI. Apache ne parle pas HTTP à
| PHP : il transmet la requête à PHP-FPM par FastCGI en posant `REMOTE_ADDR` =
| l'adresse du CLIENT. `Request::setTrustedProxies()` remplace le jeton par cette
| adresse, si bien que le client devient SON PROPRE proxy de confiance et que son
| `X-Forwarded-For` est honoré : strictement équivalent au joker.
|
| Mesuré en HTTP réel le 2026-08-20, requête émise depuis un conteneur voisin :
|
|   client = 172.18.0.3 · apache = 172.18.0.11 (SERVER_ADDR)
|   REMOTE_ADDR                        → 172.18.0.3        ← le CLIENT
|   trustedProxies                     → ['172.18.0.3']
|   X-Forwarded-For:  198.51.100.42    → request()->ip()   = 198.51.100.42   ❌
|   X-Forwarded-Host: evil.example     → getHost()         = evil.example    ❌
|
| Le second `❌` n'est pas un détail : il rendait injectable toute URL absolue
| générée par l'application — redirections, liens signés, e-mails.
|
| DÉFAUT ACTUEL : VIDE, c'est-à-dire aucun proxy de confiance.
| `isFromTrustedProxy()` est faux, tout `X-Forwarded-*` est ignoré, et
| `request()->ip()` rend l'adresse de la connexion TCP — que le client ne peut pas
| forger. Vérifié dans la même configuration : ip = le pair, host = le vrai hôte.
|
| ⚠️ Et la détection HTTPS n'en souffre pas, contrairement à ce que ce fichier a
| affirmé : Apache termine TLS et pose `HTTPS=on` dans les variables FastCGI.
| Mesuré liste vide, avec un `X-Forwarded-Proto: http` forgé → `isSecure()` reste
| `true`.
|
| ⚠️ Deux justifications successives ont été écrites ici et étaient fausses : « `*`
| est safe derrière un reverse-proxy » (non — Apache AJOUTE l'IP source à
| `X-Forwarded-For`, il ne la remplace pas, donc être derrière un proxy rallonge
| la chaîne que le joker fait sauter), puis « `REMOTE_ADDR` ne fait confiance
| qu'au pair immédiat » (vrai de la lettre, faux de l'effet). Les deux avaient été
| écrites AVANT d'être mesurées de bout en bout.
|
| Un déploiement derrière un vrai proxy AMONT (CDN, load-balancer) énumère ce
| proxy en CIDR : là, `REMOTE_ADDR` est bien l'adresse du LB, et le dépouillement
| de la chaîne redevient correct.
|
*/

use App\Core\Support\TrustedProxies;

/*
|--------------------------------------------------------------------------
|
| ⛔ ET POURQUOI IL N'Y A PLUS DE `throw` ICI (décision D8, revue du 2026-08-20)
|
| Ce fichier refusait un `*` noyé dans une liste en levant une `RuntimeException`.
| Le refus était juste ; l'endroit ne l'était pas. Un fichier de `config/` lève
| PENDANT le chargement de la configuration : une faute de frappe faisait donc
| échouer `php artisan config:cache` au démarrage du conteneur, puis TOUTE
| commande artisan ensuite — y compris celles qu'un opérateur emploierait pour
| réparer sa faute de frappe. Le refus reste dur et reste visible, mais il vit
| désormais dans `php artisan proxies:check`, que l'entrypoint exécute AVANT
| `config:cache` : l'application reste réparable, et le contrôle devient testable.
|
| Le parsing lui-même vit dans `App\Core\Support\TrustedProxies` — une fonction
| pure, appelée ici pour la valeur et par `proxies:check` pour les refus.
|
*/

// ⛑️ Défaut : chaîne VIDE = aucun proxy de confiance. Voir TrustedProxies.
$parsed = TrustedProxies::parse(env('TRUSTED_PROXIES', ''));

return [
    /*
    | Valeur posée sur `Illuminate\Http\Middleware\TrustProxies::at()` par
    | `CoreServiceProvider::boot()`. Soit la chaîne `'*'`, soit une liste
    | d'adresses/CIDR, soit le tableau VIDE (aucun proxy de confiance — le défaut).
    |
    | ⛔ ELLE N'EST PLUS POSÉE DEPUIS `bootstrap/app.php`. Le callback
    | `withMiddleware()` s'exécute sur `afterResolving(HttpKernel::class)`, que
    | `Application::handleRequest()` déclenche AVANT `$kernel->handle()` — donc
    | avant le bootstrap. MESURÉ le 2026-08-20 : `app()->bound('config')` y vaut
    | `false`. Ni un `env()` ni un `config()` n'y sont lisibles ; seul un provider,
    | booté après `LoadConfiguration`, lit la valeur RÉELLE — y compris quand elle
    | vient du cache de configuration. Finding Q1.
    */
    'at' => $parsed['at'],

    /*
    | Ce que le parsing a dû refuser ou écarter, en clair. Vide = rien à signaler.
    | Lu par `php artisan proxies:check`, qui sort en erreur si la liste n'est pas
    | vide. Figé dans le cache de configuration en même temps que `at`, donc le
    | contrôle dit la vérité avant ET après `config:cache`.
    */
    'problems' => $parsed['problems'],
];

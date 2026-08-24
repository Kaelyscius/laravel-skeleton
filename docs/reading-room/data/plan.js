/* GÉNÉRÉ — ne pas éditer à la main.
   Source : _bmad-output/planning-artifacts/epics.md + sprint-status.yaml
   Regénérer : make reading-room */
window.RR_PLAN = {
 "generated": "2026-08-24",
 "commit": "8b0a399",
 "branch": "story/2-4-fix-install-clone-neuf",
 "dirty": true,
 "counts": {
  "epics": 11,
  "stories": 131,
  "done": 16,
  "requirements": 333
 },
 "families": {
  "FR": {
   "label": "Fonctionnelles",
   "hint": "Ce que le produit doit faire."
  },
  "NFR": {
   "label": "Non fonctionnelles",
   "hint": "Performance, sécurité, qualité, accessibilité, métriques."
  },
  "AR": {
   "label": "Additionnelles",
   "hint": "Contraintes venues de l'architecture et des ADR."
  },
  "UX-DR": {
   "label": "Design & UX",
   "hint": "Composants, tokens, patterns, accessibilité."
  }
 },
 "epics": [
  {
   "num": 1,
   "title": "Foundations for Fork-Streamers & Alex-Dev",
   "phase": "Phase 0/S0 ~40h = 5j",
   "pitch": "Alex (et tout fork-streamer futur) hérite d'une fondation propre — structure <code>app/Modules/*</code> PSR-4 + tenancy <code>streamer_id</code> partout + design tokens single source of truth + Streamer model complet (tagline/bio FR+EN/photo/CTAs — les six champs existent sur le modèle ; leur écran d'édition Filament arrive en Epic 5) + composants base + time-as-texture native (Direction C).",
   "meta": {
    "FRs covered": "FR-Scaff-1 à 10",
    "NFRs critical": "NFR-Stack-1 à 6 (LOCKED versions)"
   },
   "amendments": [
    "Streamer model étendu : <code>tagline + bio_fr + bio_en + photo_url + cta_text + cta_url</code> (Amelia : sinon Epics 5/8 improvisent)",
    "Filament <code>SettingsResource</code> <b>déplacé en Epic 5</b> (Story 1.10b) — les champs existent, l'écran non (pour Press Kit Epic 8 + CTAs Epic 5)",
    "Cartographie module→domaine documentée (Winston : risque §12.1 ADR-0009)",
    "Test Pest scan migrations <code>streamer_id NOT NULL</code> (Winston : risque §12.2)",
    "Deptrac ou Pest scan cross-modules <code>use</code> (Winston : risque §12.1 couplage)"
   ],
   "effort": "5j (40h)",
   "status": "done",
   "retro": "done",
   "stories": [
    {
     "id": "1.1",
     "epic": 1,
     "title": "Initialize Laravel 12 project with PSR-4 module structure",
     "role": "Alex-Dev",
     "want": "un projet Laravel 12 vanilla avec <code>app/Core/</code> + <code>app/Modules/{Public, Live, Reviews, PressKit, Admin}/</code> PSR-4 namespaces déclarés dans <code>composer.json</code>",
     "benefit": "l'architecture modulaire (ADR-0009) est bootstrappable et les modules sont isolés",
     "ac": [
      {
       "kw": "Given",
       "text": "un environnement vierge (<code>/src</code> vide)"
      },
      {
       "kw": "When",
       "text": "j'exécute <code>composer create-project laravel/laravel src</code> puis configure les 6 namespaces PSR-4 dans <code>composer.json</code>"
      },
      {
       "kw": "Then",
       "text": "<code>composer dump-autoload</code> réussit sans warning"
      },
      {
       "kw": "And",
       "text": "les 6 namespaces (<code>App\\Core\\</code>, <code>App\\Modules\\Public\\</code>, <code>App\\Modules\\Live\\</code>, <code>App\\Modules\\Reviews\\</code>, <code>App\\Modules\\PressKit\\</code>, <code>App\\Modules\\Admin\\</code>) résolvent correctement vers leurs dossiers"
      },
      {
       "kw": "And",
       "text": "<code>php artisan about</code> confirme Laravel 12.x installé"
      }
     ],
     "notes": [],
     "status": "done"
    },
    {
     "id": "1.2",
     "epic": 1,
     "title": "Configure Docker Compose profiles (prod, dev, tools, dev-extra)",
     "role": "Fork-Streamer (Persona 4 DX)",
     "want": "<code>docker-compose.yml</code> avec système de profiles (aucun/dev/tools/dev-extra)",
     "benefit": "je démarre uniquement les services nécessaires à mon environnement (<code>make up-prod</code> pour prod stricte, <code>make up-local</code> pour dev complet)",
     "ac": [
      {
       "kw": "Given",
       "text": "le repo cloné sur VPS vierge"
      },
      {
       "kw": "When",
       "text": "j'exécute <code>docker compose --profile=none up -d</code>"
      },
      {
       "kw": "Then",
       "text": "seuls <code>apache</code>, <code>php</code>, <code>postgres</code>, <code>postgres-pulse</code>, <code>redis</code> démarrent (5 conteneurs prod)"
      },
      {
       "kw": "Given",
       "text": "environnement local"
      },
      {
       "kw": "When",
       "text": "j'exécute <code>make up-local</code>"
      },
      {
       "kw": "Then",
       "text": "profiles <code>dev</code> + <code>tools</code> + <code>dev-extra</code> ajoutent <code>node</code>, <code>mailpit</code>, <code>adminer</code>, <code>dozzle</code>, <code>it-tools</code>, <code>watchtower</code>, <code>redis-commander</code>"
      },
      {
       "kw": "And",
       "text": "custom images (<code>php</code>, <code>apache</code>, <code>node</code>) sont exclues de Watchtower via label <code>com.centurylinklabs.watchtower.enable=false</code>"
      }
     ],
     "notes": [
      "<b>Note</b> : <code>phpmyadmin</code> retiré du scope (résidu ère MariaDB — <code>adminer</code> profile <code>dev</code> couvre déjà PostgreSQL ADR-0007). <code>dev-extra</code> = <code>redis-commander</code> uniquement."
     ],
     "status": "done"
    },
    {
     "id": "1.3",
     "epic": 1,
     "title": "Create Streamer model with extended fields",
     "role": "Alex-Dev",
     "want": "un modèle <code>Streamer</code> avec colonnes <code>id, name, tagline, bio_fr, bio_en, photo_url, cta_text, cta_url, twitter_handle, discord_url, timestamps</code>",
     "benefit": "tous les composants tenant-aware (Press kit Epic 8, CTAs Epic 5) lisent depuis une source unique sans hardcoder les données d'Alex",
     "ac": [
      {
       "kw": "Given",
       "text": "la migration <code>2026_01_01_000000_create_streamers_table.php</code>"
      },
      {
       "kw": "When",
       "text": "j'exécute <code>php artisan migrate</code>"
      },
      {
       "kw": "Then",
       "text": "la table <code>streamers</code> existe avec les 11 colonnes listées + <code>created_at</code> + <code>updated_at</code>"
      },
      {
       "kw": "And",
       "text": "chaque colonne a son type approprié (<code>tagline VARCHAR(255)</code>, <code>bio_fr TEXT</code>, <code>cta_text VARCHAR(100)</code>, <code>cta_url VARCHAR(500)</code>)"
      },
      {
       "kw": "Given",
       "text": "le seeder <code>DatabaseSeeder</code>"
      },
      {
       "kw": "When",
       "text": "j'exécute <code>php artisan db:seed</code>"
      },
      {
       "kw": "Then",
       "text": "un seul row <code>Streamer</code> est créé pour Alex avec valeurs par défaut placeholder"
      }
     ],
     "notes": [],
     "status": "done"
    },
    {
     "id": "1.4",
     "epic": 1,
     "title": "Implement tenancy Pattern C (scope + trait + middleware + singleton)",
     "role": "Alex-Dev",
     "want": "<code>streamer_id</code> sur toutes tables métier + <code>BelongsToStreamerScope</code> global scope + trait <code>BelongsToStreamer</code> + middleware <code>SetCurrentStreamer</code> + singleton <code>CurrentStreamer</code> fail-loud",
     "benefit": "la tenancy v1 mono-streamer est correcte et la migration v2+ multi-streamer reste additive (ADR-0002)",
     "ac": [
      {
       "kw": "Given",
       "text": "un modèle métier (ex. test fixture <code>Article</code> avec <code>streamer_id</code>)"
      },
      {
       "kw": "When",
       "text": "j'inclus le trait <code>BelongsToStreamer</code> dans le modèle"
      },
      {
       "kw": "Then",
       "text": "le global scope <code>BelongsToStreamerScope</code> est automatiquement appliqué via <code>static::addGlobalScope</code>"
      },
      {
       "kw": "And",
       "text": "toute requête <code>Article::all()</code> injecte <code>WHERE streamer_id = ?</code> automatiquement"
      },
      {
       "kw": "Given",
       "text": "une requête HTTP entrante"
      },
      {
       "kw": "When",
       "text": "le middleware <code>SetCurrentStreamer</code> s'exécute"
      },
      {
       "kw": "Then",
       "text": "il fait <code>Streamer::query()-&gt;firstOrFail()</code> + <code>app()-&gt;instance(CurrentStreamer::class, new CurrentStreamer($streamer))</code>"
      },
      {
       "kw": "Given",
       "text": "un appel <code>app(CurrentStreamer::class)-&gt;id()</code> sans binding préalable"
      },
      {
       "kw": "When",
       "text": "la classe est résolue"
      },
      {
       "kw": "Then",
       "text": "une exception explicite est levée (fail-loud)"
      }
     ],
     "notes": [],
     "status": "done"
    },
    {
     "id": "1.5",
     "epic": 1,
     "title": "Add <code>tenancy:assert</code> artisan command + CI test for streamer_id",
     "role": "Murat",
     "want": "commande <code>php artisan tenancy:assert</code> qui vérifie <code>Streamer::count() === 1</code> + un test Pest qui scanne les migrations pour <code>streamer_id NOT NULL</code> sur toutes tables métier",
     "benefit": "la CI bloque toute violation de tenancy v1 et toute migration oubliant <code>streamer_id</code>",
     "ac": [
      {
       "kw": "Given",
       "text": "une seule row Streamer en base"
      },
      {
       "kw": "When",
       "text": "j'exécute <code>php artisan tenancy:assert</code>"
      },
      {
       "kw": "Then",
       "text": "la commande exit code 0"
      },
      {
       "kw": "Given",
       "text": "deux rows Streamer en base (violation v1)"
      },
      {
       "kw": "When",
       "text": "j'exécute <code>php artisan tenancy:assert</code>"
      },
      {
       "kw": "Then",
       "text": "la commande exit code 1 avec message d'erreur explicite"
      },
      {
       "kw": "Given",
       "text": "une migration qui crée une table métier sans <code>streamer_id BIGINT NOT NULL</code>"
      },
      {
       "kw": "When",
       "text": "le test Pest <code>TenancyMigrationTest</code> s'exécute"
      },
      {
       "kw": "Then",
       "text": "il fail avec liste des tables manquantes"
      },
      {
       "kw": "And",
       "text": "le workflow GitHub Actions échoue (CI bloquante)"
      }
     ],
     "notes": [],
     "status": "done"
    },
    {
     "id": "1.6",
     "epic": 1,
     "title": "Add cross-module coupling guard (Pest scan <code>use</code> statements)",
     "role": "Winston",
     "want": "un test Pest qui scanne <code>use</code> statements pour bloquer <code>App\\Modules\\X</code> important <code>App\\Modules\\Y</code> (sauf via <code>App\\Core</code>)",
     "benefit": "le risque archi §12.1 couplage inter-modules direct est tracké et bloqué en CI dès S0",
     "ac": [
      {
       "kw": "Given",
       "text": "un fichier <code>app/Modules/Reviews/Models/Article.php</code>"
      },
      {
       "kw": "When",
       "text": "il déclare <code>use App\\Modules\\Live\\Services\\HelixClient</code>"
      },
      {
       "kw": "Then",
       "text": "le test Pest <code>CrossModuleCouplingTest</code> fail avec message indiquant le coupling interdit"
      },
      {
       "kw": "Given",
       "text": "le même fichier déclare <code>use App\\Core\\Models\\Streamer</code>"
      },
      {
       "kw": "When",
       "text": "le test s'exécute"
      },
      {
       "kw": "Then",
       "text": "il passe (Core est explicitement autorisé)"
      },
      {
       "kw": "And",
       "text": "un document <code>docs/process/05-module-boundaries.md</code> explique la règle et comment refactor via events si besoin émerge"
      }
     ],
     "notes": [],
     "status": "done"
    },
    {
     "id": "1.7",
     "epic": 1,
     "title": "Configure module activation via ENV (<code>config/modules.php</code> + bootstrap conditionnel)",
     "role": "Fork-Streamer",
     "want": "variables d'env <code>MODULE_&lt;NAME&gt;_ENABLED=true|false</code> + <code>config/modules.php</code> + <code>AppServiceProvider::register()</code> qui charge les service providers conditionnellement",
     "benefit": "je peux désactiver Reviews ou Live au déploiement sans toucher au code (ADR-0001)",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>config/modules.php</code> qui retourne <code>['public' =&gt; env('MODULE_PUBLIC_ENABLED', true), 'live' =&gt; env('MODULE_LIVE_ENABLED', true), ...]</code>"
      },
      {
       "kw": "When",
       "text": "<code>AppServiceProvider::register()</code> boucle sur les modules activés"
      },
      {
       "kw": "Then",
       "text": "seuls les service providers des modules <code>true</code> sont chargés"
      },
      {
       "kw": "Given",
       "text": "<code>MODULE_REVIEWS_ENABLED=false</code> dans <code>.env</code>"
      },
      {
       "kw": "When",
       "text": "je fais une requête <code>GET /reviews/elden-ring-test</code>"
      },
      {
       "kw": "Then",
       "text": "je reçois <code>404</code> (route non chargée, pas <code>500</code>)"
      },
      {
       "kw": "And",
       "text": "la migration <code>2026_02_15_reviews_*</code> n'est pas appliquée (<code>loadMigrationsFrom</code> skipped)"
      }
     ],
     "notes": [],
     "status": "done"
    },
    {
     "id": "1.8",
     "epic": 1,
     "title": "Publish CSS design tokens (single source of truth)",
     "role": "Sally + Caravaggio",
     "want": "<code>resources/css/tokens.css</code> contenant toutes les CSS custom properties (palette dark + Lava + states + typo + spacing + motion)",
     "benefit": "tous les composants Blade référencent les tokens via Tailwind, jamais hardcoder de hex",
     "ac": [
      {
       "kw": "Given",
       "text": "le fichier <code>resources/css/tokens.css</code>"
      },
      {
       "kw": "When",
       "text": "je l'ouvre"
      },
      {
       "kw": "Then",
       "text": "il contient <code>--bg: #0A0A0B</code>, <code>--surface: #141416</code>, <code>--border: #1F1F22</code>, <code>--text-primary: rgba(255,255,255,.92)</code>, <code>--text-secondary: rgba(255,255,255,.60)</code>, <code>--accent-lava: #FF5722</code>, <code>--state-ok: #22C55E</code>, <code>--state-warn: #F59E0B</code>, <code>--state-err: #EF4444</code>, <code>--font-sans</code>, <code>--font-mono</code>, <code>--leading-prose: 1.7</code>, <code>--max-prose: 720px</code>, <code>--ease-default: cubic-bezier(0.16, 1, 0.3, 1)</code>, <code>--duration-default: 200ms</code>"
      },
      {
       "kw": "And",
       "text": "<code>tailwind.config.js</code> extend theme référence ces variables (ex. <code>colors.bg: 'var(--bg)'</code>, <code>colors.lava: 'var(--accent-lava)'</code>)"
      },
      {
       "kw": "Given",
       "text": "une PR qui introduit <code>bg-[#FF5722]</code> arbitrary class"
      },
      {
       "kw": "When",
       "text": "le reviewer audit"
      },
      {
       "kw": "Then",
       "text": "la PR est refusée — toujours via token (<code>bg-lava</code>)"
      }
     ],
     "notes": [],
     "status": "done"
    },
    {
     "id": "1.9",
     "epic": 1,
     "title": "Self-host IBM Plex Sans + Mono via @fontsource with preload",
     "role": "Caravaggio",
     "want": "IBM Plex Sans (400 + 600 weights) + IBM Plex Mono (400) self-hosted via <code>@fontsource</code>, avec <code>&lt;link rel=\"preload\"&gt;</code> dans <code>&lt;head&gt;</code>",
     "benefit": "FOUT minimisé sur 4G mobile (TTFC &lt;1.5s) + aucun cookie Google Fonts (RGPD)",
     "ac": [
      {
       "kw": "Given",
       "text": "le <code>package.json</code>"
      },
      {
       "kw": "When",
       "text": "je vérifie les dependencies"
      },
      {
       "kw": "Then",
       "text": "<code>@fontsource/ibm-plex-sans</code> et <code>@fontsource/ibm-plex-mono</code> sont installés"
      },
      {
       "kw": "Given",
       "text": "Vite build production"
      },
      {
       "kw": "When",
       "text": "il s'exécute"
      },
      {
       "kw": "Then",
       "text": "3 fichiers <code>woff2</code> (ibm-plex-sans-400, ibm-plex-sans-600, ibm-plex-mono-400) sont copiés dans <code>public/fonts/</code>"
      },
      {
       "kw": "Given",
       "text": "<code>&lt;x-layouts.public&gt;</code> <b>existant (produit par la Story 1.13, qui doit être <code>done</code>)</b>"
      },
      {
       "kw": "When",
       "text": "je l'inspecte"
      },
      {
       "kw": "Then",
       "text": "3 <code>&lt;link rel=\"preload\" href=\"/fonts/...woff2\" as=\"font\" type=\"font/woff2\" crossorigin&gt;</code> sont présents"
      },
      {
       "kw": "And",
       "text": "la CSS <code>@font-face</code> utilise <code>font-display: swap</code>"
      },
      {
       "kw": "Given",
       "text": "une page servie et chargée dans un navigateur réel"
      },
      {
       "kw": "When",
       "text": "je lis <code>getComputedStyle(document.body).fontFamily</code>"
      },
      {
       "kw": "Then",
       "text": "la valeur <b>résolue</b> contient <code>IBM Plex Sans</code>"
      },
      {
       "kw": "And",
       "text": "l'onglet réseau montre les <code>.woff2</code> requêtés depuis le <b>domaine local</b> — aucune requête vers <code>fonts.googleapis.com</code> ni <code>fonts.gstatic.com</code>"
      },
      {
       "kw": "And",
       "text": "casser la source de la police fait <b>échouer</b> ce test (rouge observé, pas supposé)"
      }
     ],
     "notes": [
      "<b>Requalifié 2026-07-30 (<a href=\\\"../../docs/adr/ADR-0011-observation-avant-composition.md\\\">ADR-0011</a>)</b> :",
      "l'AC3 nommait <code>&lt;x-layouts.public&gt;</code>, créé par la Story <b>1.13</b> — AC sans référent, invérifiable,",
      "faux-vert garanti. Cette story passe <b>après</b> la 1.13 et la 1.10a. Deux AC d'observation",
      "navigateur ajoutés : l'ancienne rédaction se satisfaisait de la <i>présence textuelle</i> d'une",
      "chaîne, pas de la valeur <i>calculée</i>.",
      "",
      "<b>Pièges armés pour l'implémentation :</b>",
      "- <code>--font-sans</code> porte le même nom que la variable de thème Tailwind qu'elle alimente → `@theme",
      "inline<code> émet </code>--font-sans: var(--font-sans)<code>. Ça ne tient que parce que </code>tokens.css` est",
      "importé <b>sans <code>layer()</code></b>. Si le spike révèle un ordre de cascade différent de celui supposé,",
      "c'est un <b>bug de la Story 1.8</b> à corriger avant, pas un ajustement de la 1.9.",
      "- <b>Ne JAMAIS passer de message à <code>toContain()</code></b> : il est variadique sur les <i>needles</i>, donc",
      "<code>-&gt;not-&gt;toContain('foo', 'msg')</code> nie « contient foo ET msg » et passe toujours. Deux",
      "garde-fous de la 1.8 sont morts ainsi. Utiliser <code>str_contains()</code> + <code>toBeFalse($message)</code>.",
      "- <code>max-w-prose</code> est <b>banni par un test</b> (built-in Tailwind à 65ch, non surchargeable) — le",
      "token <code>--max-prose</code> s'utilise via <code>max-w-measure</code>.",
      "- Vérifier que l'installation de Filament v5 (1.10a) n'a pas réécrit la configuration Vite",
      "sous les preloads."
     ],
     "status": "done"
    },
    {
     "id": "1.10",
     "epic": 1,
     "title": "Install Filament v3 + Sanctum + Spatie Permission + SettingsResource",
     "role": "Alex-Dev",
     "want": "Filament v3 installé avec Laravel Sanctum + Spatie Permission v7 + une <code>SettingsResource</code> singleton-style éditant les attributs de <code>Streamer</code> via <code>/admin</code>",
     "benefit": "Press Kit Epic 8 et CTAs Epic 5 ont une source de données tenant-aware éditable sans toucher au code",
     "ac": [
      {
       "kw": "Given",
       "text": "un environnement fresh"
      },
      {
       "kw": "When",
       "text": "j'exécute <code>composer require filament/filament:^3.0 laravel/sanctum:^4.0 spatie/laravel-permission:^7.0</code> puis <code>php artisan filament:install --panels</code>"
      },
      {
       "kw": "Then",
       "text": "Filament est installé sur <code>/admin</code>"
      },
      {
       "kw": "Given",
       "text": "Spatie Permission migrations exécutées + role <code>super-admin</code> seeded"
      },
      {
       "kw": "When",
       "text": "je crée un user Alex et lui assigne <code>super-admin</code>"
      },
      {
       "kw": "Then",
       "text": "il peut login sur <code>/admin</code> via Sanctum cookie SPA"
      },
      {
       "kw": "Given",
       "text": "la <code>SettingsResource</code> Filament (singleton-style, édite la seule row <code>Streamer</code>)"
      },
      {
       "kw": "When",
       "text": "Alex modifie <code>tagline</code>, <code>bio_fr</code>, <code>bio_en</code>, <code>photo_url</code>, <code>cta_text</code>, <code>cta_url</code>, <code>twitter_handle</code>, <code>discord_url</code> et clique Save"
      },
      {
       "kw": "Then",
       "text": "la row <code>streamers</code> est mise à jour + toast <code>Notification</code> success affiché"
      },
      {
       "kw": "And",
       "text": "rate limiting login <code>5/min/IP</code> est actif"
      }
     ],
     "notes": [],
     "status": "done"
    },
    {
     "id": "1.11",
     "epic": 1,
     "title": "Create base Blade components (button, card, badge, icon-button, divider, toast)",
     "role": "Sally",
     "want": "6 composants Blade présentationnels base dans <code>resources/views/components/</code>",
     "benefit": "tous les composants UI ultérieurs utilisent des primitives cohérentes (discipline 90/8/2 enforcée via variants)",
     "ac": [
      {
       "kw": "Given",
       "text": "les 6 composants créés"
      },
      {
       "kw": "When",
       "text": "je les inspecte"
      },
      {
       "kw": "Then",
       "text": "<code>&lt;x-button variant=\"primary|secondary|ghost\"&gt;</code> existe avec 6 states (default/hover/active/disabled/loading/focus-visible)"
      },
      {
       "kw": "And",
       "text": "<code>&lt;x-card&gt;</code> a 3 states (default/hover/selected) + slot principal"
      },
      {
       "kw": "And",
       "text": "<code>&lt;x-badge&gt;</code> a 5 variants (neutre/lava/ok/warn/err) — <code>lava</code> réservé LIVE uniquement"
      },
      {
       "kw": "And",
       "text": "<code>&lt;x-icon-button&gt;</code> a <code>aria-label</code> obligatoire via prop (throw exception si manquant) + tooltip natif"
      },
      {
       "kw": "And",
       "text": "<code>&lt;x-divider&gt;</code> a <code>role=\"separator\"</code> + slot optional text"
      },
      {
       "kw": "And",
       "text": "<code>&lt;x-toast&gt;</code> a 4 types (success/error/warning/info) + auto-dismiss 4-6s + <code>role=\"status|alert\"</code> selon type + dismissible"
      },
      {
       "kw": "And",
       "text": "focus-visible ring Lava <code>0.4</code> opacity + <code>outline-offset: 2px</code> sur tous focusables"
      }
     ],
     "notes": [
      "<b>Requalifié 2026-07-30 (passe de relecture des AC)</b> — 4 corrections :",
      "",
      "1. <b>« <code>lava</code> réservé LIVE uniquement » est FAUX</b> et contredit <code>src/resources/css/tokens.css</code>",
      "RÈGLE 2 (livrée par la Story 1.8, <code>done</code> et testée), qui réserve <code>--accent-lava</code> à",
      "<b>exactement 4 usages</b> : badge LIVE · CTA primaires · notes ≥ 9/10 · actions destructives",
      "en admin. <b>Le token fait foi.</b> Lire : « <code>lava</code> réservé aux 4 usages de tokens.css RÈGLE 2 ».",
      "2. <b>L'opacité <code>0.4</code> du focus ring est une valeur en dur</b> — contraire à la RÈGLE 1 de",
      "tokens.css (« aucun composant ne hardcode de couleur »). Soit on ajoute un token",
      "(<code>--focus-ring-alpha</code>), soit on utilise une utility Tailwind dérivée de <code>--color-lava</code>.",
      "À trancher à l'implémentation, mais <b>pas un hex ni une arbitrary value</b>.",
      "3. <b><code>auto-dismiss 4-6s</code> dépend d'Alpine, qui n'est pas une dépendance déclarée</b> (voir le",
      "défaut transverse en tête d'Epic 1). Résoudre la dépendance avant. Et « 4-6 s » est une",
      "plage : l'AC doit nommer l'observable (une valeur par défaut testable + une borne).",
      "",
      "<b>✅ TRANCHÉ PAR LE PO le 2026-08-08 — le toast est SCINDÉ.</b>",
      "Livewire est bien déclaré depuis le 2026-07-31, mais Alpine n'arrive dans le DOM qu'avec",
      "<code>@livewireScripts</code>, câblé par la Story <b>1.13</b>. En 1.11 aucune page ne charge Alpine :",
      "un AC de comportement s'y validerait sans rien exécuter.",
      "<b>1.11 livre la structure</b> (4 types, <code>role=\"status|alert\"</code> selon le type, bouton de",
      "fermeture avec <code>aria-label</code>, durée exposée en prop <b>par défaut <code>5000</code> ms</b> rendue en",
      "attribut de données) — tout est vérifiable par rendu Blade.",
      "<b>1.13 livre le comportement</b> (fermeture effective après la durée, surchargeable),",
      "vérifiable dans un navigateur une fois Alpine chargé.",
      "<code>5000</code> remplace la plage « 4-6 s » : une plage n'est pas un critère.",
      "4. <b>Les « 6 states » / « 3 states »</b> incluent <code>hover</code>, <code>active</code>, <code>focus-visible</code> — des",
      "pseudo-états sans observable nommé. Ils exigent une <b>valeur calculée</b>, donc le runner",
      "navigateur. À défaut, l'AC serait « vérifié » en constatant la présence d'une classe, ce",
      "qui ne prouve rien du rendu."
     ],
     "status": "done"
    },
    {
     "id": "1.12",
     "epic": 1,
     "title": "Create time-as-texture components (4 composants Direction C)",
     "role": "Caravaggio",
     "want": "4 composants Blade time-as-texture utilisant Carbon FR locale",
     "benefit": "la signature visuelle Direction C (\"temps comme texture\") est unifiée et réutilisable partout (LIVE since, Publié X, Streaming depuis)",
     "ac": [
      {
       "kw": "Given",
       "text": "Carbon FR locale configuré (<code>Carbon::setLocale('fr')</code> dans <code>AppServiceProvider::boot</code>)"
      },
      {
       "kw": "When",
       "text": "je rends <code>&lt;x-time-relative :datetime=\"now()-&gt;subHours(3)\" /&gt;</code>"
      },
      {
       "kw": "Then",
       "text": "la sortie HTML est <code>&lt;time datetime=\"2026-05-23T...\"&gt;il y a 3 heures&lt;/time&gt;</code>"
      },
      {
       "kw": "And",
       "text": "<code>&lt;x-time-absolute :datetime=\"$date\" format=\"d M Y\" /&gt;</code> rend <code>&lt;time datetime=\"...\"&gt;14 mars 2026&lt;/time&gt;</code>"
      },
      {
       "kw": "And",
       "text": "<code>&lt;x-time-dual :published=\"$pub\" :updated=\"$upd\" /&gt;</code> rend <code>Publié X · Mis à jour Y</code> uniquement si <code>$upd &gt; $pub-&gt;addDays(30)</code>, sinon <code>Publié X</code> seul"
      },
      {
       "kw": "And",
       "text": "<code>&lt;x-time-since :datetime=\"$start\" /&gt;</code> rend <code>Streaming depuis 4 ans</code>"
      },
      {
       "kw": "And",
       "text": "Alpine.js refresh client-side toutes les 60s pour <code>&lt;x-time-relative&gt;</code> (durées évolutives)"
      },
      {
       "kw": "And",
       "text": "IBM Plex Mono appliqué via class <code>font-mono</code> aux 4 composants"
      }
     ],
     "notes": [
      "<b>Requalifié 2026-07-30 (passe de relecture des AC)</b> — 3 corrections :",
      "",
      "1. <b>⛔ « IBM Plex Mono appliqué » est invérifiable ici.</b> Cette story s'exécute <b>avant</b> la",
      "Story 1.9 (self-host des polices). <code>src/resources/css/tokens.css</code> le dit lui-même :",
      "*« les fichiers woff2 arrivent en Story 1.9. D'ici là le rendu utilise les fallbacks",
      "système : c'est attendu, pas un bug. »* L'AC serait donc validé contre du <b>mono système</b>.",
      "Lire : « la class <code>font-mono</code> est appliquée aux 4 composants, et résout vers <code>--font-mono</code>",
      "(dont la valeur effective sera IBM Plex après la Story 1.9) ». La vérification de la",
      "<b>police réellement rendue</b> appartient à la 1.9, pas ici.",
      "2. <b>⛔ <code>Alpine.js</code> n'est une dépendance déclarée nulle part</b> — ni <code>package.json</code>, ni",
      "<code>composer.json</code>. Il n'est présent que dans le bundle JS de Livewire, lui-même transitif.",
      "Voir le défaut transverse en tête d'Epic 1 : à résoudre <b>avant</b> cette story.",
      "3. <b>Le littéral <code>datetime=\"2026-05-23T...\"</code></b> est hérité de la date de rédaction et ne",
      "correspondra jamais à <code>now()-&gt;subHours(3)</code>. L'AC doit porter sur la <b>forme</b> (attribut",
      "<code>datetime</code> ISO-8601 égal à l'instant passé en prop), pas sur une date gravée.",
      "",
      "<b>Règles typographiques applicables</b> (ADR-0012 §7) : mono <b>≥ 13 px</b>, jamais deux lignes de",
      "mono adjacentes, max 2 occurrences par écran, <code>tracking-tight</code>, couleur secondaire — et",
      "<b>largeur réservée</b> pour que le refresh 60 s ne fasse pas tressauter la page au passage de",
      "« il y a 59 minutes » à « il y a 1 heure »."
     ],
     "status": "done"
    },
    {
     "id": "1.13",
     "epic": 1,
     "title": "Create layouts (<code>&lt;x-layouts.public&gt;</code> + <code>&lt;x-layouts.minimal&gt;</code>)",
     "role": "Sally",
     "want": "2 composants layout Blade",
     "benefit": "toutes les pages partagent header sticky + footer + cookie-gate (public) ou minimal chrome (errors/system)",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>&lt;x-layouts.public&gt;</code>"
      },
      {
       "kw": "When",
       "text": "je l'utilise depuis une page Blade"
      },
      {
       "kw": "Then",
       "text": "la page rend <code>&lt;html lang=\"fr\"&gt;</code> + <code>&lt;head&gt;</code> avec preload fonts + <code>&lt;body&gt;</code> avec skip-to-content link visible au focus uniquement + header sticky 48px mobile / 56px desktop + slot <code>main</code> + footer + cookie consent bandeau bas-droite"
      },
      {
       "kw": "And",
       "text": "<code>&lt;x-layouts.minimal&gt;</code> rend uniquement <code>&lt;html lang=\"fr\"&gt;</code> + <code>&lt;head&gt;</code> minimal + slot <code>main</code> sans header/footer"
      },
      {
       "kw": "And",
       "text": "les deux layouts respectent <code>prefers-reduced-motion: reduce</code> via CSS dédiée"
      },
      {
       "kw": "And",
       "text": "<code>&lt;a href=\"#main\"&gt;Aller au contenu&lt;/a&gt;</code> est premier focusable de <code>&lt;x-layouts.public&gt;</code> avec class <code>sr-only focus:not-sr-only</code>"
      }
     ],
     "notes": [
      "<b>Requalifié 2026-07-30 (passe de relecture des AC)</b> — 3 corrections :",
      "",
      "1. <b>⛔ « <code>&lt;head&gt;</code> avec preload fonts » est sans référent ici.</b> Les preloads sont produits par",
      "la Story <b>1.9</b>, qui s'exécute <b>après</b>. C'est le <b>miroir exact</b> du défaut qui a motivé",
      "<a href=\\\"../../docs/adr/ADR-0011-observation-avant-composition.md\\\">ADR-0011</a> — la dépendance",
      "circulaire s'est retournée. Elle est cette fois <b>inoffensive</b> : un layout peut naître sans",
      "preload et les recevoir ensuite. Mais l'AC doit le dire. Lire : « le <code>&lt;head&gt;</code> expose un",
      "point d'insertion pour les preload fonts, <b>renseigné par la Story 1.9</b> ». Ne pas",
      "l'affirmer présent ici, sinon l'AC se valide sur un <code>&lt;head&gt;</code> vide.",
      "2. <b>⛔ « cookie consent bandeau bas-droite » appartient à l'Epic 4.</b> Rien ne le produit à ce",
      "stade. Même traitement : le layout expose l'emplacement, l'Epic 4 le remplit. Sans ça, on",
      "livrerait un bandeau factice — un échafaudage <i>plus permissif</i> que la production, exactement",
      "ce que l'ADR-0011 refuse.",
      "3. <b>« header sticky 48 px mobile / 56 px desktop » et <code>prefers-reduced-motion</code></b> sont des",
      "<b>valeurs calculées</b> : elles exigent le runner navigateur. Ni la présence d'une classe ni",
      "la présence d'une règle CSS dans le fichier source ne prouvent la hauteur rendue.",
      "",
      "<b>Note de séquence</b> : 4 des 5 AC de cette story dépendent du spike. Ce n'est pas la Story 1.9",
      "seule qui l'attend — c'est la moitié du reliquat d'Epic 1.",
      "",
      "### ➕ AC ajouté le 2026-08-08 — le comportement de <code>&lt;x-toast&gt;</code> atterrit ici",
      "",
      "<b>Arbitrage PO</b> : la Story 1.11 livre la <i>structure</i> du toast, cette story livre son",
      "<i>comportement</i>. Motif : l'auto-fermeture exige Alpine, qui n'entre dans le DOM qu'avec",
      "<code>@livewireScripts</code> — câblé par CE layout. En 1.11, un AC de comportement se serait validé sans",
      "rien exécuter.",
      "",
      "<b>Given</b> <code>&lt;x-layouts.public&gt;</code> charge <code>@livewireScripts</code> (donc Alpine)",
      "<b>When</b> un <code>&lt;x-toast&gt;</code> est rendu dans le slot <code>main</code>",
      "<b>Then</b> il se ferme seul après la durée exposée par sa prop, <b><code>5000</code> ms par défaut</b>",
      "<b>And</b> une durée surchargée est respectée",
      "<b>And</b> le bouton de fermeture le ferme immédiatement, sans attendre la durée",
      "",
      "⚠️ Ces AC exigent le <b>runner navigateur</b> (valeur observée dans le temps, pas présence d'une",
      "classe). Et ils ne sont vérifiables que depuis une page qui utilise réellement le layout —",
      "c'est précisément ce qui les rend légitimes ici et illégitimes en 1.11.",
      "",
      "⚠️ <b>Ne PAS ajouter <code>alpinejs</code> via npm</b> : Livewire 4 l'embarque. Deux Alpine enregistrés en",
      "parallèle est un bug classique."
     ],
     "status": "done"
    }
   ]
  },
  {
   "num": 2,
   "title": "Installer & Quality Gates (Fork-Streamer Path)",
   "phase": "Phase 1 ~10j",
   "pitch": "Fork-streamer installe le skeleton sur VPS vierge en &lt;15min via <code>make install-dev-full</code> (Bats E2E nightly bloquant) ; Alex a gates CI <b>progressifs L5→L8</b> depuis S1 (PHPStan, ECS, Pest unit) qui catchent régressions sans dette accumulée S6.",
   "meta": {
    "FRs covered": "FR-Install-1 à 7, FR-CI-1 à 5, FR-CI-7, FR-CI-8 (FR-CI-6 Pest OWASP déplacé Epic 4/5/9)",
    "NFRs critical": "NFR-Sec-1 (Gitleaks bloquant prod #1), NFR-Sec-5 (Bats nightly bloquant prod #4 — split avec Epic 11)"
   },
   "amendments": [
    "<b>Pest OWASP A01-A04 DÉPLACÉ Phase 3/S1+S2</b> (Murat : prématuré Phase 1, A01 = Filament policies = Epic 5)",
    "<b>Gates PHPStan progressifs L5→L8</b> sprint par sprint (Winston : sinon dette 8000 erreurs S6)",
    "Lighthouse-CI dès S1, pas seulement S6 (Amelia)",
    "Profiles Docker re-découpés prod/dev/dev-tools/ops (Winston R1)"
   ],
   "effort": "10j",
   "status": "in-progress",
   "retro": "optional",
   "stories": [
    {
     "id": "2.1",
     "epic": 2,
     "title": "Refactor <code>scripts/lib/common.sh</code> (DRY shared lib)",
     "role": "Amelia",
     "want": "un fichier <code>scripts/lib/common.sh</code> centralisant <code>die()</code>, <code>retry()</code>, <code>require_cmd()</code>, <code>ensure_idempotent()</code>, <code>trap 'die' ERR</code>",
     "benefit": "tous les scripts d'install partagent les primitives shell sans duplication",
     "ac": [
      {
       "kw": "Given",
       "text": "un script <code>scripts/install/01-docker.sh</code> source <code>common.sh</code>"
      },
      {
       "kw": "When",
       "text": "une commande dans le script échoue"
      },
      {
       "kw": "Then",
       "text": "<code>trap ERR</code> déclenche <code>die \"step 01-docker failed at line X\"</code> avec exit code 1"
      },
      {
       "kw": "And",
       "text": "<code>retry mvn test 3</code> retry 3 fois avec backoff exponentiel"
      },
      {
       "kw": "And",
       "text": "<code>require_cmd docker</code> exit 1 explicite si binaire manquant"
      },
      {
       "kw": "And",
       "text": "<code>ensure_idempotent .install-state/01-docker-done &lt;command&gt;</code> skip si sentinel existe"
      }
     ],
     "notes": [],
     "status": "done"
    },
    {
     "id": "2.2",
     "epic": 2,
     "title": "Idempotent install with sentinel + lockfile",
     "role": "Fork-Streamer",
     "want": "<code>make install-dev-full</code> qui crée des sentinels <code>.install-state/&lt;step&gt;-done</code> + un lockfile <code>.install-state/lock.yml</code> en fin",
     "benefit": "un install interrompu peut reprendre où il s'est arrêté",
     "ac": [
      {
       "kw": "Given",
       "text": "install qui crash au module 07"
      },
      {
       "kw": "When",
       "text": "je relance <code>make install-dev-full</code>"
      },
      {
       "kw": "Then",
       "text": "les sentinels 00-06 sont détectés et skippés"
      },
      {
       "kw": "And",
       "text": "l'install reprend au module 07"
      },
      {
       "kw": "Given",
       "text": "install complet"
      },
      {
       "kw": "When",
       "text": "il termine"
      },
      {
       "kw": "Then",
       "text": "<code>.install-state/lock.yml</code> contient <code>composer.lock sha256</code>, <code>php -v</code>, <code>node -v</code>, timestamp"
      }
     ],
     "notes": [],
     "status": "done"
    },
    {
     "id": "2.3",
     "epic": 2,
     "title": "Implement <code>--dry-run</code> and <code>--resume-from</code> flags",
     "role": "Fork-Streamer",
     "want": "flags <code>--dry-run</code> et <code>--resume-from=&lt;step&gt;</code> sur tous les scripts d'install",
     "benefit": "je peux tester l'install sans effets de bord et reprendre depuis un step",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>make install-dev-full DRY_RUN=true</code>"
      },
      {
       "kw": "When",
       "text": "les scripts s'exécutent"
      },
      {
       "kw": "Then",
       "text": "<code>run_cmd()</code> n'exécute rien, juste affiche <code>[DRY] $cmd</code>"
      },
      {
       "kw": "And",
       "text": "aucun fichier créé, aucun container démarré"
      },
      {
       "kw": "Given",
       "text": "<code>make install-dev-full RESUME_FROM=05-laravel</code>"
      },
      {
       "kw": "When",
       "text": "la commande démarre"
      },
      {
       "kw": "Then",
       "text": "modules 00-04 skippés, install reprend au 05"
      }
     ],
     "notes": [],
     "status": "done"
    },
    {
     "id": "2.4",
     "epic": 2,
     "title": "Bats E2E install test (nightly bloquant)",
     "role": "Murat",
     "want": "<code>tests/bats/install.bats</code> qui lance <code>make install-dev-full</code> dans un container éphémère + assert <code>/health</code> 200 OK",
     "benefit": "le 4ᵉ bloquant prod (Bats smoke installer nightly) est actif",
     "ac": [
      {
       "kw": "Given",
       "text": "GitHub Actions workflow <code>.github/workflows/nightly.yml</code>"
      },
      {
       "kw": "When",
       "text": "il s'exécute chaque nuit"
      },
      {
       "kw": "Then",
       "text": "il <code>docker run</code> une image Ubuntu 24.04 vierge + <code>bats tests/install.bats</code>"
      },
      {
       "kw": "And",
       "text": "le test clone le repo + exécute <code>make install-dev-full</code> + curl <code>localhost/health</code>"
      },
      {
       "kw": "And",
       "text": "assert <code>/health</code> retourne <code>200</code> + JSON contenant <code>\"database\": \"ok\"</code>, <code>\"cache\": \"ok\"</code>, <code>\"queue\": \"ok\"</code>"
      },
      {
       "kw": "And",
       "text": "temps total &lt;15min (sinon fail)"
      }
     ],
     "notes": [],
     "status": "review"
    },
    {
     "id": "2.5",
     "epic": 2,
     "title": "Versioned quality templates (php.ini, vhost.conf)",
     "role": "Winston",
     "want": "des gabarits de configuration versionnés, rendus au démarrage depuis l'environnement",
     "benefit": "un fork-streamer règle PHP et Apache par variables d'environnement, sans éditer ni Dockerfile ni fichier de configuration",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>docker/php/conf/php.ini.template</code> versionné"
      },
      {
       "kw": "When",
       "text": "le conteneur <code>php</code> démarre"
      },
      {
       "kw": "Then",
       "text": "il est rendu vers <code>/usr/local/etc/php/conf.d/99-fork.ini</code> — dernier dans l'ordre alphabétique du scan <code>conf.d</code>, donc prioritaire sur <code>composer-optimizations.ini</code>"
      },
      {
       "kw": "And",
       "text": "<b>jamais</b> vers <code>/usr/local/etc/php/php.ini</code>, qui est un bind-mount <b>RW</b> du fichier versionné (<code>docker-compose.yml:44</code>, et <code>:118</code> pour <code>test-browser</code>) : y écrire réécrirait <code>docker/php/conf/php.ini</code> sur l'hôte à chaque démarrage"
      },
      {
       "kw": "And",
       "text": "le mécanisme est identique en <code>development</code> et en <code>production</code> (le stage <code>development</code> descend de <code>production</code>) — seule la limite CLI diffère"
      },
      {
       "kw": "Given",
       "text": "<code>PHP_MEMORY_LIMIT</code> non défini"
      },
      {
       "kw": "When",
       "text": "le conteneur démarre"
      },
      {
       "kw": "Then",
       "text": "le pool FPM applique <code>php_admin_value[memory_limit] = 256M</code> — une requête qui dérape meurt à la borne, avec une trace qui nomme le coupable"
      },
      {
       "kw": "And",
       "text": "le CLI conserve sa limite haute (<code>4G</code> en <code>development</code>), dont dépendent <code>composer install</code>, PHPStan niveau 8 et la campagne de mutation"
      },
      {
       "kw": "Given",
       "text": "<code>PHP_MEMORY_LIMIT=512M</code> dans le <code>.env</code> <b>de la racine du dépôt</b> — celui que lit Docker Compose, <b>pas</b> <code>src/.env</code> qui est celui de Laravel"
      },
      {
       "kw": "And",
       "text": "la variable déclarée dans <code>environment:</code>/<code>env_file:</code> du service <code>php</code> — sans quoi Compose ne l'injecte pas dans le conteneur, quelle que soit sa présence dans <code>.env</code>"
      },
      {
       "kw": "When",
       "text": "le conteneur démarre"
      },
      {
       "kw": "Then",
       "text": "<code>php -r 'echo ini_get(\"memory_limit\");'</code> rend <code>512M</code>"
      },
      {
       "kw": "And",
       "text": "le test assert la <b>valeur effective</b>, jamais le contenu du fichier rendu — un fichier correct dans un répertoire qui perd est exactement le défaut que cette story corrige"
      },
      {
       "kw": "And",
       "text": "<code>PHP_MEMORY_LIMIT</code> est documentée dans <code>.env.example</code> racine, qui ne contient aujourd'hui aucune variable <code>PHP_*</code>"
      },
      {
       "kw": "Given",
       "text": "une variable référencée par un gabarit mais absente de l'environnement"
      },
      {
       "kw": "When",
       "text": "le rendu s'exécute"
      },
      {
       "kw": "Then",
       "text": "la valeur par défaut du gabarit s'applique, et le rendu ne produit jamais une directive à valeur vide"
      },
      {
       "kw": "And",
       "text": "<code>envsubst</code> est invoqué avec sa <b>liste d'autorisation</b> (<code>envsubst '$PHP_MEMORY_LIMIT $PHP_MAX_EXECUTION_TIME' &lt; tpl &gt; cible</code>), pour qu'aucun autre <code>$MOT</code> du fichier ne soit substitué"
      },
      {
       "kw": "Given",
       "text": "les images <code>php</code> et <code>apache</code>"
      },
      {
       "kw": "When",
       "text": "on y exécute <code>envsubst --version</code>"
      },
      {
       "kw": "Then",
       "text": "la commande répond"
      },
      {
       "kw": "Given",
       "text": "<code>docker/apache/conf/sites-enabled/laravel.conf.template</code> versionné"
      },
      {
       "kw": "When",
       "text": "le conteneur <code>apache</code> démarre"
      },
      {
       "kw": "Then",
       "text": "le rendu produit <code>/etc/apache2/sites-enabled/laravel.conf</code> — chemin exigé littéralement par <code>docker/apache/scripts/docker-entrypoint.sh:41</code>, qui sort en <code>1</code> s'il est absent"
      },
      {
       "kw": "And",
       "text": "le rendu passe par un fichier temporaire validé par <code>httpd -t</code> <b>avant</b> d'écraser la cible : un vhost invalide ne doit pas détruire le vhost qui marchait"
      },
      {
       "kw": "Given",
       "text": "un conteneur déjà démarré une fois"
      },
      {
       "kw": "When",
       "text": "il redémarre"
      },
      {
       "kw": "Then",
       "text": "le rendu produit un fichier identique"
      },
      {
       "kw": "And",
       "text": "gabarit et cible ne sont jamais le même chemin — sinon le gabarit est écrasé par sa propre sortie au 2ᵉ démarrage"
      },
      {
       "kw": "Given",
       "text": "<code>docker/php/conf/opcache.ini</code>, <code>docker/php/conf/xdebug.ini</code>, <code>docker/postgres/conf.d</code>, <code>docker/supervisor/conf.d</code>"
      },
      {
       "kw": "Then",
       "text": "ils restent <b>hors périmètre</b> de cette story, et c'est écrit ici"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "2.6",
     "epic": 2,
     "title": "Gitleaks pre-commit hook + CI (bloquant prod #1)",
     "role": "Murat",
     "want": "Gitleaks pre-commit hook + GitHub Actions step <code>gitleaks detect --no-git</code>",
     "benefit": "le 1ᵉʳ bloquant prod (Gitleaks) est actif et empêche tout secret leak",
     "ac": [
      {
       "kw": "Given",
       "text": "le hook <code>.husky/pre-commit</code> configuré"
      },
      {
       "kw": "When",
       "text": "je tente <code>git commit</code> avec un fichier contenant <code>AWS_SECRET_KEY=AKIA...</code>"
      },
      {
       "kw": "Then",
       "text": "le commit est refusé avec message Gitleaks explicite"
      },
      {
       "kw": "Given",
       "text": "workflow GitHub Actions step <code>gitleaks-scan</code>"
      },
      {
       "kw": "When",
       "text": "il s'exécute sur push/PR"
      },
      {
       "kw": "Then",
       "text": "<code>gitleaks detect --source . --no-git</code> retourne 0 (zéro secret détecté)"
      },
      {
       "kw": "And",
       "text": "workflow fail si secret détecté (bloquant CI)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "2.7",
     "epic": 2,
     "title": "GitHub Actions wrappers provider-agnostic (<code>scripts/ci/*.sh</code>)",
     "role": "Winston",
     "want": "wrappers shell <code>scripts/ci/{test,lint,deploy,quality}.sh</code> + workflows YAML 30 lignes max",
     "benefit": "passage GitHub → GitLab → autre provider = juste changer le YAML wrapper",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>scripts/ci/test.sh</code> qui exécute <code>vendor/bin/pest --parallel --coverage</code>"
      },
      {
       "kw": "When",
       "text": "le workflow <code>.github/workflows/test.yml</code> s'exécute"
      },
      {
       "kw": "Then",
       "text": "il appelle uniquement <code>./scripts/ci/test.sh</code>"
      },
      {
       "kw": "And",
       "text": "<code>scripts/ci/lint.sh</code> exécute <code>ecs check</code> + <code>phpstan analyse</code>"
      },
      {
       "kw": "And",
       "text": "<code>scripts/ci/quality.sh</code> orchestre lint + test + drift + rector dry-run"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "2.8",
     "epic": 2,
     "title": "CI matrix PHP 8.4 + 8.5.1 × Postgres 17",
     "role": "Murat",
     "want": "matrice CI <code>php: [8.4, 8.5.1]</code> × <code>postgres: [17]</code>",
     "benefit": "toute incompatibilité PHP 8.5.1 est détectée avant prod",
     "ac": [
      {
       "kw": "Given",
       "text": "workflow avec <code>strategy.matrix.php: [8.4, 8.5.1]</code>"
      },
      {
       "kw": "When",
       "text": "il s'exécute sur PR"
      },
      {
       "kw": "Then",
       "text": "2 jobs parallèles tournent (un par version PHP)"
      },
      {
       "kw": "And",
       "text": "chaque job utilise <code>services.postgres: postgres:17-alpine</code>"
      },
      {
       "kw": "And",
       "text": "la PR ne peut merger que si les 2 jobs passent"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "2.9",
     "epic": 2,
     "title": "Pre-commit hook séquentiel (Gitleaks → ECS → PHPStan L5 → Pest)",
     "role": "Murat",
     "want": "pre-commit hook qui exécute en séquence : Gitleaks → ECS --fix → PHPStan level <b>5</b> → Pest --parallel sur unit tests",
     "benefit": "les régressions sont catchées avant push",
     "ac": [
      {
       "kw": "Given",
       "text": "le hook <code>.husky/pre-commit</code>"
      },
      {
       "kw": "When",
       "text": "je <code>git commit</code>"
      },
      {
       "kw": "Then",
       "text": "les 4 étapes s'exécutent en séquence"
      },
      {
       "kw": "And",
       "text": "si une étape fail, le commit est refusé"
      },
      {
       "kw": "And",
       "text": "ECS auto-fixe et stage les fichiers modifiés"
      },
      {
       "kw": "And",
       "text": "PHPStan tourne au niveau initial L5 (pas L8 dès J1)"
      },
      {
       "kw": "And",
       "text": "Pest tourne uniquement <code>tests/Unit/</code> (&lt;30s)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "2.10",
     "epic": 2,
     "title": "Progressive PHPStan levels (L5→L8) sprint by sprint",
     "role": "Winston",
     "want": "<code>phpstan.neon</code> configuré au niveau <b>L5</b> au démarrage avec plan documenté L5→L6→L7→L8 sprint par sprint",
     "benefit": "la dette PHPStan ne s'accumule pas",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>phpstan.neon</code> au démarrage"
      },
      {
       "kw": "When",
       "text": "je consulte <code>level</code>"
      },
      {
       "kw": "Then",
       "text": "il est à <b>5</b> (pas 8)"
      },
      {
       "kw": "Given",
       "text": "doc <code>docs/process/phpstan-progression.md</code>"
      },
      {
       "kw": "When",
       "text": "je la lis"
      },
      {
       "kw": "Then",
       "text": "elle documente : Epic 2 = L5, Epic 4 = L6, Epic 7 = L7, Epic 10 = L8 zéro erreur"
      },
      {
       "kw": "And",
       "text": "chaque PR qui monte le niveau doit baseline = 0 erreurs"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "2.11",
     "epic": 2,
     "title": "axe-core CLI + Lighthouse mobile in CI",
     "role": "Murat",
     "want": "axe-core CLI + Lighthouse-CI workflow scannant home + 1 slug review + /press",
     "benefit": "les régressions a11y sont catchées dès S1",
     "ac": [
      {
       "kw": "Given",
       "text": "workflow <code>.github/workflows/a11y.yml</code>"
      },
      {
       "kw": "When",
       "text": "il s'exécute sur PR"
      },
      {
       "kw": "Then",
       "text": "<code>npx @axe-core/cli http://localhost:8080/</code> retourne 0 violation AA"
      },
      {
       "kw": "And",
       "text": "Lighthouse mobile sur les 3 URLs retourne accessibility ≥95"
      },
      {
       "kw": "And",
       "text": "workflow fail si threshold pas atteint (bloquant à partir d'Epic 4)"
      },
      {
       "kw": "And",
       "text": "SEO ≥95, perf ≥85, best-practices ≥90 vérifiés en informatif S1, bloquant S6"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "2.12",
     "epic": 2,
     "title": "Snyk security scan weekly (informatif)",
     "role": "Murat",
     "want": "workflow <code>snyk.yml</code> schedulé hebdomadaire qui scan PHP + Node dependencies",
     "benefit": "les CVE HIGH/CRITICAL sont alertées sans bloquer le développement",
     "ac": [
      {
       "kw": "Given",
       "text": "workflow <code>snyk.yml</code> schedulé <code>cron: '0 9 <i> </i> 1'</code>"
      },
      {
       "kw": "When",
       "text": "il s'exécute"
      },
      {
       "kw": "Then",
       "text": "<code>snyk test --severity-threshold=high</code> sur <code>composer.lock</code> et <code>package-lock.json</code>"
      },
      {
       "kw": "And",
       "text": "si nouvelle vuln HIGH/CRITICAL détectée → notification Discord + GitHub issue auto"
      },
      {
       "kw": "And",
       "text": "workflow ne fail jamais (informatif)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "2.13",
     "epic": 2,
     "title": "Mozilla Observatory CLI staging gate A",
     "role": "Murat",
     "want": "un step CI qui lance Mozilla Observatory contre staging et exige grade A minimum",
     "benefit": "les headers de sécurité sont vérifiés avant prod",
     "ac": [
      {
       "kw": "Given",
       "text": "workflow <code>staging-deploy.yml</code> step \"observatory-scan\""
      },
      {
       "kw": "When",
       "text": "il s'exécute après déploiement staging"
      },
      {
       "kw": "Then",
       "text": "<code>observatory-cli staging.skeleton-streamer.dev --format=json | jq .grade</code> retourne <code>\"A\"</code> ou meilleur"
      },
      {
       "kw": "And",
       "text": "workflow fail si grade &lt; A (bloquant promotion staging→prod)"
      },
      {
       "kw": "And",
       "text": "rapport scan archivé en artifact"
      }
     ],
     "notes": [],
     "status": "backlog"
    }
   ]
  },
  {
   "num": 3,
   "title": "Observability & Backups (Alex Operates)",
   "phase": "Phase 2/S0 ~6j",
   "pitch": "Alex déploie en prod confiant — Sentry catche erreurs externes, Pulse monitore temps réel (DB isolée <code>postgres-pulse</code> ADR-0004), Spatie Health + Uptime-Kuma alertent Discord en cas panne, backups locaux quotidiens préservent les articles, secrets via <code>env:encrypt</code> natif (ADR-0006).",
   "meta": {
    "FRs covered": "FR-Obs-1 à 6, FR-Backup-1 à 4, FR-Sec-2 à 7 (FR-Sec-1 Cookie consent déplacé Epic 4)",
    "NFRs critical": "NFR-Monit-1 à 5, NFR-Backup-1 à 3, NFR-Risk-5/6"
   },
   "amendments": [
    "Health check <code>BackupOffsiteCheck</code> WARN si <code>BACKUP_OFFSITE_ENABLED=false</code> en prod (Winston : risque §12.6)",
    "Commande artisan <code>pennant:prune</code> schedulée mensuellement (Winston : risque §12.7)",
    "Spatie Health DiskSpace explicite sur volume <code>postgres-pulse</code> (Winston : risque §12.4)"
   ],
   "effort": "6j",
   "status": "backlog",
   "retro": "optional",
   "stories": [
    {
     "id": "3.1",
     "epic": 3,
     "title": "Install Sentry SDK + DSN env + Laravel breadcrumbs",
     "role": "Alex-Auteur",
     "want": "Sentry SDK installé avec DSN dans <code>.env</code> + breadcrumbs Laravel auto-attachés",
     "benefit": "toute exception non-catchée en prod est remontée externes (free tier 5k events/mois)",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>composer require sentry/sentry-laravel</code> + <code>SENTRY_LARAVEL_DSN</code> dans <code>.env.production.encrypted</code>"
      },
      {
       "kw": "When",
       "text": "une exception non-catchée se produit en prod"
      },
      {
       "kw": "Then",
       "text": "elle est envoyée à Sentry avec breadcrumbs (request, route, user_id si auth)"
      },
      {
       "kw": "And",
       "text": "sampling rate <code>SENTRY_TRACES_SAMPLE_RATE=0.1</code> configuré (10% pour rester sous free tier)"
      },
      {
       "kw": "And",
       "text": "environnement (<code>dev/staging/prod</code>) tagué dans chaque event"
      },
      {
       "kw": "And",
       "text": "secrets/PII filtrés via <code>before_send</code> callback (pas de tokens/emails dans payload)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "3.2",
     "epic": 3,
     "title": "Install Pulse on dedicated <code>postgres-pulse</code> DB",
     "role": "Winston",
     "want": "Laravel Pulse installé avec connexion vers DB séparée <code>postgres-pulse</code>",
     "benefit": "ADR-0004 est respecté — pas de contention I/O entre Pulse et DB applicative",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>docker-compose.yml</code> avec service <code>postgres-pulse</code> (image postgres:17-alpine, volume nommé, network internal)"
      },
      {
       "kw": "When",
       "text": "je lance <code>docker compose up postgres-pulse</code>"
      },
      {
       "kw": "Then",
       "text": "le container démarre et <code>pg_isready</code> retourne success"
      },
      {
       "kw": "Given",
       "text": "<code>config/database.php</code> avec connexion <code>pgsql_pulse</code> + <code>config/pulse.php</code> storage driver database connection pgsql_pulse"
      },
      {
       "kw": "When",
       "text": "Pulse écrit des snapshots"
      },
      {
       "kw": "Then",
       "text": "ils vont dans la DB <code>pulse</code>, pas la DB applicative"
      },
      {
       "kw": "And",
       "text": "<code>php artisan migrate --database=pgsql_pulse</code> exécute migrations Pulse uniquement sur cette DB"
      },
      {
       "kw": "And",
       "text": "<code>/pulse</code> route accessible admin-only via Sanctum + middleware <code>super-admin</code>"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "3.3",
     "epic": 3,
     "title": "Register Spatie Health checks",
     "role": "Murat",
     "want": "6 health checks Spatie registrés dans <code>app/Providers/HealthServiceProvider.php</code>",
     "benefit": "<code>/health</code> JSON expose l'état des sous-systèmes critiques",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>HealthServiceProvider</code> registre les checks"
      },
      {
       "kw": "When",
       "text": "<code>curl /health</code> exécuté"
      },
      {
       "kw": "Then",
       "text": "réponse JSON contient <code>database</code>, <code>cache</code>, <code>queue</code>, <code>disk_space</code> (&gt;15% libre), <code>opcache_memory</code>, <code>https_certificate_expiry</code> (&gt;14 jours)"
      },
      {
       "kw": "And",
       "text": "chaque check retourne <code>\"ok\" | \"warn\" | \"fail\"</code> + message explicite"
      },
      {
       "kw": "And",
       "text": "HTTP status <code>200</code> si tous OK, <code>503</code> si au moins un fail"
      },
      {
       "kw": "And",
       "text": "check <code>BackupOffsiteCheck</code> ajouté (cf. Story 3.8)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "3.4",
     "epic": 3,
     "title": "Uptime-Kuma container + monitor <code>/health</code> + Discord alerts",
     "role": "Alex-Auteur",
     "want": "Uptime-Kuma container externe qui monitore <code>/health</code> toutes les 60s + alert Discord webhook si fail",
     "benefit": "je suis alerté hors-bande même si tout le stack app est down",
     "ac": [
      {
       "kw": "Given",
       "text": "Uptime-Kuma déployé sur sous-domaine séparé (<code>monitor.skeleton-streamer.dev</code>)"
      },
      {
       "kw": "When",
       "text": "il monitore <code>https://skeleton-streamer.dev/health</code>"
      },
      {
       "kw": "Then",
       "text": "check toutes les 60s, alert Discord webhook si HTTP status ≠ 200 ou si JSON <code>database/cache/queue</code> contient <code>fail</code>"
      },
      {
       "kw": "And",
       "text": "un dashboard public en lecture seule pour transparence"
      },
      {
       "kw": "And",
       "text": "ce monitoring est <i>cuttable v1</i> si glissement (cf. Epic 11)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "3.5",
     "epic": 3,
     "title": "Spatie Schedule Monitor for cron jobs",
     "role": "Murat",
     "want": "Spatie Schedule Monitor v4 installé pour surveiller tous les cron jobs",
     "benefit": "un cron silencieusement cassé déclenche un alert plutôt qu'une dégradation silencieuse",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>composer require spatie/laravel-schedule-monitor</code> + migration <code>monitored_scheduled_tasks</code>"
      },
      {
       "kw": "When",
       "text": "j'ajoute <code>-&gt;monitorName('backup-local')</code> à un Schedule"
      },
      {
       "kw": "Then",
       "text": "chaque exécution est tracée en DB avec start_time, end_time, exit_code"
      },
      {
       "kw": "And",
       "text": "si un cron ne tourne pas dans son créneau attendu, un check Health <code>ScheduleMonitorCheck</code> fail"
      },
      {
       "kw": "And",
       "text": "Sentry est notifié si un cron fail 3 fois consécutivement"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "3.6",
     "epic": 3,
     "title": "<code>scripts/ops/backup-local.sh</code> daily cron",
     "role": "Alex-Auteur",
     "want": "<code>scripts/ops/backup-local.sh</code> qui dump Postgres app quotidiennement à 03:00 vers <code>/var/backups/postgres/</code> avec rotation 14j",
     "benefit": "ADR-0003 backup local est actif et un incident applicatif est récupérable",
     "ac": [
      {
       "kw": "Given",
       "text": "le script <code>scripts/ops/backup-local.sh</code> exécutable"
      },
      {
       "kw": "When",
       "text": "cron <code>0 3 <i> </i> * /opt/skeleton/scripts/ops/backup-local.sh</code> tourne"
      },
      {
       "kw": "Then",
       "text": "<code>pg_dump --no-owner skeleton_app | gzip -9 &gt; /var/backups/postgres/backup-$(date +%Y-%m-%d).sql.gz</code>"
      },
      {
       "kw": "And",
       "text": "rotation 14 jours (suppression du plus ancien si &gt;14 fichiers)"
      },
      {
       "kw": "And",
       "text": "<b>exclusion explicite</b> de la DB <code>pulse</code> (pas dans le dump)"
      },
      {
       "kw": "And",
       "text": "test Bats <code>tests/bats/backup-local.bats</code> vérifie integrity via <code>pg_restore --list</code>"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "3.7",
     "epic": 3,
     "title": "<code>scripts/ops/backup-offsite.sh</code> hands-off (disabled by default)",
     "role": "Alex-Auteur",
     "want": "<code>scripts/ops/backup-offsite.sh</code> désactivé par défaut (<code>BACKUP_OFFSITE_ENABLED=false</code>) mais activable en 5 min via rclone",
     "benefit": "ADR-0003 couche 2 est prête sans coût mais activable au signal",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>.env.example</code> avec <code>BACKUP_OFFSITE_ENABLED=false</code> + <code>BACKUP_OFFSITE_RCLONE_REMOTE=</code>"
      },
      {
       "kw": "When",
       "text": "je laisse les valeurs par défaut"
      },
      {
       "kw": "Then",
       "text": "le script <code>backup-offsite.sh</code> exit 0 sans rien faire"
      },
      {
       "kw": "Given",
       "text": "je configure <code>BACKUP_OFFSITE_ENABLED=true</code> + <code>BACKUP_OFFSITE_RCLONE_REMOTE=mega:streamer-backup</code> + <code>rclone config</code> one-time"
      },
      {
       "kw": "When",
       "text": "cron exécute <code>backup-offsite.sh</code> post backup-local"
      },
      {
       "kw": "Then",
       "text": "<code>rclone copy /var/backups/postgres/ ${BACKUP_OFFSITE_RCLONE_REMOTE}/ --max-age 30d</code>"
      },
      {
       "kw": "And",
       "text": "rotation 30 jours sur le remote"
      },
      {
       "kw": "And",
       "text": "doc <code>docs/process/06-backup-offsite-activation.md</code> explique le 5-min activation"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "3.8",
     "epic": 3,
     "title": "Health check <code>BackupOffsiteCheck</code> WARN if disabled in prod",
     "role": "Winston",
     "want": "un Spatie Health check custom <code>BackupOffsiteCheck</code> qui retourne WARN si <code>BACKUP_OFFSITE_ENABLED=false</code> en prod",
     "benefit": "le risque archi §12.6 est tracké automatiquement",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>app/Core/HealthChecks/BackupOffsiteCheck.php</code>"
      },
      {
       "kw": "When",
       "text": "l'environnement est <code>prod</code> et <code>BACKUP_OFFSITE_ENABLED=false</code>"
      },
      {
       "kw": "Then",
       "text": "le check retourne status <code>warn</code> avec message \"Offsite backup disabled — UPGRADE BEFORE HOSTING THIRD-PARTY DATA (ADR-0003)\""
      },
      {
       "kw": "Given",
       "text": "environnement <code>dev</code> ou <code>staging</code>"
      },
      {
       "kw": "When",
       "text": "la même condition"
      },
      {
       "kw": "Then",
       "text": "check retourne status <code>ok</code> (pas de warn en non-prod)"
      },
      {
       "kw": "Given",
       "text": "<code>BACKUP_OFFSITE_ENABLED=true</code> + dernier backup remote détecté &lt;48h"
      },
      {
       "kw": "When",
       "text": "le check tourne"
      },
      {
       "kw": "Then",
       "text": "status <code>ok</code> + message timestamp dernier upload remote"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "3.9",
     "epic": 3,
     "title": "<code>pennant:prune</code> scheduled monthly",
     "role": "Winston",
     "want": "commande artisan <code>pennant:prune</code> schedulée mensuellement",
     "benefit": "le risque archi §12.7 (Pennant tables grossissent) est mitigé par rotation automatique",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>app/Console/Kernel.php</code> <code>schedule()</code>"
      },
      {
       "kw": "When",
       "text": "je vois la déclaration"
      },
      {
       "kw": "Then",
       "text": "elle contient <code>$schedule-&gt;command('pennant:prune --older-than=90')-&gt;monthly()-&gt;onOneServer()-&gt;monitorName('pennant-prune')</code>"
      },
      {
       "kw": "And",
       "text": "la commande native Pennant supprime les rows <code>features</code> non-utilisés depuis &gt;90 jours"
      },
      {
       "kw": "And",
       "text": "test Pest vérifie qu'après seed de 20 features dont 5 stales &gt;90j, <code>pennant:prune --older-than=90</code> les supprime"
      },
      {
       "kw": "And",
       "text": "Schedule Monitor track cette commande"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "3.10",
     "epic": 3,
     "title": "VPS hardening (SSH key-only + UFW + fail2ban)",
     "role": "Murat",
     "want": "VPS hardening : SSH <code>PasswordAuthentication no</code>, UFW ouvert sur 22/80/443, fail2ban actif",
     "benefit": "l'infra serveur est durcie par défaut (PRD §7.4)",
     "ac": [
      {
       "kw": "Given",
       "text": "un script <code>scripts/ops/hardening.sh</code> exécuté sur VPS fresh"
      },
      {
       "kw": "When",
       "text": "il complète"
      },
      {
       "kw": "Then",
       "text": "<code>/etc/ssh/sshd_config</code> a <code>PasswordAuthentication no</code> + <code>PermitRootLogin no</code>"
      },
      {
       "kw": "And",
       "text": "<code>ufw status</code> montre ports 22/80/443 ouverts, tout le reste deny"
      },
      {
       "kw": "And",
       "text": "<code>fail2ban-client status sshd</code> montre filtre actif + 3 tentatives = ban 1h"
      },
      {
       "kw": "And",
       "text": "<code>fail2ban-client status apache-auth</code> filtre actif sur <code>/admin</code> login"
      },
      {
       "kw": "And",
       "text": "Dependabot + Renovate configurés sur le repo GitHub"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "3.11",
     "epic": 3,
     "title": "<code>env:encrypt</code> native Laravel + secrets workflow doc",
     "role": "Winston",
     "want": "<code>php artisan env:encrypt --env=production</code> workflow + doc <code>docs/process/secrets-management.md</code>",
     "benefit": "ADR-0006 est opérationnel et les secrets prod sont committables chiffrés",
     "ac": [
      {
       "kw": "Given",
       "text": "Alex génère localement <code>.env.production</code> + <code>php artisan env:encrypt --env=production</code>"
      },
      {
       "kw": "When",
       "text": "la commande termine"
      },
      {
       "kw": "Then",
       "text": "<code>.env.production.encrypted</code> est créé, committable safely (pas de leak Gitleaks)"
      },
      {
       "kw": "And",
       "text": "la clé <code>LARAVEL_ENV_ENCRYPTION_KEY</code> (32 chars) stockée en env var serveur + password manager personnel"
      },
      {
       "kw": "Given",
       "text": "déploiement prod"
      },
      {
       "kw": "When",
       "text": "<code>php artisan env:decrypt --env=production --key=$LARAVEL_ENV_ENCRYPTION_KEY</code> exécuté lors provisioning"
      },
      {
       "kw": "Then",
       "text": "<code>.env.production</code> reconstitué temporairement pour <code>php artisan config:cache</code>"
      },
      {
       "kw": "And",
       "text": "doc <code>docs/process/secrets-management.md</code> documente : génération clé, stockage, rotation, recovery"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "3.12",
     "epic": 3,
     "title": "Structured JSON logs + logrotate",
     "role": "Murat",
     "want": "logs Laravel en format JSON structuré (Monolog formatter) + rotation via logrotate",
     "benefit": "debug et analytique sont possibles via grep/jq + disk usage maîtrisé",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>config/logging.php</code> channel <code>prod</code> configuré avec <code>JsonFormatter</code>"
      },
      {
       "kw": "When",
       "text": "Laravel log une exception"
      },
      {
       "kw": "Then",
       "text": "la ligne dans <code>storage/logs/laravel-*.log</code> est valide JSON avec champs <code>@timestamp</code>, <code>level</code>, <code>message</code>, <code>context</code>, <code>extra</code>"
      },
      {
       "kw": "And",
       "text": "<code>/etc/logrotate.d/laravel-skeleton</code> rotate <code>storage/logs/*.log</code> quotidiennement, garde 14 jours, compress gzip"
      },
      {
       "kw": "And",
       "text": "logs verbose en <code>dev</code> (level debug), <code>info</code> en staging, <code>warning</code> en prod"
      }
     ],
     "notes": [],
     "status": "backlog"
    }
   ]
  },
  {
   "num": 4,
   "title": "Layout + Live Status + Cookie Consent",
   "phase": "Phase 3/S1",
   "pitch": "Twitch Viewer perçoit LIVE/OFFLINE en &lt;300ms (badge Lava pulsant + embed Twitch + chat desktop, OFFLINE bascule gracieusement vers archive/dernière review hero/replay YouTube) ; cookie consent RGPD pré-embed Twitch/YouTube fonctionnel <b>dès J1</b> (pas S5).",
   "meta": {
    "FRs covered": "FR-Public-1/3/4, FR-Live-1 à 5, <b>FR-Sec-1</b> (cookie consent — déplacé d'Epic 9 ex-emplacement)",
    "NFRs critical": "NFR-Sec-3 (Cookie consent bloquant prod #3), NFR-Mobile-4 (&lt;300ms premier glance), NFR-Perf-1 à 4, NFR-Perf-10",
    "ARs": "AR-Ext-1 (Twitch Helix client)",
    "UX-DRs": "UX-DR-16 (consent gate bandeau), UX-DR-17/18/19 (Live components)",
    "Critère go": "home LIVE/OFFLINE rendu en &lt;1s mobile 4G (PRD §10.3 LOCKED)"
   },
   "amendments": [
    "<b>Cookie consent déplacé Epic 9 → Epic 4</b> (Murat NON-NÉGOCIABLE — 4 sprints d'exposition RGPD avec embed Twitch sans consent = mise en demeure CNIL rétroactive possible)",
    "<b>Story explicite \"Twitch Viewer offline landing\"</b> → CTA archive/dernière review (John : sinon ce persona = fantôme)",
    "<b>4 tests Pest minimum sur <code>&lt;livewire:live-status-badge&gt;</code></b> (Murat — 4 fixtures distinctes : 404 API, timeout, channel offline status, polling expired)"
   ],
   "effort": "4.5j",
   "status": "backlog",
   "retro": "optional",
   "stories": [
    {
     "id": "4.1",
     "epic": 4,
     "title": "Header sticky <code>&lt;x-nav&gt;</code> (logo + 3 items + LIVE indicator)",
     "role": "Twitch Viewer",
     "want": "un header sticky 48px mobile / 56px desktop avec logo + 3 items + indicateur LIVE intégré",
     "benefit": "je perçois l'état LIVE/OFFLINE au premier glance sans scroll",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>&lt;x-nav&gt;</code> rendu dans <code>&lt;x-layouts.public&gt;</code>"
      },
      {
       "kw": "When",
       "text": "je charge la home sur mobile 360px"
      },
      {
       "kw": "Then",
       "text": "le header fait 48px de hauteur, sticky top, <code>bg-bg/90 backdrop-blur-sm border-b border-border</code>"
      },
      {
       "kw": "And",
       "text": "les 3 items (Reviews · About · Press) sont visibles inline (pas de burger menu)"
      },
      {
       "kw": "Given",
       "text": "desktop 1280px"
      },
      {
       "kw": "Then",
       "text": "le header fait 56px de hauteur"
      },
      {
       "kw": "And",
       "text": "l'indicateur LIVE est visible en haut-gauche (composant <code>&lt;livewire:live-status-badge&gt;</code> Story 4.6)"
      },
      {
       "kw": "And",
       "text": "l'item actif a underline 1px + <code>text-primary</code>"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "4.2",
     "epic": 4,
     "title": "Footer + <code>&lt;x-footer.follow&gt;</code> capture before bounce",
     "role": "Browser FOMO + Returner Ponce-fan",
     "want": "footer site standard + bloc <code>&lt;x-footer.follow&gt;</code> persistant (Twitter + Discord + RSS texte)",
     "benefit": "je peux suivre Alex hors-stream depuis n'importe quelle page (Pattern 3)",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>&lt;x-footer&gt;</code> + <code>&lt;x-footer.follow&gt;</code> inclus dans <code>&lt;x-layouts.public&gt;</code>"
      },
      {
       "kw": "When",
       "text": "je scrolle au footer"
      },
      {
       "kw": "Then",
       "text": "<code>&lt;x-footer.follow&gt;</code> affiche <code>Twitter @$settings-&gt;twitter_handle</code> + <code>Discord</code> + <code>RSS</code> (texte, pas bouton)"
      },
      {
       "kw": "And",
       "text": "URLs lues depuis <code>$settings</code> (tenant-aware — pas hardcodées)"
      },
      {
       "kw": "And",
       "text": "<code>&lt;x-footer&gt;</code> contient mentions légales · <code>/press</code> · GitHub · contact mailto · copyright <code>2026</code>"
      },
      {
       "kw": "And",
       "text": "<b>pas de Lava</b> sur ce footer (discipline 90/8/2)"
      },
      {
       "kw": "And",
       "text": "RSS feed accessible <code>/feed.xml</code> (Story Epic 6)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "4.3",
     "epic": 4,
     "title": "Cookie consent banner (Spatie — bloquant prod #3)",
     "role": "Reader-Gamer (compliance RGPD)",
     "want": "bandeau cookie consent bas-droite max 64px hauteur, 3 boutons text-link, jamais d'overlay plein écran",
     "benefit": "je peux lire l'article sans cookie wall agressif tout en respectant RGPD pré-embed Twitch/YouTube",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>composer require spatie/laravel-cookie-consent</code> + <code>&lt;x-consent-gate&gt;</code> inclus dans <code>&lt;x-layouts.public&gt;</code>"
      },
      {
       "kw": "When",
       "text": "je visite la home pour la première fois (pas de cookie consent)"
      },
      {
       "kw": "Then",
       "text": "un bandeau apparaît bas-droite, max 64px hauteur, <code>bg-surface</code> + border-top <code>border</code>"
      },
      {
       "kw": "And",
       "text": "il contient 3 boutons text-link \"Accepter\" / \"Refuser\" / \"Personnaliser\" — <b>pas de Lava</b>"
      },
      {
       "kw": "And",
       "text": "le bandeau n'est <b>pas</b> un overlay plein écran"
      },
      {
       "kw": "Given",
       "text": "je clique \"Refuser\""
      },
      {
       "kw": "When",
       "text": "je navigue à une page avec embed Twitch"
      },
      {
       "kw": "Then",
       "text": "l'embed est remplacé par un placeholder cliquable"
      },
      {
       "kw": "Given",
       "text": "je clique \"Accepter\""
      },
      {
       "kw": "Then",
       "text": "l'embed Twitch charge normalement"
      },
      {
       "kw": "And",
       "text": "ma préférence est persistée 365 jours (cookie <code>cookie_consent</code>)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "4.4",
     "epic": 4,
     "title": "Iframe blocker placeholder for refused consent",
     "role": "Reader-Gamer (refus cookies)",
     "want": "un placeholder cliquable élégant à la place de tout iframe Twitch/YouTube si refus consent",
     "benefit": "je peux toujours accéder au contenu manuellement",
     "ac": [
      {
       "kw": "Given",
       "text": "consent state = <code>refused</code>"
      },
      {
       "kw": "When",
       "text": "je charge une page avec <code>&lt;x-twitch-embed&gt;</code> ou embed YouTube"
      },
      {
       "kw": "Then",
       "text": "Alpine.js détecte l'état + remplace l'iframe par <code>&lt;x-consent-placeholder&gt;</code> avant chargement"
      },
      {
       "kw": "And",
       "text": "le placeholder affiche : icône iframe + texte \"Cliquer pour charger l'embed (cela acceptera les cookies)\" + bouton secondary \"Charger\" + lien externe vers twitch.tv ou youtube.com"
      },
      {
       "kw": "And",
       "text": "clic sur \"Charger\" → update consent → reload iframe in place (sans full page reload)"
      },
      {
       "kw": "And",
       "text": "Pest test : viewport mobile + consent refused → placeholder visible, iframe absent"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "4.5",
     "epic": 4,
     "title": "Twitch Helix API client (rate-limit aware + Redis cache 60s)",
     "role": "Alex-Dev",
     "want": "<code>App\\Modules\\Live\\Services\\TwitchHelixClient</code> avec rate-limit awareness + cache Redis 60s",
     "benefit": "le badge LIVE est performant + ne déclenche pas rate-limiting Helix",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>TwitchHelixClient::isLive(string $channelId): bool</code>"
      },
      {
       "kw": "When",
       "text": "elle est appelée pour la première fois"
      },
      {
       "kw": "Then",
       "text": "elle ping Helix <code>GET /helix/streams?user_login=$channelId</code> avec OAuth2 client_credentials"
      },
      {
       "kw": "And",
       "text": "la réponse est cachée Redis avec TTL 60s sous clé <code>helix:live:$channelId</code>"
      },
      {
       "kw": "Given",
       "text": "100 appels consécutifs en 60s"
      },
      {
       "kw": "Then",
       "text": "99 retournent depuis le cache (1 seul hit Helix réel)"
      },
      {
       "kw": "And",
       "text": "rate-limit headers Helix monitored, si &lt;50 → cache TTL augmenté à 5min temporairement"
      },
      {
       "kw": "And",
       "text": "Sentry alert si rate-limit &lt;10"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "4.6",
     "epic": 4,
     "title": "<code>&lt;livewire:live-status-badge&gt;</code> with 4 Pest tests minimum",
     "role": "Twitch Viewer",
     "want": "un badge Livewire qui poll Helix toutes les 60s + affiche \"● LIVE since 2h17m\" en Lava pulsant quand stream actif",
     "benefit": "je perçois l'état stream au premier glance (&lt;300ms)",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>&lt;livewire:live-status-badge&gt;</code> rendu dans <code>&lt;x-nav&gt;</code>"
      },
      {
       "kw": "When",
       "text": "Helix retourne stream actif"
      },
      {
       "kw": "Then",
       "text": "le badge affiche <code>● LIVE since 2h17m</code> en <code>bg-lava text-bg</code> (Lava authorized — catégorie 4)"
      },
      {
       "kw": "And",
       "text": "Alpine.js refresh client-side la durée toutes les 60s (composant <code>&lt;x-time-since&gt;</code>)"
      },
      {
       "kw": "And",
       "text": "un pulse subtil 1Hz sur le point <code>●</code> (<code>@keyframes pulse</code> 200ms <code>cubic-bezier(0.16, 1, 0.3, 1)</code>)"
      },
      {
       "kw": "Given",
       "text": "Helix retourne stream inactif"
      },
      {
       "kw": "Then",
       "text": "badge montre <code>OFFLINE · dernier stream il y a 14h</code> en <code>text-secondary</code> (pas de Lava)"
      },
      {
       "kw": "Given",
       "text": "Pest test <code>LiveStatusBadgeTest.php</code> exigé par Murat (4 cas distincts)"
      },
      {
       "kw": "Then",
       "text": ":"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "4.7",
     "epic": 4,
     "title": "Circuit breaker fallback OFFLINE silent",
     "role": "Twitch Viewer",
     "want": "circuit breaker qui force OFFLINE après 3 retries Helix échoués + reset après 5min, sans aucune alerte UI",
     "benefit": "Helix down ne casse pas mon expérience — l'embed Twitch natif source de vérité me corrigera",
     "ac": [
      {
       "kw": "Given",
       "text": "un Service <code>TwitchHelixClient</code> avec circuit breaker"
      },
      {
       "kw": "When",
       "text": "3 appels Helix consécutifs échouent (timeout / 5xx)"
      },
      {
       "kw": "Then",
       "text": "le circuit s'ouvre pour 5 minutes"
      },
      {
       "kw": "And",
       "text": "les appels suivants retournent immédiatement <code>false</code> (OFFLINE) sans hit Helix"
      },
      {
       "kw": "And",
       "text": "<b>aucune alerte UI visible</b> au visiteur (pas de \"Twitch API indisponible\")"
      },
      {
       "kw": "Given",
       "text": "5 minutes écoulées"
      },
      {
       "kw": "Then",
       "text": "le circuit passe half-open, tente 1 ping"
      },
      {
       "kw": "And",
       "text": "si succès → circuit fermé, opérations normales"
      },
      {
       "kw": "And",
       "text": "si échec → circuit ré-ouvert 5 min de plus"
      },
      {
       "kw": "And",
       "text": "Pulse expose métrique <code>helix_circuit_state</code> (open/half-open/closed)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "4.8",
     "epic": 4,
     "title": "<code>&lt;x-twitch-embed&gt;</code> with consent gate + chat hidden &lt;768px",
     "role": "Twitch Viewer (LIVE)",
     "want": "composant <code>&lt;x-twitch-embed :channel=\"$channel\"&gt;</code> qui rend l'iframe Twitch player + chat (desktop), masque le chat sur mobile &lt;768px",
     "benefit": "je vois le stream confortablement desktop ET je ne souffre pas du chat illisible mobile",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>&lt;x-twitch-embed :channel=\"$settings-&gt;twitch_handle\" /&gt;</code> dans homepage"
      },
      {
       "kw": "When",
       "text": "je suis sur desktop ≥768px + consent accepté"
      },
      {
       "kw": "Then",
       "text": "rendu : iframe player Twitch 75% width + iframe chat 25% width côté à côte"
      },
      {
       "kw": "Given",
       "text": "mobile &lt;768px + consent accepté"
      },
      {
       "kw": "Then",
       "text": "iframe player 100% width + <b>chat masqué via CSS <code>@media (max-width: 767px) { .twitch-chat { display: none; } }</code></b>"
      },
      {
       "kw": "And",
       "text": "un lien CTA discret \"Ouvrir le chat sur Twitch\" remplace le chat masqué"
      },
      {
       "kw": "Given",
       "text": "consent refusé"
      },
      {
       "kw": "Then",
       "text": "<code>&lt;x-consent-placeholder&gt;</code> affiché à la place (Story 4.4)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "4.9",
     "epic": 4,
     "title": "<code>&lt;x-offline-scene&gt;</code> avec time-as-texture",
     "role": "Twitch Viewer (OFFLINE — état majoritaire)",
     "want": "scène OFFLINE : \"Hors ligne · dernier stream il y a 14h\" + dernière review hero + 3 reviews récentes + lien dernier replay YouTube",
     "benefit": "OFFLINE = exploration, pas vide ou frustration",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>&lt;x-offline-scene&gt;</code> rendu dans homepage quand Helix retourne offline"
      },
      {
       "kw": "When",
       "text": "je charge la page"
      },
      {
       "kw": "Then",
       "text": "la section principale affiche : titre \"Hors ligne\" + <code>&lt;x-time-relative :datetime=\"$lastStreamEndedAt\"&gt;</code> (\"· dernier stream il y a 14h\")"
      },
      {
       "kw": "And",
       "text": "<b>dernière review hero</b> avec cover + titre + note + verdict 1 ligne"
      },
      {
       "kw": "And",
       "text": "liste 3 reviews récentes (cards) en dessous"
      },
      {
       "kw": "And",
       "text": "lien \"Voir le dernier replay YouTube\" vers la VOD la plus récente"
      },
      {
       "kw": "And",
       "text": "<b>pas de Lava</b> sur cette scène"
      },
      {
       "kw": "And",
       "text": "<b>pas de \"Prochain stream prévu\"</b> v1"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "4.10",
     "epic": 4,
     "title": "Twitch Viewer offline landing CTA explicit (John request)",
     "role": "Twitch Viewer offline-driven",
     "want": "un parcours explicite OFFLINE → CTA archive/dernière review",
     "benefit": "je consomme le contenu d'Alex même quand il ne stream pas",
     "ac": [
      {
       "kw": "Given",
       "text": "je suis Twitch Viewer arrivant sur home en mode OFFLINE"
      },
      {
       "kw": "When",
       "text": "je vois <code>&lt;x-offline-scene&gt;</code> (Story 4.9)"
      },
      {
       "kw": "Then",
       "text": "elle inclut un CTA secondary \"Voir toutes les reviews →\" en bas"
      },
      {
       "kw": "And",
       "text": "ce CTA mène à <code>/reviews/</code> (listing — story Epic 6)"
      },
      {
       "kw": "And",
       "text": "un événement Plausible <code>home_offline_to_reviews_click</code> est dispatché au clic"
      },
      {
       "kw": "And",
       "text": "<b>aucune modale popup</b> ne s'affiche pour pousser à l'engagement"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "4.11",
     "epic": 4,
     "title": "Homepage routing LIVE/OFFLINE differentiation",
     "role": "Alex-Dev",
     "want": "<code>HomeController::index()</code> qui détermine LIVE/OFFLINE via <code>TwitchHelixClient</code> puis rend la vue adaptée",
     "benefit": "le critère go S1 (premier glance &lt;300ms + home rendue &lt;1s mobile 4G) est atteint",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>App\\Modules\\Public\\Http\\Controllers\\HomeController@index</code>"
      },
      {
       "kw": "When",
       "text": "une requête <code>GET /</code> arrive"
      },
      {
       "kw": "Then",
       "text": "le controller call <code>$twitchClient-&gt;isLive($streamer-&gt;twitch_handle)</code> (cache 60s)"
      },
      {
       "kw": "And",
       "text": "si LIVE → render avec <code>&lt;x-twitch-embed&gt;</code> + meta <code>&lt;x-time-since&gt;</code>"
      },
      {
       "kw": "And",
       "text": "si OFFLINE → render avec <code>&lt;x-offline-scene&gt;</code> (Story 4.9)"
      },
      {
       "kw": "And",
       "text": "TTFC sur mobile 4G mesuré Lighthouse &lt;1.5s"
      },
      {
       "kw": "And",
       "text": "test Pest browser <code>HomepageRoutingTest</code> couvre les 2 cas"
      },
      {
       "kw": "And",
       "text": "Plausible event <code>home_view</code> dispatché avec prop <code>state: live|offline</code>"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "4.12",
     "epic": 4,
     "title": "Pest OWASP A02 (Cryptographic Failures) cookie secure flags",
     "role": "Murat",
     "want": "test Pest <code>tests/Security/CryptographyTest.php</code> qui vérifie tous les cookies ont <code>Secure + HttpOnly + SameSite=Strict</code>",
     "benefit": "OWASP A02 est couvert + cookie consent est sécurisé dès Epic 4",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>tests/Security/CryptographyTest.php</code>"
      },
      {
       "kw": "When",
       "text": "il s'exécute en CI (gate progressif activé Epic 4)"
      },
      {
       "kw": "Then",
       "text": "assert <code>config/session.php</code> a <code>secure: true</code>, <code>http_only: true</code>, <code>same_site: 'strict'</code> en non-local"
      },
      {
       "kw": "And",
       "text": "assert <code>spatie/laravel-cookie-consent</code> configuré avec <code>secure_cookie: true</code>"
      },
      {
       "kw": "And",
       "text": "assert toute Response Laravel inclut <code>Strict-Transport-Security: max-age=31536000; includeSubDomains; preload</code>"
      },
      {
       "kw": "And",
       "text": "workflow CI fail si une assertion ne passe pas (bloquant à partir de cet Epic)"
      }
     ],
     "notes": [],
     "status": "backlog"
    }
   ]
  },
  {
   "num": 5,
   "title": "Reviews CRUD + Reading + CTAs Twitter/Discord UTM",
   "phase": "Phase 3/S2 ~7j",
   "pitch": "Reader-Gamer Chercheur Google atterrit sur <code>/reviews/{slug}</code>, voit titre + note + verdict en &lt;5s above-the-fold mobile, peut lire 1200 mots confortable ; Alex publie review en &lt;10min Filament fatigué 23h (autosave 60s natif + preview inline) ; CTAs Twitter/Discord en fin d'article tenant-aware avec UTM bidirectionnel.",
   "meta": {
    "FRs covered": "FR-Reviews-1 à 8, FR-Reviews-10, <b>FR-Reviews-12/13</b> (CTAs déplacés d'Epic 9), FR-Admin-1 à 4, FR-Admin-6, FR-Admin-7",
    "NFRs critical": "NFR-Cadence-1/2/3 (3 articles/mois steady, publish &lt;10min), NFR-Perf-1 à 8, NFR-SEO-3/4/8, NFR-Metric-4/5 (time-on-page &gt;3min, bounce &lt;60%)",
    "ARs": "AR-Ext-2 (YouTube validator), AR-Data-1 à 7",
    "Critère go": "publish review brouillon → publié &lt;10min chrono (PRD §10.3 LOCKED)"
   },
   "amendments": [
    "<b>CTAs Twitter/Discord déplacés Epic 9 → Epic 5</b> (Amelia : <code>&lt;x-cta.post-read&gt;</code> est une story interne Reviews, pas un epic à part)",
    "Effort revu à <b>7j</b> (vs 6j initial — autosave Livewire 3 + preview inline sous-estimés 1.5j, Amelia)",
    "<b>Pest OWASP A01 (Auth) + A03 (Injection) activés au merge Epic 5</b> (Murat : Filament policies + forms autosave)",
    "Update-in-place workflow (<code>last_updated_at</code> auto-bump, badge \"Mis à jour le X\" si Y &gt; X+30j) — Direction C",
    "ArticleSeeder fixture créée (utilisée par Epic 7 OG pour tests indépendants)"
   ],
   "effort": "7j",
   "status": "backlog",
   "retro": "optional",
   "stories": [
    {
     "id": "5.1",
     "epic": 5,
     "title": "Article model + migration (enum type review|news|preview)",
     "role": "Alex-Dev",
     "want": "modèle <code>Article</code> unique avec enum <code>type</code> (review|news|preview), <code>note</code>/<code>vod_youtube_url</code>/<code>game_id</code> nullable, slug ASCII pur, <code>published_at</code> + <code>last_updated_at</code> + <code>revision_note</code>",
     "benefit": "OQ9 LOCKED unifie 3 types de contenu sans dupliquer la table",
     "ac": [
      {
       "kw": "Given",
       "text": "migration <code>2026_02_15_create_articles_table.php</code>"
      },
      {
       "kw": "When",
       "text": "<code>php artisan migrate</code>"
      },
      {
       "kw": "Then",
       "text": "table <code>articles</code> avec colonnes : <code>id</code>, <code>streamer_id BIGINT NOT NULL</code>, <code>type ENUM('review','news','preview')</code>, <code>title VARCHAR(255)</code>, <code>slug VARCHAR(180) UNIQUE</code>, <code>cover_url TEXT NULL</code>, <code>body MEDIUMTEXT</code>, <code>note TINYINT NULL</code> (0-10), <code>verdict TEXT NULL</code>, <code>vod_youtube_url VARCHAR(500) NULL</code>, <code>game_id BIGINT NULL FK games</code>, <code>published_at TIMESTAMP NULL</code>, <code>last_updated_at TIMESTAMP NULL</code>, <code>revision_note TEXT NULL</code>, <code>views_count INT DEFAULT 0</code>, <code>timestamps</code>"
      },
      {
       "kw": "And",
       "text": "index <code>(streamer_id, published_at DESC)</code> + <code>(streamer_id, type, published_at)</code> + unique <code>(streamer_id, slug)</code>"
      },
      {
       "kw": "And",
       "text": "<code>Article</code> model utilise trait <code>BelongsToStreamer</code> (Epic 1 tenancy)"
      },
      {
       "kw": "And",
       "text": "test Pest TenancyMigrationTest passe (Story 1.5)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "5.2",
     "epic": 5,
     "title": "Game model + GameResource (catalogue référencé)",
     "role": "Alex-Dev",
     "want": "modèle <code>Game</code> + Filament <code>GameResource</code> (titre, slug, plateforme, studio, sortie_date)",
     "benefit": "les reviews peuvent être liées à un jeu identifié pour Schema.org VideoGame + archive <code>/games/{slug}</code>",
     "ac": [
      {
       "kw": "Given",
       "text": "migration <code>2026_02_15_create_games_table.php</code> + Filament <code>GameResource</code>"
      },
      {
       "kw": "When",
       "text": "Alex crée un jeu \"Elden Ring Nightreign\" via <code>/admin/games/create</code>"
      },
      {
       "kw": "Then",
       "text": "row créé avec slug auto-généré + tenant-aware"
      },
      {
       "kw": "And",
       "text": "<code>ArticleResource</code> (Story 5.3) a un Select cherchable pour <code>game_id</code>"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "5.3",
     "epic": 5,
     "title": "ArticleResource Filament CRUD (full)",
     "role": "Alex-Auteur",
     "want": "Filament <code>ArticleResource</code> avec form complet + listing table + actions Edit/Delete/Publish/Preview",
     "benefit": "je gère mes reviews/news/previews depuis <code>/admin/articles</code>",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>App\\Modules\\Reviews\\Filament\\Resources\\ArticleResource</code>"
      },
      {
       "kw": "When",
       "text": "j'ouvre <code>/admin/articles/create</code>"
      },
      {
       "kw": "Then",
       "text": "form affiche sections : \"Identification\" (title, slug auto, type select, game select, cover FileUpload) + \"Contenu\" (body MarkdownEditor) + \"Évaluation\" (note 0-10 nullable, verdict Textarea — visible si type=review) + \"VOD\" (vod_youtube_url + bouton \"Valider\") + \"Publication\" (published_at DateTimePicker)"
      },
      {
       "kw": "And",
       "text": "listing colonnes : Cover thumbnail, Title, Type Badge (review/news/preview), Note, Published (<code>&lt;x-time-relative&gt;</code>), Actions"
      },
      {
       "kw": "And",
       "text": "Filtres : type, year, has_note, vod_unavailable"
      },
      {
       "kw": "And",
       "text": "PHPStan level monté à L6 pour ce module"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "5.4",
     "epic": 5,
     "title": "Autosave 60s native Filament Forms with silent toast",
     "role": "Alex-Auteur (23h fatigué)",
     "want": "autosave 60s sur <code>ArticleResource</code> form + toast Filament Notification silencieux \"Saved 23:14:32\"",
     "benefit": "je ne pense jamais \"ai-je sauvé ?\"",
     "ac": [
      {
       "kw": "Given",
       "text": "ArticleResource form avec <code>-&gt;autosave(60)</code>"
      },
      {
       "kw": "When",
       "text": "je laisse 60s sans action après une modification"
      },
      {
       "kw": "Then",
       "text": "Filament POST autosave vers backend"
      },
      {
       "kw": "And",
       "text": "un toast Filament Notification silencieux apparaît 2s \"Saved 23:14:32\" en bas-droite"
      },
      {
       "kw": "And",
       "text": "Pest feature test <code>it('persists draft after 60s without explicit save')</code> passe"
      },
      {
       "kw": "And",
       "text": "browser crash mid-rédaction → réouverture brouillon = autosave 60s récupéré"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "5.5",
     "epic": 5,
     "title": "Preview inline non-modal in Filament",
     "role": "Alex-Auteur",
     "want": "bouton \"Preview\" qui toggle preview inline (panneau split-screen droit), pas une modale",
     "benefit": "je vois le rendu réel sans quitter l'éditeur",
     "ac": [
      {
       "kw": "Given",
       "text": "ArticleResource Form avec Action <code>Preview</code> custom"
      },
      {
       "kw": "When",
       "text": "je clique \"Preview\""
      },
      {
       "kw": "Then",
       "text": "un panneau droit split-screen (50/50) montre le rendu Blade réel"
      },
      {
       "kw": "And",
       "text": "<b>pas de modale fullscreen</b>"
      },
      {
       "kw": "And",
       "text": "modifs côté éditeur refresh le preview Livewire en debounce 500ms"
      },
      {
       "kw": "And",
       "text": "preview utilise les mêmes composants Blade que <code>/reviews/{slug}</code> (<code>&lt;x-reviews.header&gt;</code> + <code>&lt;x-reviews.body&gt;</code> + <code>&lt;x-reviews.timecode&gt;</code>)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "5.6",
     "epic": 5,
     "title": "YoutubeValidator service + check pre-publish",
     "role": "Alex-Auteur",
     "want": "<code>YoutubeValidator::validate(string $url)</code> qui ping YouTube Data API avant publish",
     "benefit": "jamais de lien VOD mort en prod",
     "ac": [
      {
       "kw": "Given",
       "text": "Alex saisit <code>vod_youtube_url</code> puis clique \"Publier\""
      },
      {
       "kw": "When",
       "text": "ArticleResource form <code>beforeSave()</code>"
      },
      {
       "kw": "Then",
       "text": "<code>YoutubeValidator::validate($url)</code> ping API + retourne <code>{exists, duration, views, title}</code>"
      },
      {
       "kw": "And",
       "text": "si <code>exists: true</code> → publish réussit + Filament Notification success \"VOD trouvée — durée 4h12m\""
      },
      {
       "kw": "And",
       "text": "si <code>exists: false</code> → Filament Notification warning + override possible"
      },
      {
       "kw": "And",
       "text": "si Helix YT down → fallback graceful (warning, override possible)"
      },
      {
       "kw": "And",
       "text": "test Pest feature couvre les 3 cas"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "5.7",
     "epic": 5,
     "title": "Public review page <code>/reviews/{slug}</code> (Wirecutter verdict above-the-fold)",
     "role": "Reader-Gamer Chercheur Google",
     "want": "page <code>/reviews/{slug}</code> avec verdict above-the-fold mobile &lt;5s",
     "benefit": "je décide en &lt;5s si Alex mérite mes 8 min de lecture",
     "ac": [
      {
       "kw": "Given",
       "text": "route <code>GET /reviews/{slug}</code> → <code>ReviewController@show</code>"
      },
      {
       "kw": "When",
       "text": "je charge la page sur mobile 360px"
      },
      {
       "kw": "Then",
       "text": "above-the-fold contient : header sticky 48px + breadcrumb 1 ligne + H1 28px + métadonnées <code>&lt;x-time-dual&gt;</code> + note display 60px (couleur tier) + verdict intro"
      },
      {
       "kw": "And",
       "text": "<b>pas de cover image above-the-fold mobile</b> (cover apparaît scroll +200-300px premier H2)"
      },
      {
       "kw": "And",
       "text": "<b>pas de popup, pas d'autoplay, pas de sidebar agressive</b>"
      },
      {
       "kw": "And",
       "text": "TTFC layout (titre + note visible) &lt;1.5s mobile 4G (Lighthouse)"
      },
      {
       "kw": "And",
       "text": "LCP &lt;2.5s, CLS = 0"
      },
      {
       "kw": "And",
       "text": "corps article <code>&lt;x-reviews.body&gt;</code> 720px max-width 18px line-height 1.7 (Stripe Press pattern)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "5.8",
     "epic": 5,
     "title": "<code>&lt;x-reviews.header&gt;</code> (titre + note display + verdict + métadonnées denses)",
     "role": "Sally",
     "want": "composant <code>&lt;x-reviews.header :article&gt;</code> qui rend titre H1 + métadonnées denses + note display couleur tier + verdict intro",
     "benefit": "above-the-fold mobile est rendu en &lt;5s avec hiérarchie claire",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>&lt;x-reviews.header :article=\"$article\" /&gt;</code>"
      },
      {
       "kw": "When",
       "text": "je le rends avec un article note 8"
      },
      {
       "kw": "Then",
       "text": "structure verticale : H1 + meta inline <code>&lt;x-time-dual /&gt;</code> · <code>8 min de lecture</code> (mono) + bloc note display \"8 / 10\" 60px mobile / 80-96px desktop, couleur <code>text-primary</code> (tier solid)"
      },
      {
       "kw": "And",
       "text": "si <code>note &gt;= 9</code> → couleur <code>text-lava</code> (autorisé — catégorie 3 des 4 Lava)"
      },
      {
       "kw": "And",
       "text": "si <code>note &lt;= 6</code> → couleur <code>text-secondary</code>"
      },
      {
       "kw": "And",
       "text": "si <code>type !== 'review'</code> → pas de note affichée"
      },
      {
       "kw": "And",
       "text": "verdict 1-3 phrases en <code>&lt;p class=\"text-lg italic font-medium\"&gt;</code>"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "5.9",
     "epic": 5,
     "title": "<code>&lt;x-reviews.body :markdown&gt;</code> (corps article 720px max-width)",
     "role": "Sally",
     "want": "<code>&lt;x-reviews.body :markdown&gt;</code> rendant Markdown → HTML avec max-width 720px + IBM Plex Sans 18px + line-height 1.7",
     "benefit": "lecture longue 1200 mots confortable (Stripe Press pattern)",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>&lt;x-reviews.body&gt;</code> avec article body Markdown"
      },
      {
       "kw": "When",
       "text": "rendu"
      },
      {
       "kw": "Then",
       "text": "parsing via league/commonmark"
      },
      {
       "kw": "And",
       "text": "wrapper <code>&lt;article class=\"prose max-w-prose\"&gt;</code> avec Tailwind Typography custom (tokens IBM Plex + line-height 1.7)"
      },
      {
       "kw": "And",
       "text": "images : <code>loading=\"lazy\"</code> + dimensions reservées"
      },
      {
       "kw": "And",
       "text": "<code>&lt;x-reviews.timecode&gt;</code> shortcode pour <code>[00:42]</code>"
      },
      {
       "kw": "And",
       "text": "pas de sidebar mobile"
      },
      {
       "kw": "And",
       "text": "sub-headings H2/H3 séquentiels"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "5.10",
     "epic": 5,
     "title": "<code>&lt;x-reviews.timecode :video :time&gt;</code> YouTube <code>?t=42</code> new tab",
     "role": "Reader-Gamer",
     "want": "timecodes inline <code>[00:42]</code> cliquables dans le corps article",
     "benefit": "je peux jumper directement à un moment précis sur la VOD YouTube",
     "ac": [
      {
       "kw": "Given",
       "text": "body article contient <code>[12:34]</code> parsé par CommonMark extension custom"
      },
      {
       "kw": "When",
       "text": "rendu HTML"
      },
      {
       "kw": "Then",
       "text": "sortie <code>&lt;a href=\"https://youtu.be/{video_id}?t=754\" target=\"_blank\" rel=\"noopener noreferrer\" class=\"font-mono text-secondary hover:text-primary\"&gt;[12:34]&lt;/a&gt;</code>"
      },
      {
       "kw": "And",
       "text": "ouverture nouvelle onglet (pas modale)"
      },
      {
       "kw": "And",
       "text": "Pest test parse <code>[1:23]</code>, <code>[01:23]</code>, <code>[12:34]</code>, <code>[1:23:45]</code> → seconds correct"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "5.11",
     "epic": 5,
     "title": "Update-in-place workflow (<code>last_updated_at</code> auto-bump + badge front)",
     "role": "Reader-Gamer (SEO + Trust)",
     "want": "éditer article post-publish → <code>last_updated_at</code> auto-bump + badge \"Mis à jour le X\" front si Y &gt; X+30j",
     "benefit": "patch jeu = update-in-place, link equity SEO préservée (Schema.org dateModified)",
     "ac": [
      {
       "kw": "Given",
       "text": "Article avec <code>published_at = 2026-03-14</code> et <code>last_updated_at = null</code>"
      },
      {
       "kw": "When",
       "text": "Alex édite + Save (post-publish)"
      },
      {
       "kw": "Then",
       "text": "observer Model <code>Article::saving()</code> set <code>last_updated_at = now()</code> (si déjà publié)"
      },
      {
       "kw": "Given",
       "text": "front rendering avec <code>last_updated_at &gt; published_at + 30j</code>"
      },
      {
       "kw": "Then",
       "text": "<code>&lt;x-time-dual&gt;</code> affiche \"Publié 14 mars · Mis à jour 12 avril\""
      },
      {
       "kw": "Given",
       "text": "<code>last_updated_at - published_at &lt;= 30j</code>"
      },
      {
       "kw": "Then",
       "text": "affiche uniquement \"Publié 14 mars\""
      },
      {
       "kw": "And",
       "text": "Schema.org JSON-LD <code>datePublished</code> + <code>dateModified</code>"
      },
      {
       "kw": "And",
       "text": "sitemap.xml <code>&lt;lastmod&gt;</code> reflète <code>last_updated_at</code> (Story Epic 6)"
      },
      {
       "kw": "And",
       "text": "RSS feed entries triées par <code>last_updated_at</code>"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "5.12",
     "epic": 5,
     "title": "View counter seuil min 100 (anti-vanity Ponce)",
     "role": "Alex (anti-vanity Ponce)",
     "want": "compteur vues incrémenté sur GET /reviews/{slug} mais affiché front uniquement si <code>views_count &gt;= 100</code>",
     "benefit": "pas de \"0 vues\" embarrassant + pas en index (page detail uniquement)",
     "ac": [
      {
       "kw": "Given",
       "text": "colonne <code>views_count INT DEFAULT 0</code>"
      },
      {
       "kw": "When",
       "text": "visiteur charge <code>/reviews/{slug}</code>"
      },
      {
       "kw": "Then",
       "text": "middleware <code>IncrementViewCount</code> incrémente (rate-limit 1/IP/article/h via Redis)"
      },
      {
       "kw": "Given",
       "text": "<code>views_count &gt;= 100</code>"
      },
      {
       "kw": "Then",
       "text": "<code>&lt;x-reviews.header&gt;</code> affiche \"247 vues\" en <code>text-secondary font-mono</code>"
      },
      {
       "kw": "Given",
       "text": "<code>views_count &lt; 100</code>"
      },
      {
       "kw": "Then",
       "text": "<b>rien n'est affiché</b>"
      },
      {
       "kw": "And",
       "text": "<b>pas de compteur en index</b> <code>/reviews/</code> ni cards listing"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "5.13",
     "epic": 5,
     "title": "<code>&lt;x-cta.post-read&gt;</code> Twitter/Discord tenant-aware UTM bidirectionnel",
     "role": "Reader-Gamer (engagement)",
     "want": "CTAs Twitter/Discord en fin d'article tenant-aware avec UTM bidirectionnel",
     "benefit": "je suis Alex hors-stream + Alex track JTBD n°3 + composant fonctionne pour fork-streamer",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>&lt;x-cta.post-read :slug=\"$article-&gt;slug\" /&gt;</code> rendu en fin d'article (après <code>&lt;x-reviews.related&gt;</code> Epic 6)"
      },
      {
       "kw": "When",
       "text": "affiché"
      },
      {
       "kw": "Then",
       "text": "structure verticale mobile / horizontale desktop : 2 boutons secondary \"Twitter @{$settings-&gt;twitter_handle}\" + \"Discord du chat\""
      },
      {
       "kw": "And",
       "text": "lecture URLs depuis <code>$settings</code> — jamais hardcoded"
      },
      {
       "kw": "And",
       "text": "copy archétype Ponce : \"On en discute ailleurs.\" en titre + 1 ligne contexte"
      },
      {
       "kw": "And",
       "text": "<b>pas de Lava</b> sur ces CTAs (preserve rareté signal LIVE)"
      },
      {
       "kw": "And",
       "text": "1 clic = <code>target=\"_blank\"</code> + <code>rel=\"noopener noreferrer\"</code> + URL UTM-tracked : <code>?utm_source=site&amp;utm_medium=post-read-cta&amp;utm_campaign={article-slug}&amp;utm_content=twitter|discord</code>"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "5.14",
     "epic": 5,
     "title": "Plausible event <code>cta_post_read_click</code> + KPI CTR &gt;3%",
     "role": "Mary",
     "want": "événement Plausible <code>cta_post_read_click</code> au clic avec props <code>{platform, slug}</code>",
     "benefit": "CTR fin d'article &gt;3% est mesurable (KPI Sally round 5)",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>&lt;x-cta.post-read&gt;</code> avec Alpine.js <code>@click=\"plausible('cta_post_read_click', {props: {platform: 'twitter', slug: 'elden-ring-nightreign'}})\"</code>"
      },
      {
       "kw": "When",
       "text": "visiteur clique le bouton Twitter"
      },
      {
       "kw": "Then",
       "text": "événement envoyé à Plausible avec props"
      },
      {
       "kw": "And",
       "text": "dashboard Plausible expose CTR par slug + plateforme"
      },
      {
       "kw": "And",
       "text": "alerte si CTR &lt;3% sur 7j roulants"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "5.15",
     "epic": 5,
     "title": "Schema.org Review + VideoGame structured data",
     "role": "Reader-Gamer Chercheur Google (SEO)",
     "want": "JSON-LD Schema.org <code>Review</code> + <code>VideoGame</code> dans <code>&lt;head&gt;</code> de <code>/reviews/{slug}</code> quand <code>type=review</code>",
     "benefit": "Google peut afficher rich snippet avec note dans SERP",
     "ac": [
      {
       "kw": "Given",
       "text": "article type=review avec note=8 et game \"Elden Ring Nightreign\""
      },
      {
       "kw": "When",
       "text": "je render <code>/reviews/{slug}</code>"
      },
      {
       "kw": "Then",
       "text": "<code>&lt;head&gt;</code> contient <code>&lt;script type=\"application/ld+json\"&gt;</code> avec <code>@type: Review</code> + <code>reviewRating: {ratingValue: 8, bestRating: 10}</code> + <code>itemReviewed: {@type: VideoGame, name: \"Elden Ring Nightreign\"}</code> + <code>author: {@type: Person, name: \"Alex\"}</code> + <code>datePublished</code> + <code>dateModified</code>"
      },
      {
       "kw": "And",
       "text": "Google Rich Results Test valide sans erreur"
      },
      {
       "kw": "And",
       "text": "<code>type=news</code> ou <code>preview</code> → JSON-LD <code>Article</code> (sans rating)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "5.16",
     "epic": 5,
     "title": "Pest OWASP A01 (Auth) + A03 (Injection) at Epic 5 merge",
     "role": "Murat",
     "want": "tests Pest <code>tests/Security/AuthTest.php</code> + <code>tests/Security/InjectionTest.php</code> activés au merge Epic 5",
     "benefit": "OWASP A01 + A03 sont couverts dès S2 (PRD §sécu Phase 3/S1+S2)",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>tests/Security/AuthTest.php</code>"
      },
      {
       "kw": "When",
       "text": "il s'exécute en CI"
      },
      {
       "kw": "Then",
       "text": "assert utilisateur non-<code>super-admin</code> reçoit 403 sur <code>/admin/articles/create</code>"
      },
      {
       "kw": "And",
       "text": "assert utilisateur logged-out reçoit 302 redirect vers <code>/admin/login</code>"
      },
      {
       "kw": "And",
       "text": "assert tenancy enforcée : Article créé pour streamer_id=2 jamais accessible si current streamer=1"
      },
      {
       "kw": "Given",
       "text": "<code>tests/Security/InjectionTest.php</code>"
      },
      {
       "kw": "Then",
       "text": "assert <code>body</code> Markdown sanitize les <code>&lt;script&gt;</code> tags via HTMLPurifier (CommonMark strict mode)"
      },
      {
       "kw": "And",
       "text": "assert SQL injection sur slug param (<code>/reviews/'; DROP TABLE articles--</code>) → 404 (route param validation regex)"
      },
      {
       "kw": "And",
       "text": "workflow CI fail si une assertion ne passe pas"
      }
     ],
     "notes": [],
     "status": "backlog"
    }
   ]
  },
  {
   "num": 6,
   "title": "Archive & SEO Compounding",
   "phase": "Phase 3/S4 archive ~3.5j",
   "pitch": "Browser FOMO scanne 3 derniers articles ; Returner Ponce-fan retrouve l'article d'il y a 6 mois via tag/jeu/année ; Google indexe l'archive comme autorité topique sur \"streaming FR analyse\" — <b>moat business evergreen compounding</b> (Plausible-style, opportunité stratégique #1).",
   "meta": {
    "FRs covered": "FR-Public-2/5/6/7, FR-Reviews-11 (related articles capture before bounce)",
    "NFRs critical": "NFR-Cadence-4/5 (% trafic organique articles &gt;6 mois cibles M+12/M+18), NFR-SEO-1 à 8"
   },
   "amendments": [
    "<b>Internal linking automatique tags ≥2 = ALGO NAÏF v1</b> (Murat : 0.5j, pas TF-IDF qui = 5j → drop v1.1)",
    "<code>&lt;x-reviews.related&gt;</code> 3 cards horizontales en fin d'article AVANT CTA Twitter/Discord (Pattern 3 \"Capture before bounce\" Victor R6)",
    "Pages <code>/{year}</code> + <code>/{tag}</code> + <code>/{game}</code> cursor pagination first-class (pas annexes)",
    "Schema.org <code>Article.dateModified</code> synchronisé avec <code>last_updated_at</code> (cohérent FR-Reviews-8 Epic 5)"
   ],
   "effort": "3.5j",
   "status": "backlog",
   "retro": "optional",
   "stories": [
    {
     "id": "6.1",
     "epic": 6,
     "title": "Routes archive <code>/{year}</code> + <code>/{tag}</code> + <code>/{game}</code> first-class",
     "role": "Returner Ponce-fan + Browser FOMO",
     "want": "routes <code>/reviews/{year}</code>, <code>/reviews/tag/{tag}</code>, <code>/reviews/games/{game-slug}</code> first-class",
     "benefit": "je navigue les archives par dimension naturelle",
     "ac": [
      {
       "kw": "Given",
       "text": "routes définies dans <code>App\\Modules\\Reviews\\Routes\\web.php</code>"
      },
      {
       "kw": "When",
       "text": "je visite <code>/reviews/2026</code>"
      },
      {
       "kw": "Then",
       "text": "rendu liste cursor-paginated articles <code>WHERE YEAR(published_at) = 2026 AND streamer_id = current</code> triés <code>published_at DESC</code>"
      },
      {
       "kw": "And",
       "text": "<code>/reviews/tag/elden-ring</code> filtre <code>tags</code> jointure pivot"
      },
      {
       "kw": "And",
       "text": "<code>/reviews/games/elden-ring-nightreign</code> filtre <code>game_id</code>"
      },
      {
       "kw": "And",
       "text": "routes utilisent <code>Route::name('reviews.archive.year|tag|game')</code>"
      },
      {
       "kw": "And",
       "text": "breadcrumb 1 ligne : <code>Accueil / Reviews / 2026</code> ou <code>... / Tags / Elden Ring</code>"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "6.2",
     "epic": 6,
     "title": "Cursor pagination (scale 100+ articles M+24)",
     "role": "Alex (long-terme moat)",
     "want": "pagination cursor-based (<code>cursorPaginate</code> Laravel)",
     "benefit": "scaling à 100+ articles M+24 reste performant",
     "ac": [
      {
       "kw": "Given",
       "text": "archive <code>/reviews/2026</code> avec 50 articles"
      },
      {
       "kw": "When",
       "text": "je charge la page 1"
      },
      {
       "kw": "Then",
       "text": "12 articles chargés + bouton \"Articles plus anciens →\" avec cursor <code>?cursor=...</code>"
      },
      {
       "kw": "And",
       "text": "clic → page 2 avec 12 suivants"
      },
      {
       "kw": "And",
       "text": "<b>pas de \"Page X / Y\"</b> affiché"
      },
      {
       "kw": "And",
       "text": "SQL query utilise <code>WHERE published_at &lt; cursor</code> (efficace à 1000+ articles)"
      },
      {
       "kw": "And",
       "text": "test Pest browser : navigation paginated end-to-end sans 500 sur 50 articles seed"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "6.3",
     "epic": 6,
     "title": "<code>&lt;x-reviews.related&gt;</code> 3 cards tags ≥2 algo naïf",
     "role": "Reader-Gamer (capture before bounce)",
     "want": "composant <code>&lt;x-reviews.related :article&gt;</code> rendant 3 cards d'articles liés (tags partagés ≥2) en fin d'article AVANT CTA",
     "benefit": "je découvre un autre article avant de partir (Pattern 3 — Victor R6)",
     "ac": [
      {
       "kw": "Given",
       "text": "un Article avec tags <code>[elden-ring, action-rpg, soulslike]</code>"
      },
      {
       "kw": "When",
       "text": "<code>&lt;x-reviews.related :article=\"$article\" /&gt;</code> rendu"
      },
      {
       "kw": "Then",
       "text": "algo naïf v1 : query <code>articles WHERE id != current AND tags_overlap &gt;= 2</code> ORDER BY <code>last_updated_at DESC</code> LIMIT 3"
      },
      {
       "kw": "And",
       "text": "3 cards horizontales : cover thumbnail + titre + note + <code>&lt;x-time-relative&gt;</code> \"il y a 3 jours\""
      },
      {
       "kw": "And",
       "text": "<b>affiché AVANT</b> <code>&lt;x-cta.post-read&gt;</code> (ordre critique)"
      },
      {
       "kw": "And",
       "text": "si &lt;3 articles liés → afficher ce qu'on a (no pad avec random)"
      },
      {
       "kw": "And",
       "text": "si 0 articles liés → composant ne rend rien"
      },
      {
       "kw": "And",
       "text": "<b>algo naïf v1 LOCKED</b> — TF-IDF reporté v1.1 (Murat — drop 4j scope creep)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "6.4",
     "epic": 6,
     "title": "<code>&lt;x-reviews.archive-grid&gt;</code> listing 3-col",
     "role": "Sally",
     "want": "composant <code>&lt;x-reviews.archive-grid :articles&gt;</code> listing 3-col desktop / 1-col mobile",
     "benefit": "archive pages year/tag/game ont le même rendu cohérent",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>&lt;x-reviews.archive-grid :articles=\"$articles\" /&gt;</code>"
      },
      {
       "kw": "When",
       "text": "desktop 1024px+"
      },
      {
       "kw": "Then",
       "text": "grid 3-col gap-6 max-width 1024px"
      },
      {
       "kw": "And",
       "text": "chaque card : cover 16:9 + H3 titre + meta <code>&lt;x-time-relative&gt;</code> + note (si type=review) + verdict 1 ligne tronqué"
      },
      {
       "kw": "Given",
       "text": "mobile &lt;640px"
      },
      {
       "kw": "Then",
       "text": "1 colonne stacked, padding-x 16px"
      },
      {
       "kw": "And",
       "text": "clic card → <code>/reviews/{slug}</code>"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "6.5",
     "epic": 6,
     "title": "<code>&lt;x-reviews.empty-state&gt;</code> Raycast pattern",
     "role": "Returner Ponce-fan",
     "want": "composant <code>&lt;x-reviews.empty-state&gt;</code> rendant un état nominal designed",
     "benefit": "page archive vide reste cohérente avec l'identité visuelle",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>/reviews/tag/jeu-rare</code> retourne 0 article"
      },
      {
       "kw": "When",
       "text": "<code>&lt;x-reviews.empty-state /&gt;</code> rendu"
      },
      {
       "kw": "Then",
       "text": "affiche texte \"Aucun article pour ce tag pour l'instant.\" + CTA secondary \"Voir tous les articles →\" mène à <code>/reviews/</code>"
      },
      {
       "kw": "And",
       "text": "<b>pas de skeleton loader permanent</b> (anti-pattern Sally R3)"
      },
      {
       "kw": "And",
       "text": "<b>pas de \"Lorem ipsum review #4\" placeholder</b>"
      },
      {
       "kw": "And",
       "text": "layout cohérent avec <code>&lt;x-layouts.public&gt;</code>"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "6.6",
     "epic": 6,
     "title": "Sitemap.xml auto-generated",
     "role": "Reader-Gamer Chercheur Google (SEO)",
     "want": "<code>sitemap.xml</code> auto-généré listant toutes les pages publiques",
     "benefit": "Google crawle efficacement (moat compounding evergreen)",
     "ac": [
      {
       "kw": "Given",
       "text": "route <code>GET /sitemap.xml</code>"
      },
      {
       "kw": "When",
       "text": "Googlebot requête"
      },
      {
       "kw": "Then",
       "text": "XML valide <code>&lt;urlset&gt;</code> listant toutes URLs publiques"
      },
      {
       "kw": "And",
       "text": "chaque <code>&lt;url&gt;</code> contient <code>&lt;loc&gt;</code> + <code>&lt;lastmod&gt;</code> (reflète <code>last_updated_at</code> pour reviews — Story 5.11) + <code>&lt;changefreq&gt;</code> + <code>&lt;priority&gt;</code>"
      },
      {
       "kw": "And",
       "text": "reviews <code>priority=0.8</code>, archive <code>0.6</code>, home <code>1.0</code>, /press <code>0.5</code>"
      },
      {
       "kw": "And",
       "text": "mis à jour automatiquement au publish via Article observer (cache invalidation)"
      },
      {
       "kw": "And",
       "text": "<code>robots.txt</code> référence <code>Sitemap: https://skeleton-streamer.dev/sitemap.xml</code>"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "6.7",
     "epic": 6,
     "title": "RSS feed <code>/feed.xml</code> trié par <code>last_updated_at</code>",
     "role": "Returner Ponce-fan (RSS user)",
     "want": "<code>/feed.xml</code> RSS 2.0 valide listant 20 derniers articles triés <code>last_updated_at</code> DESC",
     "benefit": "je suis Alex via mon lecteur RSS",
     "ac": [
      {
       "kw": "Given",
       "text": "route <code>GET /feed.xml</code>"
      },
      {
       "kw": "When",
       "text": "un RSS reader requête"
      },
      {
       "kw": "Then",
       "text": "XML RSS 2.0 valide avec 20 derniers articles"
      },
      {
       "kw": "And",
       "text": "<b>triés par <code>last_updated_at DESC</code></b> (pas <code>published_at</code>) — alerte subscribers des updates majeures"
      },
      {
       "kw": "And",
       "text": "chaque <code>&lt;item&gt;</code> contient <code>&lt;title&gt;</code>, <code>&lt;link&gt;</code>, <code>&lt;description&gt;</code> (verdict 1-3 phrases), <code>&lt;pubDate&gt;</code>, <code>&lt;guid isPermaLink=\"true\"&gt;</code>"
      },
      {
       "kw": "And",
       "text": "Feed Validator W3C valide sans erreur"
      },
      {
       "kw": "And",
       "text": "<code>&lt;x-footer&gt;</code> lien texte \"RSS\" pointe vers <code>/feed.xml</code>"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "6.8",
     "epic": 6,
     "title": "Schema.org structured data on archive pages",
     "role": "Reader-Gamer Chercheur Google",
     "want": "JSON-LD <code>CollectionPage</code> + <code>ItemList</code> sur archive pages",
     "benefit": "Google comprend la structure éditoriale et indexe comme autorité topique",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>/reviews/2026</code>"
      },
      {
       "kw": "When",
       "text": "Googlebot crawle"
      },
      {
       "kw": "Then",
       "text": "<code>&lt;head&gt;</code> contient JSON-LD <code>@type: CollectionPage</code> + <code>mainEntity: {@type: ItemList, itemListElement: [...]}</code>"
      },
      {
       "kw": "And",
       "text": "<code>/reviews/tag/elden-ring</code> similar avec <code>about: {@type: Thing, name: \"Elden Ring\"}</code>"
      },
      {
       "kw": "And",
       "text": "Google Rich Results Test valide sans erreur"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "6.9",
     "epic": 6,
     "title": "Listing <code>/reviews/</code> root page",
     "role": "Reader-Gamer + Browser FOMO",
     "want": "page <code>/reviews/</code> racine listant tous articles paginated cursor",
     "benefit": "j'ai un point d'entrée global sans filtre dimension",
     "ac": [
      {
       "kw": "Given",
       "text": "route <code>GET /reviews/</code> (sans paramètre)"
      },
      {
       "kw": "When",
       "text": "je charge"
      },
      {
       "kw": "Then",
       "text": "rendu <code>&lt;x-reviews.archive-grid&gt;</code> avec 12 derniers + cursor pagination"
      },
      {
       "kw": "And",
       "text": "filtres visibles tablette+ : \"Année\" select, \"Type\" select, \"Tags\" multi-select"
      },
      {
       "kw": "And",
       "text": "mobile &lt;768px : pas de filtres (KISS — utilisateur va sur tag/year pages dédiées)"
      },
      {
       "kw": "And",
       "text": "H1 \"Reviews\" + meta description \"Reviews de jeux par Alex — analyses calmes, qualité éditoriale &gt; hype\""
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "6.10",
     "epic": 6,
     "title": "Pagination breadcrumbs cohérence",
     "role": "Reader-Gamer",
     "want": "breadcrumbs cohérents sur toutes les pages archive",
     "benefit": "je navigue intuitivement sans me perdre",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>/reviews/2026/page/2</code>"
      },
      {
       "kw": "When",
       "text": "je charge"
      },
      {
       "kw": "Then",
       "text": "breadcrumb 1 ligne IBM Plex Sans 13px sous header : <code>Accueil / Reviews / 2026</code>"
      },
      {
       "kw": "And",
       "text": "dernier item <code>text-primary</code> (autres <code>text-secondary</code>)"
      },
      {
       "kw": "And",
       "text": "séparateur <code> / </code> IBM Plex Mono"
      },
      {
       "kw": "And",
       "text": "Schema.org <code>BreadcrumbList</code> JSON-LD injecté"
      },
      {
       "kw": "And",
       "text": "test Pest browser : breadcrumb visible sur 5 pages clés (home, /reviews/, slug, /reviews/2026, /reviews/tag/foo)"
      }
     ],
     "notes": [],
     "status": "backlog"
    }
   ]
  },
  {
   "num": 7,
   "title": "OG Images 3 Tiers + News",
   "phase": "Phase 3/S4 OG ~4j",
   "pitch": "Chaque review tweetée/partagée Reddit/Bluesky devient un mini-poster identifiable hors-site (barre Lava 9+/10 reconnaissable, sobre pour notes faibles, neutre pour news) — <b>système d'identité virale gratuit, wedge partage social CRITICAL S4</b>.",
   "meta": {
    "FRs covered": "FR-OG-1 à 6",
    "NFRs critical": "NFR-SEO-7 (OG 1200×630), NFR-Risk-5 (mitigation P6 génération lente)",
    "ARs": "AR-Ext-4 (Browsershot)",
    "Critère go": "OG image visible Twitter share validator pour 1 review publiée (PRD §10.3 LOCKED)"
   },
   "amendments": [
    "<b>4 templates partagent 80% code</b> (Murat : 1 layout Blade + 4 color schemes — sinon maintenance 4× = drop 2 templates)",
    "<b>Buffer +1j Browsershot</b> (Amelia : Puppeteer headless en CI Docker = 0.5j risque setup)",
    "<b>ArticleSeeder fixture</b> pour tests Pest indépendants d'Epic 5 (1 fixture Article seedée)",
    "Job async + retry 3x + fallback OG statique (mitigation §12.5)"
   ],
   "effort": "4j",
   "status": "backlog",
   "retro": "optional",
   "stories": [
    {
     "id": "7.1",
     "epic": 7,
     "title": "ArticleSeeder fixture for Pest tests",
     "role": "Amelia",
     "want": "<code>database/seeders/ArticleSeederTest.php</code> seedant 4 articles fixtures (1 par tier OG : stellar 9+, solid 7-8, light ≤6, news sans note)",
     "benefit": "Epic 7 tests Pest tournent indépendamment d'Epic 5",
     "ac": [
      {
       "kw": "Given",
       "text": "seeder <code>ArticleSeederTest::run()</code>"
      },
      {
       "kw": "When",
       "text": "appelé depuis <code>Tests\\TestCase::setUp()</code>"
      },
      {
       "kw": "Then",
       "text": "4 articles seedés : <code>stellar-fixture</code> (note 10), <code>solid-fixture</code> (note 8), <code>light-fixture</code> (note 5), <code>news-fixture</code> (type=news, sans note)"
      },
      {
       "kw": "And",
       "text": "chacun a cover URL placeholder valide + game lié (sauf news)"
      },
      {
       "kw": "And",
       "text": "test Pest peut générer OG image sans installer tout le module Reviews"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "7.2",
     "epic": 7,
     "title": "Browsershot + Chrome headless dans container php",
     "role": "Winston",
     "want": "<code>spatie/browsershot</code> installé + Chrome headless dans le container <code>php</code> Docker",
     "benefit": "génération OG via Puppeteer fonctionne en dev + CI + prod",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>composer require spatie/browsershot</code> + Dockerfile mise à jour"
      },
      {
       "kw": "When",
       "text": "Dockerfile build"
      },
      {
       "kw": "Then",
       "text": "Chrome headless installé via <code>apt install chromium</code> + <code>PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium</code>"
      },
      {
       "kw": "And",
       "text": "test smoke <code>Browsershot::html('&lt;h1&gt;test&lt;/h1&gt;')-&gt;screenshot()</code> génère PNG valide"
      },
      {
       "kw": "And",
       "text": "CI GitHub Actions setup-php avec extensions nécessaires"
      },
      {
       "kw": "And",
       "text": "taille image Docker <code>php</code> augmente &lt;100MB (Chromium léger)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "7.3",
     "epic": 7,
     "title": "<code>GenerateOgImage</code> Job async with retry + timeout",
     "role": "Alex-Dev",
     "want": "<code>App\\Modules\\Reviews\\Jobs\\GenerateOgImage</code> async queue Redis avec <code>tries=3</code> + <code>timeout=30s</code> + retry backoff",
     "benefit": "publish review n'est pas bloqué par génération lente (mitigation P6)",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>GenerateOgImage::dispatch($article)</code> après <code>published_at = now()</code>"
      },
      {
       "kw": "When",
       "text": "le job exécute"
      },
      {
       "kw": "Then",
       "text": "<code>Browsershot::html(view(\"og.{$template}\", ['article' =&gt; $article]))-&gt;windowSize(1200, 630)-&gt;screenshot()</code>"
      },
      {
       "kw": "And",
       "text": "sauvegarde <code>public/og/{slug}.png</code> via <code>Storage::disk('public_og')-&gt;put(...)</code>"
      },
      {
       "kw": "And",
       "text": "job class <code>public $tries = 3; public $timeout = 30;</code>"
      },
      {
       "kw": "And",
       "text": "retry backoff exponentiel : 30s → 2min → 5min"
      },
      {
       "kw": "And",
       "text": "si 3 retries échouent → fallback OG statique (Story 7.8)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "7.4",
     "epic": 7,
     "title": "Template <code>og/review-stellar.blade.php</code> (note ≥9 — barre Lava)",
     "role": "Caravaggio",
     "want": "template <code>og/review-stellar.blade.php</code> pour notes ≥9 avec barre Lava bottom + note 180px Lava + accent visuel fort",
     "benefit": "les reviews exceptionnelles sont visuellement identifiables hors-site",
     "ac": [
      {
       "kw": "Given",
       "text": "template utilisant <code>&lt;x-og.layout :article=\"$article\"&gt;</code>"
      },
      {
       "kw": "When",
       "text": "rendu avec article note 10"
      },
      {
       "kw": "Then",
       "text": "background <code>#0A0A0B</code> flat"
      },
      {
       "kw": "And",
       "text": "cover game left 40% width"
      },
      {
       "kw": "And",
       "text": "title H1 IBM Plex Sans Bold auto-shrink CSS selon longueur"
      },
      {
       "kw": "And",
       "text": "note display \"10 / 10\" 180px IBM Plex Sans Bold couleur Lava <code>#FF5722</code>"
      },
      {
       "kw": "And",
       "text": "<b>barre Lava 8px</b> bottom horizontale (signal fort réservé tier stellar)"
      },
      {
       "kw": "And",
       "text": "logo Alex discret bottom-right 32px"
      },
      {
       "kw": "And",
       "text": "canvas 1200×630"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "7.5",
     "epic": 7,
     "title": "Template <code>og/review-solid.blade.php</code> (note 7-8 — accent succès discret)",
     "role": "Caravaggio",
     "want": "template <code>og/review-solid.blade.php</code> pour notes 7-8 avec note 180px texte primaire + accent état succès discret + pas de barre Lava",
     "benefit": "les bonnes reviews sont positives sans \"spammer\" le signal Lava",
     "ac": [
      {
       "kw": "Given",
       "text": "article note 8"
      },
      {
       "kw": "When",
       "text": "template rendu"
      },
      {
       "kw": "Then",
       "text": "<b>pas de barre Lava</b>"
      },
      {
       "kw": "And",
       "text": "note \"8 / 10\" 180px couleur <code>rgba(255,255,255,.92)</code> (text-primary)"
      },
      {
       "kw": "And",
       "text": "accent discret <code>#22C55E</code> (state-ok) sur séparateur 2px sous le titre"
      },
      {
       "kw": "And",
       "text": "layout strictement identique à stellar (80% code partagé via <code>&lt;x-og.layout&gt;</code>)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "7.6",
     "epic": 7,
     "title": "Template <code>og/review-light.blade.php</code> (note ≤6 — sobre)",
     "role": "Caravaggio",
     "want": "template <code>og/review-light.blade.php</code> pour notes ≤6 avec note 180px texte secondaire + pas d'accent",
     "benefit": "les reviews négatives gardent un ton sobre honnête (anti-clickbait)",
     "ac": [
      {
       "kw": "Given",
       "text": "article note 5"
      },
      {
       "kw": "When",
       "text": "template rendu"
      },
      {
       "kw": "Then",
       "text": "note \"5 / 10\" 180px couleur <code>rgba(255,255,255,.60)</code> (text-secondary)"
      },
      {
       "kw": "And",
       "text": "<b>aucun accent visuel</b> (ni Lava, ni succès)"
      },
      {
       "kw": "And",
       "text": "ton sobre, honnête"
      },
      {
       "kw": "And",
       "text": "layout identique aux 2 autres tier (80% code partagé)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "7.7",
     "epic": 7,
     "title": "Template <code>og/news.blade.php</code> (type ≠ review — sans note)",
     "role": "Caravaggio",
     "want": "template <code>og/news.blade.php</code> pour <code>type ∈ {news, preview}</code> sans note + badge \"NEWS\" ou \"PREVIEW\" Lava bottom-left",
     "benefit": "les articles non-reviews gardent une identité distinctive",
     "ac": [
      {
       "kw": "Given",
       "text": "article type=news"
      },
      {
       "kw": "When",
       "text": "template rendu"
      },
      {
       "kw": "Then",
       "text": "pas de note affichée"
      },
      {
       "kw": "And",
       "text": "title 100% width surface (pas split 40/60)"
      },
      {
       "kw": "And",
       "text": "badge <b>\"NEWS\"</b> en haut-gauche 24px IBM Plex Mono Lava <code>#FF5722</code> (autorisé contexte OG — exception explicite)"
      },
      {
       "kw": "And",
       "text": "Sous-titre verdict 1 ligne si présent"
      },
      {
       "kw": "Given",
       "text": "article type=preview"
      },
      {
       "kw": "Then",
       "text": "badge \"PREVIEW\" remplace \"NEWS\""
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "7.8",
     "epic": 7,
     "title": "Composition commune 80% partagée + fallback statique",
     "role": "Murat",
     "want": "layout <code>&lt;x-og.layout :article :template&gt;</code> partagé entre 4 templates + fallback statique <code>public/og/default.png</code>",
     "benefit": "maintenance 1× (pas 4×) + jamais d'image OG manquante en prod",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>resources/views/components/og/layout.blade.php</code>"
      },
      {
       "kw": "When",
       "text": "je l'inspecte"
      },
      {
       "kw": "Then",
       "text": "il contient 80% du HTML/CSS partagé (background, cover slot, title slot, logo slot)"
      },
      {
       "kw": "And",
       "text": "chaque template <code>og/{tier}.blade.php</code> extend ce layout et fournit uniquement le slot <code>note</code> ou <code>badge</code> différenciant"
      },
      {
       "kw": "Given",
       "text": "<code>GenerateOgImage</code> job échoue après 3 retries"
      },
      {
       "kw": "When",
       "text": "un visiteur partage l'article sur Twitter"
      },
      {
       "kw": "Then",
       "text": "<code>&lt;meta property=\"og:image\" content=\"https://skeleton-streamer.dev/og/default.png\"&gt;</code> injecté"
      },
      {
       "kw": "And",
       "text": "Pulse alert sur <code>failed_jobs</code> count &gt;0 sur GenerateOgImage"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "7.9",
     "epic": 7,
     "title": "OG generation on publish via Article observer",
     "role": "Alex-Auteur",
     "want": "<code>ArticleObserver</code> qui dispatch <code>GenerateOgImage::dispatch($article)</code> automatiquement au publish ou update",
     "benefit": "je n'oublie jamais de générer l'OG manuellement",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>App\\Modules\\Reviews\\Observers\\ArticleObserver</code>"
      },
      {
       "kw": "When",
       "text": "un Article est publié pour la première fois (<code>published_at</code> set + previous null)"
      },
      {
       "kw": "Then",
       "text": "observer call <code>GenerateOgImage::dispatch($article)</code>"
      },
      {
       "kw": "Given",
       "text": "Article édité post-publish avec changement <code>title</code>, <code>note</code>, <code>cover_url</code> ou <code>type</code>"
      },
      {
       "kw": "Then",
       "text": "observer dispatch également (régénère OG)"
      },
      {
       "kw": "And",
       "text": "observer évite dispatch si aucun champ visible OG n'a changé (<code>isDirty(['title', 'note', 'cover_url', 'type'])</code>)"
      },
      {
       "kw": "And",
       "text": "feature flag <code>og-dynamic-pre-render</code> (Pennant AR-Flag-1) permet de désactiver en prod si surcharge"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "7.10",
     "epic": 7,
     "title": "Meta tags OG + Twitter Card in <code>&lt;head&gt;</code>",
     "role": "Reader-Gamer + social shares",
     "want": "meta tags <code>og:image</code>, <code>og:title</code>, <code>og:description</code>, <code>twitter:card</code> injectés dans <code>&lt;head&gt;</code> de <code>/reviews/{slug}</code>",
     "benefit": "partage social affiche le mini-poster signé Alex",
     "ac": [
      {
       "kw": "Given",
       "text": "article publié avec OG image générée"
      },
      {
       "kw": "When",
       "text": "je render <code>/reviews/{slug}</code>"
      },
      {
       "kw": "Then",
       "text": "<code>&lt;head&gt;</code> contient :"
      },
      {
       "kw": "And",
       "text": "Twitter Card Validator valide"
      },
      {
       "kw": "And",
       "text": "Facebook OG Debugger valide"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "7.11",
     "epic": 7,
     "title": "Pest snapshot PixelMatch (4 PNG reference fixtures)",
     "role": "Murat",
     "want": "tests Pest visual regression via PixelMatch (4 PNG references en <code>tests/fixtures/og/</code>)",
     "benefit": "les régressions visuelles non intentionnelles sont détectées en CI",
     "ac": [
      {
       "kw": "Given",
       "text": "4 PNG references commités dans <code>tests/fixtures/og/{stellar,solid,light,news}.png</code>"
      },
      {
       "kw": "When",
       "text": "test Pest <code>OgImageVariantTest</code> génère OG depuis fixture article + compare via PixelMatch"
      },
      {
       "kw": "Then",
       "text": "assert diff &lt;0.5% pixels (tolerance anti-aliasing)"
      },
      {
       "kw": "And",
       "text": "si diff &gt;0.5% → test fail + génère diff image <code>tests/fixtures/og/diff-{tier}.png</code>"
      },
      {
       "kw": "And",
       "text": "CI workflow Browsershot configuré headless"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "7.12",
     "epic": 7,
     "title": "Pulse alert on failed OG jobs",
     "role": "Murat",
     "want": "Pulse card \"Failed OG generation\" + alert Discord si &gt;3 fails/24h",
     "benefit": "dégradation silencieuse OG generation est catchée",
     "ac": [
      {
       "kw": "Given",
       "text": "Pulse card configurée sur table <code>failed_jobs WHERE queue = 'og-generation'</code>"
      },
      {
       "kw": "When",
       "text": "je consulte <code>/pulse</code>"
      },
      {
       "kw": "Then",
       "text": "card visible avec count failed jobs 24h"
      },
      {
       "kw": "And",
       "text": "si count &gt;3 → notification Discord webhook"
      },
      {
       "kw": "And",
       "text": "chaque failed job entry contient article_id + exception trace pour debug"
      }
     ],
     "notes": [],
     "status": "backlog"
    }
   ]
  },
  {
   "num": 8,
   "title": "Press Kit + Trust Signaling + Bouton Copier UTM",
   "phase": "Phase 3/S4 press ~4j",
   "pitch": "Game Dev / PR studio arrive sur <code>/press</code> via Keymailer, scanne stats P50 médianes + bio FR+EN + 3 reviews récentes en &lt;30s, télécharge SVG individuel en 1 clic, <b>copie le lien press kit UTM-tracké</b> pour shortlist Alex.",
   "meta": {
    "FRs covered": "FR-Press-1 à 9 (toutes — y compris <b>FR-Press-7 bouton copier UTM</b> déplacé d'Epic 9)",
    "NFRs critical": "NFR-Metric-8/9 (downloads SVG + taux réponse pitchs Keymailer), NFR-Risk-3 (mitigation P3 crédibilité M+1)",
    "ARs": "AR-Ext-3 (Resend SMTP)",
    "Critère go": "downloads SVG individuels &gt;5/mois M+3 (PRD §4.2)"
   },
   "amendments": [
    "<b>Bouton \"Copier le lien press kit\" UTM-tracké déplacé Epic 9 → Epic 8</b> (Amelia : cohérent JTBD n°3 unifié)",
    "Tenant-aware Victor R6 confirmé (utilise <code>Streamer</code> model d'Epic 1 avec <code>tagline + bio_fr + bio_en + photo_url</code>)",
    "<code>&lt;x-press.trust-section&gt;</code> slots data + methodology (Pattern 2 — Wirecutter trust signaling)",
    "Méthodologie stats P50 à 1 clic max (lien page dédiée)"
   ],
   "effort": "4j",
   "status": "backlog",
   "retro": "optional",
   "stories": [
    {
     "id": "8.1",
     "epic": 8,
     "title": "<code>&lt;x-press.kit&gt;</code> page <code>/press</code> tenant-aware (hiérarchie Stats &gt; Photo &gt; Bio)",
     "role": "Game Dev / PR studio",
     "want": "page <code>/press</code> avec hiérarchie verticale stricte Stats &gt; Photo &gt; Bio (casse instinct \"photo first\")",
     "benefit": "je décide en &lt;30s si gifter une clé à Alex",
     "ac": [
      {
       "kw": "Given",
       "text": "route <code>GET /press</code> → <code>PressKitController@show</code>"
      },
      {
       "kw": "When",
       "text": "je charge la page sur desktop 13\" MacBook Air"
      },
      {
       "kw": "Then",
       "text": "max-width container 960px centered"
      },
      {
       "kw": "And",
       "text": "structure verticale stricte :"
      },
      {
       "kw": "And",
       "text": "composant <code>&lt;x-press.kit :streamer=\"$streamer\"&gt;</code> lit depuis <code>$streamer</code> (Streamer model Epic 1) — pas hardcoded"
      },
      {
       "kw": "And",
       "text": "TTFC &lt;1.5s mobile 4G"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "8.2",
     "epic": 8,
     "title": "<code>&lt;x-press.stats-block&gt;</code> P50 médianes + sparkline 7j",
     "role": "Game Dev",
     "want": "bloc stats P50 médianes (viewers concurrents + heures stream + nb VODs) avec sparkline 7j",
     "benefit": "je vois la légitimité d'Alex en 5s sans vanity metrics",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>&lt;x-press.stats-block :data=\"$stats\"&gt;</code>"
      },
      {
       "kw": "When",
       "text": "rendu"
      },
      {
       "kw": "Then",
       "text": "3-col grid desktop / 1-col mobile :"
      },
      {
       "kw": "And",
       "text": "<b>jamais de mean</b> — médianes P50 uniquement (anti-vanity Ponce)"
      },
      {
       "kw": "And",
       "text": "<b>jamais de followers Twitch</b> (vanity, gameable)"
      },
      {
       "kw": "And",
       "text": "sparkline 7j stats computed depuis Twitch Helix <code>viewers_per_stream</code> last 7 days"
      },
      {
       "kw": "And",
       "text": "Schema.org <code>Person</code> JSON-LD avec <code>interactionStatistic</code> sur ces 3 metrics"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "8.3",
     "epic": 8,
     "title": "<code>&lt;x-press.trust-section&gt;</code> slots data + methodology",
     "role": "Caravaggio + Murat",
     "want": "composant <code>&lt;x-press.trust-section&gt;</code> avec slots <code>data</code> + <code>methodology</code> (Pattern 2 trust signaling unifié)",
     "benefit": "PR studio peut vérifier la méthodologie stats en 1 clic max (Wirecutter pattern)",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>&lt;x-press.trust-section&gt;</code> avec 2 slots"
      },
      {
       "kw": "When",
       "text": "rendu"
      },
      {
       "kw": "Then",
       "text": "slot <code>data</code> affiche les stats P50 (Story 8.2)"
      },
      {
       "kw": "And",
       "text": "slot <code>methodology</code> affiche un lien <code>&lt;a href=\"/press/methodologie\" class=\"text-secondary underline\"&gt;Comment je calcule ces stats →&lt;/a&gt;</code>"
      },
      {
       "kw": "And",
       "text": "clic mène à page dédiée <code>/press/methodologie</code> avec explication détaillée (script Twitch Helix + agrégation P50 + exclusions)"
      },
      {
       "kw": "And",
       "text": "composant réutilisable pour autres pages (footer, README \"as a template\" Epic 11)"
      },
      {
       "kw": "And",
       "text": "historique transparent affiché : \"X articles publiés sur Y mois\" + \"Site lancé le DD/MM/YYYY\""
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "8.4",
     "epic": 8,
     "title": "Méthodologie page dédiée <code>/press/methodologie</code>",
     "role": "Game Dev sceptique",
     "want": "page <code>/press/methodologie</code> expliquant comment Alex calcule ses stats P50",
     "benefit": "je peux vérifier la méthodologie en 30s avant de gifter",
     "ac": [
      {
       "kw": "Given",
       "text": "route <code>GET /press/methodologie</code> → <code>PressKitController@methodology</code>"
      },
      {
       "kw": "When",
       "text": "je charge la page"
      },
      {
       "kw": "Then",
       "text": "contenu Markdown statique explique :"
      },
      {
       "kw": "And",
       "text": "breadcrumb <code>Accueil / Presse / Méthodologie</code>"
      },
      {
       "kw": "And",
       "text": "lien retour vers <code>/press</code> discret"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "8.5",
     "epic": 8,
     "title": "<code>&lt;x-press.download-button&gt;</code> SVG/PNG/Kit individuel 1 clic",
     "role": "Game Dev (zip-averse)",
     "want": "bouton SVG/PNG/Kit chacun individuel — 1 clic = 1 fichier",
     "benefit": "je télécharge le format que je veux sans déziper rien",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>&lt;x-press.download-button :file :format&gt;</code> rendu sur <code>/press</code>"
      },
      {
       "kw": "When",
       "text": "je vois les options"
      },
      {
       "kw": "Then",
       "text": "3 boutons horizontaux desktop / vertical mobile : \"SVG (logo vectoriel)\" / \"PNG (logo 1024px)\" / \"Kit complet (.zip)\""
      },
      {
       "kw": "And",
       "text": "chaque bouton secondary (<code>bg-surface text-primary border-border</code>) — <b>pas de Lava</b>"
      },
      {
       "kw": "And",
       "text": "clic = direct download (<code>&lt;a href=\"/press/assets/logo.svg\" download&gt;</code>)"
      },
      {
       "kw": "And",
       "text": "<b>pas de modale \"Quel format ?\"</b> (anti-friction)"
      },
      {
       "kw": "And",
       "text": "<b>kit complet zip optionnel</b> (Alex peut décider de le retirer s'il préfère SVG/PNG seuls — vote Sally R5 : SVG seul suffit pour PR studios sérieux)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "8.6",
     "epic": 8,
     "title": "<code>&lt;x-press.contact-form&gt;</code> Livewire + Resend driver",
     "role": "Game Dev",
     "want": "formulaire contact simple (nom, email, sujet, message) en bas de <code>/press</code> avec validation real-time",
     "benefit": "je peux pitcher Alex directement sans passer par Twitter DM",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>&lt;x-press.contact-form&gt;</code> composant Livewire 3"
      },
      {
       "kw": "When",
       "text": "je remplis le form sur <code>/press</code>"
      },
      {
       "kw": "Then",
       "text": "validation real-time <code>wire:model.debounce.500ms</code> avec messages sous chaque champ"
      },
      {
       "kw": "And",
       "text": "Honeypot anti-spam (champ caché Laravel natif)"
      },
      {
       "kw": "And",
       "text": "rate limiting 3/h/IP (Story FR-Sec-3)"
      },
      {
       "kw": "And",
       "text": "submit envoie email via Resend driver (OQ8 LOCKED) à <code>$settings-&gt;contact_email</code>"
      },
      {
       "kw": "And",
       "text": "log Spatie ActivityLog \"press_contact_received\" avec metadata (timestamp, IP redacted, sujet)"
      },
      {
       "kw": "And",
       "text": "toast success \"Message envoyé. Alex répondra sous 48h.\" + form reset"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "8.7",
     "epic": 8,
     "title": "<code>&lt;x-cta.copy-press-link&gt;</code> UTM-tracked Alpine clipboard",
     "role": "Game Dev (shortlist Alex)",
     "want": "bouton \"Copier le lien press kit\" UTM-tracké en fin de <code>/press</code>",
     "benefit": "je copie un lien tracké pour le mettre dans mon shortlist sheet et Alex tracke JTBD n°3 (Mary P5)",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>&lt;x-cta.copy-press-link /&gt;</code> rendu en fin <code>/press</code>"
      },
      {
       "kw": "When",
       "text": "je clique le bouton"
      },
      {
       "kw": "Then",
       "text": "Alpine.js <code>@click=\"navigator.clipboard.writeText('https://skeleton-streamer.dev/press?utm_source=keymailer&amp;utm_medium=press-kit&amp;utm_campaign=copy-link&amp;utm_content={timestamp_hash}')\"</code>"
      },
      {
       "kw": "And",
       "text": "toast success \"Lien copié — UTM ajouté\" 2s"
      },
      {
       "kw": "And",
       "text": "événement Plausible <code>press_link_copied</code> dispatché avec props <code>{utm_campaign}</code>"
      },
      {
       "kw": "And",
       "text": "bouton secondary (pas Lava)"
      },
      {
       "kw": "And",
       "text": "copy : \"Copier le lien press kit (Keymailer-ready)\""
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "8.8",
     "epic": 8,
     "title": "Bio FR + EN bilingue display + Markdown",
     "role": "Game Dev EN-speaker",
     "want": "bio FR + EN affichée sur <code>/press</code> avec toggle ou côte-à-côte",
     "benefit": "je lis dans ma langue préférée pour évaluer Alex",
     "ac": [
      {
       "kw": "Given",
       "text": "Streamer model avec <code>bio_fr</code> + <code>bio_en</code> (Epic 1 Story 1.3)"
      },
      {
       "kw": "When",
       "text": "je charge <code>/press</code>"
      },
      {
       "kw": "Then",
       "text": "desktop : 2-col côte-à-côte (\"Bio FR\" / \"Bio EN\") avec headers IBM Plex Sans 14px mono"
      },
      {
       "kw": "And",
       "text": "mobile : stacked verticalement, FR d'abord"
      },
      {
       "kw": "And",
       "text": "Markdown parsé (<code>&lt;p&gt;</code> tags supportés)"
      },
      {
       "kw": "And",
       "text": "si <code>bio_en</code> vide (Alex pas encore écrit) → afficher uniquement FR + petit note \"EN version coming soon\""
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "8.9",
     "epic": 8,
     "title": "3 dernières reviews preview sur <code>/press</code>",
     "role": "Game Dev",
     "want": "3 dernières reviews publiées affichées sur <code>/press</code> avec cover + titre + note + verdict 1 ligne",
     "benefit": "je vérifie la qualité éditoriale en 5s avant de pitcher",
     "ac": [
      {
       "kw": "Given",
       "text": "section \"Recent Reviews\" sur <code>/press</code>"
      },
      {
       "kw": "When",
       "text": "je la vois"
      },
      {
       "kw": "Then",
       "text": "3 cards horizontales (desktop) / stackées (mobile) avec : cover thumbnail, H4 titre, note display, verdict tronqué 80 chars, lien vers <code>/reviews/{slug}</code>"
      },
      {
       "kw": "And",
       "text": "triées par <code>published_at DESC</code> (derniers 3 reviews, pas news/preview)"
      },
      {
       "kw": "And",
       "text": "si &lt;3 reviews publiées (M0 J1 capital = 3 articles — PRD §6.3) → afficher ce qu'on a + texte \"Premières reviews — la collection se construit\""
      },
      {
       "kw": "And",
       "text": "<b>état nominal designed</b> (pas placeholder Lorem ipsum)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "8.10",
     "epic": 8,
     "title": "Tests Pest e2e Press Kit journey",
     "role": "Murat",
     "want": "test Pest Browser end-to-end <code>PressKitJourneyTest</code> simulant Game Dev arrivant Keymailer",
     "benefit": "le journey complet (Story 3 step-10) est validé automatiquement",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>tests/Browser/PressKitJourneyTest.php</code> avec Pest Browser"
      },
      {
       "kw": "When",
       "text": "test simule visite <code>/press?utm_source=keymailer</code>"
      },
      {
       "kw": "Then",
       "text": "assert order DOM : Stats &gt; TrustSection &gt; Photo &gt; Bio &gt; 3 reviews preview &gt; Download buttons &gt; Copy link &gt; Contact form"
      },
      {
       "kw": "And",
       "text": "simule click \"SVG download\" → file téléchargé"
      },
      {
       "kw": "And",
       "text": "simule click \"Copier le lien\" → clipboard contient URL avec UTM"
      },
      {
       "kw": "And",
       "text": "simule submit contact form → Resend email mock appelé"
      },
      {
       "kw": "And",
       "text": "Lighthouse mobile sur <code>/press</code> score ≥90 a11y + ≥85 perf"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "8.11",
     "epic": 8,
     "title": "Plausible events <code>press_svg_download</code> + <code>press_link_copied</code>",
     "role": "Mary",
     "want": "événements Plausible <code>press_svg_download</code> + <code>press_link_copied</code> + <code>press_contact_submitted</code>",
     "benefit": "KPI downloads SVG &gt;5/mois M+3 + clics copier-lien &gt;10/mois M+6 mesurables",
     "ac": [
      {
       "kw": "Given",
       "text": "chaque action sur <code>/press</code> instrumentée"
      },
      {
       "kw": "When",
       "text": "Game Dev télécharge SVG"
      },
      {
       "kw": "Then",
       "text": "<code>plausible('press_svg_download', {props: {format: 'svg'}})</code> dispatché"
      },
      {
       "kw": "Given",
       "text": "Game Dev clic \"Copier le lien\""
      },
      {
       "kw": "Then",
       "text": "<code>plausible('press_link_copied', {props: {utm_campaign}})</code>"
      },
      {
       "kw": "Given",
       "text": "Game Dev submit contact"
      },
      {
       "kw": "Then",
       "text": "<code>plausible('press_contact_submitted', {props: {subject_category}})</code>"
      },
      {
       "kw": "And",
       "text": "dashboard Plausible expose ces 3 events avec drill-down"
      },
      {
       "kw": "And",
       "text": "alerte M+3 si downloads &lt;5/mois (signal pitch Keymailer pas convertit)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "8.12",
     "epic": 8,
     "title": "SEO meta + Schema.org <code>Person</code> pour <code>/press</code>",
     "role": "Reader-Gamer Chercheur Google (indirect discovery)",
     "want": "meta description optimisée + Schema.org <code>Person</code> JSON-LD sur <code>/press</code>",
     "benefit": "<code>/press</code> rank Google sur \"Alex streamer press kit\" + Schema.org Person améliore knowledge graph",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>/press</code> <code>&lt;head&gt;</code>"
      },
      {
       "kw": "When",
       "text": "je l'inspecte"
      },
      {
       "kw": "Then",
       "text": "<code>&lt;title&gt;Press Kit — Alex (Streamer FR)&lt;/title&gt;</code>"
      },
      {
       "kw": "And",
       "text": "<code>&lt;meta name=\"description\" content=\"Stats P50 + bio + downloads — kit presse Alex\"&gt;</code>"
      },
      {
       "kw": "And",
       "text": "JSON-LD <code>@type: Person</code> avec <code>name</code>, <code>url</code>, <code>image</code>, <code>sameAs: [twitter_handle, twitch, youtube, discord]</code>, <code>description: bio_en</code>, <code>interactionStatistic</code> (stats P50)"
      },
      {
       "kw": "And",
       "text": "Google Rich Results Test valide"
      },
      {
       "kw": "And",
       "text": "Sitemap.xml référence <code>/press</code> priority 0.5"
      }
     ],
     "notes": [],
     "status": "backlog"
    }
   ]
  },
  {
   "num": 9,
   "title": "Admin Workflow + Comments Dormant + UTM Infrastructure",
   "phase": "Phase 3/S5 ~2.5j",
   "pitch": "Alex publie en &lt;10min même 23h fatigué (brouillon réseaux sociaux copiable Filament — texte Twitter/Mastodon/Bluesky pré-formaté) ; infrastructure Comments en code dormant activable M+1 sur 3 signaux mesurables (Akismet pré-câblé + feature flag <code>comments.enabled=false</code>) ; UTM-builder centralisé + Plausible events.",
   "meta": {
    "FRs covered": "FR-Reviews-9 (comments OFF J1 + Akismet dormant), FR-Admin-5 (brouillon social copiable S5), FR-Admin-8 (rate limiting login)",
    "ARs": "AR-Flag-1 à 4 (Pennant flags v1)",
    "Critère go": "UTM dev gifting trackable bout en bout (test E2E faux UTM — PRD §10.3 LOCKED)"
   },
   "amendments": [
    "<b>Epic 10 initial + résidu Epic 9 dissous fusionnés en Epic 9 final</b> (Amelia : S5 Polish — fusion logique S5 sprint)",
    "<b>OQ1+OQ2 RÉVISÉS</b> confirmés (party-mode round 4) : Comments OFF J1 + activation conditionnelle M+1 sur 3 signaux (≥3 demandes Reader-Gamer prouvées + Akismet pré-câblé + budget modération &lt;30min/sem)",
    "<b>Pest OWASP A02 (Crypto) + A04 (Insecure Design) activés au merge Epic 9</b> (Murat : cookie secure flags + rate limits)",
    "UTM-builder helper Laravel + Plausible events <code>cta_post_read_click</code> (props platform + slug)"
   ],
   "effort": "2.5j",
   "status": "backlog",
   "retro": "optional",
   "stories": [
    {
     "id": "9.1",
     "epic": 9,
     "title": "Brouillon réseaux sociaux Filament (Twitter/Mastodon/Bluesky)",
     "role": "Alex-Auteur",
     "want": "action Filament \"Générer brouillon social\" sur ArticleResource qui pré-formate texte pour Twitter/Mastodon/Bluesky",
     "benefit": "je copy-paste le brouillon dans mes apps sociales en &lt;30s post-publish, pas d'API auto-publish v1",
     "ac": [
      {
       "kw": "Given",
       "text": "ArticleResource avec action <code>GenerateSocialDraft</code> custom"
      },
      {
       "kw": "When",
       "text": "je clique l'action sur une review publiée"
      },
      {
       "kw": "Then",
       "text": "modale ouvre 3 tabs (Twitter / Mastodon / Bluesky) avec textarea pré-rempli :"
      },
      {
       "kw": "And",
       "text": "bouton \"Copier\" sur chaque tab → clipboard"
      },
      {
       "kw": "And",
       "text": "URL inclut UTM <code>?utm_source=twitter|mastodon|bluesky&amp;utm_medium=organic&amp;utm_campaign={slug}</code>"
      },
      {
       "kw": "And",
       "text": "<b>pas d'API auto-publish v1</b>"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "9.2",
     "epic": 9,
     "title": "Comments migrations dormantes (table + columns)",
     "role": "Murat + John",
     "want": "migration <code>2026_03_15_create_comments_table.php</code> qui crée la table comments mais le module est désactivé par feature flag",
     "benefit": "activation M+1 = juste flip un flag, pas re-migration",
     "ac": [
      {
       "kw": "Given",
       "text": "migration <code>create_comments_table</code>"
      },
      {
       "kw": "When",
       "text": "<code>php artisan migrate</code>"
      },
      {
       "kw": "Then",
       "text": "table <code>comments</code> créée avec colonnes : <code>id</code>, <code>streamer_id BIGINT NOT NULL</code>, <code>article_id BIGINT FK articles</code>, <code>name VARCHAR(80)</code>, <code>email VARCHAR(255) hashed</code>, <code>body TEXT</code>, <code>ip_hash VARCHAR(64)</code>, <code>is_approved BOOLEAN DEFAULT false</code>, <code>is_spam BOOLEAN DEFAULT false</code>, <code>flagged_count INT DEFAULT 0</code>, <code>timestamps</code>"
      },
      {
       "kw": "And",
       "text": "index <code>(streamer_id, article_id, is_approved, created_at DESC)</code>"
      },
      {
       "kw": "And",
       "text": "modèle <code>Comment</code> créé avec trait <code>BelongsToStreamer</code> + relation <code>belongsTo Article</code>"
      },
      {
       "kw": "And",
       "text": "<b>AUCUNE route publique ne POST vers <code>/comments</code></b> (module désactivé)"
      },
      {
       "kw": "And",
       "text": "AUCUNE Filament Resource pour comments en v1"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "9.3",
     "epic": 9,
     "title": "Akismet pré-câblé en code dormant",
     "role": "Murat",
     "want": "service <code>AkismetClient</code> + interface <code>SpamCheckerInterface</code> câblés mais désactivés",
     "benefit": "activation M+1 = juste binding container + flag flip, pas refactor",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>composer require tijsverkoyen/akismet</code> + <code>AkismetClient implements SpamCheckerInterface</code>"
      },
      {
       "kw": "When",
       "text": "je consulte le code"
      },
      {
       "kw": "Then",
       "text": "interface définit <code>check(Comment $comment): bool</code> + <code>submitSpam(Comment $comment): void</code> + <code>submitHam(Comment $comment): void</code>"
      },
      {
       "kw": "And",
       "text": "<code>AkismetClient</code> implémente avec clé <code>AKISMET_API_KEY</code> dans <code>.env</code>"
      },
      {
       "kw": "And",
       "text": "binding dans <code>AppServiceProvider</code> conditionnel sur <code>Feature::active('comments-akismet')</code>"
      },
      {
       "kw": "And",
       "text": "<b>AUCUN appel Akismet en v1</b> (interface jamais instanciée)"
      },
      {
       "kw": "And",
       "text": "doc <code>docs/process/07-comments-activation-m1.md</code> explique procédure"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "9.4",
     "epic": 9,
     "title": "Feature flag <code>comments-enabled</code> Pennant",
     "role": "John + Alex",
     "want": "feature flag <code>comments-enabled</code> Pennant + scope global",
     "benefit": "activation conditionnelle M+1 = <code>php artisan pennant:activate comments-enabled</code>",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>App\\Core\\Features\\CommentsFeature</code> définie + registrée"
      },
      {
       "kw": "When",
       "text": "v1 J0"
      },
      {
       "kw": "Then",
       "text": "flag <code>comments-enabled</code> est <code>false</code> par défaut"
      },
      {
       "kw": "And",
       "text": "controllers Reviews check <code>Feature::active('comments-enabled')</code> avant render section comments"
      },
      {
       "kw": "And",
       "text": "Filament <code>ArticleResource</code> cache la section \"Comments enabled?\" toggle (ADR-0001)"
      },
      {
       "kw": "And",
       "text": "activation runtime exclusive via CLI : <code>php artisan pennant:activate comments-enabled</code>"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "9.5",
     "epic": 9,
     "title": "Documentation activation M+1 (3 signaux mesurables)",
     "role": "John",
     "want": "doc <code>docs/process/07-comments-activation-m1.md</code> documentant les 3 signaux mesurables pour activation M+1",
     "benefit": "la décision M+1 est evidence-based",
     "ac": [
      {
       "kw": "Given",
       "text": "doc <code>docs/process/07-comments-activation-m1.md</code>"
      },
      {
       "kw": "When",
       "text": "je la lis"
      },
      {
       "kw": "Then",
       "text": "elle documente les <b>3 signaux mesurables</b> :"
      },
      {
       "kw": "And",
       "text": "procédure 5-min activation : flip flag + déploiement + monitoring Pulse"
      },
      {
       "kw": "And",
       "text": "procédure kill switch (<code>pennant:deactivate comments-enabled</code>)"
      },
      {
       "kw": "And",
       "text": "doc référencée dans CLAUDE.md + README"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "9.6",
     "epic": 9,
     "title": "UTM-builder Laravel helper centralisé",
     "role": "Alex-Dev",
     "want": "helper <code>App\\Core\\Support\\UtmBuilder</code> centralisé pour générer URLs UTM-tracked",
     "benefit": "format UTM cohérent + 1 source de vérité",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>UtmBuilder</code> class"
      },
      {
       "kw": "When",
       "text": "je l'utilise"
      },
      {
       "kw": "Then",
       "text": "méthode statique <code>UtmBuilder::make(string $url, array $params): string</code>"
      },
      {
       "kw": "And",
       "text": "signature : <code>UtmBuilder::make('https://twitter.com/alex', ['source' =&gt; 'site', 'medium' =&gt; 'post-read-cta', 'campaign' =&gt; $slug, 'content' =&gt; 'twitter'])</code>"
      },
      {
       "kw": "And",
       "text": "params snake_case auto-convertis en <code>utm_*</code> querystring"
      },
      {
       "kw": "And",
       "text": "test Pest covers : URL existing query + URL hash + encoding spéciaux"
      },
      {
       "kw": "And",
       "text": "utilisé dans : <code>&lt;x-cta.post-read&gt;</code> (Epic 5), <code>&lt;x-cta.copy-press-link&gt;</code> (Epic 8), GenerateSocialDraft (Story 9.1)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "9.7",
     "epic": 9,
     "title": "Plausible events centralisés (props validation)",
     "role": "Mary",
     "want": "service <code>PlausibleEvents</code> centralise noms d'événements + props attendues",
     "benefit": "typos évitées + props validées + dashboard cohérent",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>PlausibleEvents</code> enum ou class"
      },
      {
       "kw": "When",
       "text": "je l'utilise"
      },
      {
       "kw": "Then",
       "text": "liste événements : <code>home_view</code> (state), <code>cta_post_read_click</code> (platform, slug), <code>press_svg_download</code> (format), <code>press_link_copied</code> (utm_campaign), <code>press_contact_submitted</code> (subject_category)"
      },
      {
       "kw": "And",
       "text": "méthode <code>PlausibleEvents::track(string $event, array $props): void</code> valide props vs schema (throw en dev/staging, log warning prod)"
      },
      {
       "kw": "And",
       "text": "envoie via plausible.js OU API server-side"
      },
      {
       "kw": "And",
       "text": "test Pest covers : missing required prop, extra prop, invalid value"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "9.8",
     "epic": 9,
     "title": "Rate limiting <code>/admin/login</code> 5/min/IP",
     "role": "Murat",
     "want": "rate limiting Laravel sur <code>/admin/login</code> 5/min/IP avec délai exponentiel",
     "benefit": "brute force admin bloqué",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>RouteServiceProvider</code> avec rate limiter <code>admin-login</code>"
      },
      {
       "kw": "When",
       "text": "<code>RateLimiter::for('admin-login', fn ($request) =&gt; Limit::perMinute(5)-&gt;by($request-&gt;ip()))</code>"
      },
      {
       "kw": "Then",
       "text": "middleware <code>throttle:admin-login</code> appliqué sur POST <code>/admin/login</code>"
      },
      {
       "kw": "And",
       "text": "6ᵉ tentative dans 1 min → HTTP 429 + retry-after 60s"
      },
      {
       "kw": "And",
       "text": "fail2ban filter parse les 429 et ban IP 1h après 3 occurrences"
      },
      {
       "kw": "And",
       "text": "Pest test : 5 attempts → 401, 6ᵉ → 429"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "9.9",
     "epic": 9,
     "title": "Pest OWASP A02 (Crypto) + A04 (Insecure Design)",
     "role": "Murat",
     "want": "tests Pest A02 + A04 étendus + activés au merge Epic 9",
     "benefit": "4 catégories OWASP couvertes Phase 3/S2-S5",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>tests/Security/CryptographyTest.php</code> étendu"
      },
      {
       "kw": "When",
       "text": "il s'exécute en CI"
      },
      {
       "kw": "Then",
       "text": "assert sessions Laravel utilisent <code>AES-256-CBC</code> ou supérieur"
      },
      {
       "kw": "And",
       "text": "assert passwords admin sont bcrypt rounds ≥12"
      },
      {
       "kw": "And",
       "text": "assert <code>.env.production.encrypted</code> ne contient pas patterns clair"
      },
      {
       "kw": "Given",
       "text": "<code>tests/Security/InsecureDesignTest.php</code>"
      },
      {
       "kw": "Then",
       "text": "assert rate limiting actif sur <code>/admin/login</code> (Story 9.8) + <code>/admin/api/*</code> (60/min) + <code>/contact</code> (3/h)"
      },
      {
       "kw": "And",
       "text": "assert csrf tokens présents sur forms publics"
      },
      {
       "kw": "And",
       "text": "assert headers Apache : <code>X-Frame-Options: DENY</code>, <code>X-Content-Type-Options: nosniff</code>"
      },
      {
       "kw": "And",
       "text": "workflow CI fail si assertion échoue"
      }
     ],
     "notes": [],
     "status": "backlog"
    }
   ]
  },
  {
   "num": 10,
   "title": "Quality Audit Final",
   "phase": "Phase 3/S6 ~4j",
   "pitch": "Code maintenable long-terme — gates PHPStan/ECS/Pest passés progressivement (posés Epic 2 dès S1) + audits finaux non-automatisables : <b>audit Lava discipline (1j max borné)</b>, audit time-as-texture cohérence (retirer 30% si bruit), Percy visual regression baseline, Lighthouse ≥90 release gate, validation Pest OWASP A01-A04 globale, axe-core CLI green.",
   "meta": {
    "FRs covered": "aucune nouvelle FR (pure quality/polish)",
    "NFRs critical": "NFR-Quality-1 à 7, NFR-A11y-1 à 10, NFR-Perf-1 à 10 (validation finale), NFR-Browser-1 à 5 (cross-browser)",
    "ARs": "AR-Risk-1 à 8 (audit final risques flaggés)",
    "Critère go": "Lighthouse mobile &gt;90 homepage + 1 page review (PRD §10.3 LOCKED)"
   },
   "amendments": [
    "<b>Epic 11 initial renommé \"Quality Audit Final\"</b> (Winston : gates continus posés Epic 2 dès S1, audit final = uniquement audits manuels non-automatisables)",
    "<b>Audit Lava borné à 1j max</b> (Murat : output <code>docs/lava-audit.md</code> checklist binaire OUI/NON sur 10 critères — sans cette borne, drop)",
    "<b>Audit time-as-texture</b> : si retirer toutes mentions temporelles rend l'expérience plus calme = retirer 30% (cohérence Direction C)",
    "Percy snapshots 5 pages clés baseline (home LIVE, home OFFLINE, slug review, /press, /archive)"
   ],
   "effort": "4j",
   "status": "backlog",
   "retro": "optional",
   "stories": [
    {
     "id": "10.1",
     "epic": 10,
     "title": "PHPStan L7 → L8 final (zéro erreur)",
     "role": "Winston",
     "want": "<code>phpstan.neon</code> au niveau L8 final avec zéro erreur baseline",
     "benefit": "la progression L5→L6→L7→L8 culmine sans dette résiduelle",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>phpstan.neon</code> au démarrage Epic 10 à L7"
      },
      {
       "kw": "When",
       "text": "je monte <code>level: 8</code>"
      },
      {
       "kw": "Then",
       "text": "<code>vendor/bin/phpstan analyse</code> retourne 0 erreur"
      },
      {
       "kw": "And",
       "text": "<code>phpstan-baseline.neon</code> est <b>vide</b> (pas de dette acceptée)"
      },
      {
       "kw": "And",
       "text": "workflow CI bloquant sur L8"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "10.2",
     "epic": 10,
     "title": "ECS PSR-12 zéro warning final",
     "role": "Winston",
     "want": "<code>ecs check</code> retourne zéro warning sur <code>app/</code> + <code>tests/</code> + <code>config/</code>",
     "benefit": "PSR-12 stricte + lisibilité OSS maximale",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>vendor/bin/ecs check</code> sur main"
      },
      {
       "kw": "When",
       "text": "il termine"
      },
      {
       "kw": "Then",
       "text": "zéro warning, zéro suggested fix"
      },
      {
       "kw": "And",
       "text": "workflow CI fail sur tout warning (escalation Epic 2 informatif)"
      },
      {
       "kw": "And",
       "text": "<code>.editorconfig</code> cohérent avec <code>ecs.php</code>"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "10.3",
     "epic": 10,
     "title": "Pest 70% baseline coverage final",
     "role": "Murat",
     "want": "<code>pest --coverage</code> retourne ≥70% baseline sur tout <code>app/</code>",
     "benefit": "target coverage v1 LOCKED atteint (PRD §9.3)",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>vendor/bin/pest --coverage --min=70</code>"
      },
      {
       "kw": "When",
       "text": "il termine"
      },
      {
       "kw": "Then",
       "text": "coverage globale ≥70% sur <code>app/Core/</code> + <code>app/Modules/*</code>"
      },
      {
       "kw": "And",
       "text": "rapport HTML généré <code>storage/app/test-coverage/</code>"
      },
      {
       "kw": "And",
       "text": "workflow CI fail si &lt;70%"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "10.4",
     "epic": 10,
     "title": "Audit Lava grep (borné 1j max)",
     "role": "Caravaggio + Murat",
     "want": "audit \"où apparaît <code>bg-lava</code> / <code>text-lava</code> ?\" + checklist binaire dans <code>docs/lava-audit.md</code>",
     "benefit": "discipline 90/8/2 enforcée + Lava réservé strictement 4 catégories",
     "ac": [
      {
       "kw": "Given",
       "text": "script <code>scripts/audit/lava-discipline.sh</code>"
      },
      {
       "kw": "When",
       "text": "il s'exécute"
      },
      {
       "kw": "Then",
       "text": "<code>grep -r \"bg-lava\\|text-lava\\|--accent-lava\" resources/views/</code> retourne liste exhaustive"
      },
      {
       "kw": "And",
       "text": "chaque occurrence checklisté binaire dans <code>docs/lava-audit.md</code> :"
      },
      {
       "kw": "And",
       "text": "si OUI sur 1 des 4 → Lava autorisé"
      },
      {
       "kw": "And",
       "text": "si NON sur les 4 → flag refactor (déplacer vers secondary)"
      },
      {
       "kw": "And",
       "text": "<b>temps audit borné à 1j max</b> (Murat — output checklist, pas philosophie)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "10.5",
     "epic": 10,
     "title": "Audit time-as-texture intentionnel vs bruit",
     "role": "Caravaggio",
     "want": "audit mentions temporelles \"time-as-texture\" + règle \"si retirer rend plus calme, retirer 30%\"",
     "benefit": "Direction C signature reste intentionnelle, pas bruit",
     "ac": [
      {
       "kw": "Given",
       "text": "audit via grep <code>&lt;x-time-*</code>"
      },
      {
       "kw": "When",
       "text": "je liste tous les usages"
      },
      {
       "kw": "Then",
       "text": "chaque usage review manuellement :"
      },
      {
       "kw": "And",
       "text": "sortie : <code>docs/time-as-texture-audit.md</code> avec décisions"
      },
      {
       "kw": "And",
       "text": "<b>30% à retirer si retrait rend l'expérience plus calme</b>"
      },
      {
       "kw": "And",
       "text": "test : 5 pages clés (home, slug, /press, archive year, archive tag) → mentions intentionnelles uniquement"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "10.6",
     "epic": 10,
     "title": "Percy visual regression baseline (5 pages clés)",
     "role": "Murat",
     "want": "Percy CI baseline sur 5 pages clés (home LIVE, home OFFLINE, slug review, /press, /reviews/2026)",
     "benefit": "régressions visuelles non intentionnelles détectées",
     "ac": [
      {
       "kw": "Given",
       "text": "workflow <code>.github/workflows/percy.yml</code>"
      },
      {
       "kw": "When",
       "text": "il s'exécute sur PR"
      },
      {
       "kw": "Then",
       "text": "5 pages × 3 viewports (360px, 768px, 1280px) = 15 captures"
      },
      {
       "kw": "And",
       "text": "baseline créée première fois + comparée à chaque PR"
      },
      {
       "kw": "And",
       "text": "changes intentionnels → approve dans dashboard Percy"
      },
      {
       "kw": "And",
       "text": "workflow informatif (pas bloquant CI) — review humaine requise"
      },
      {
       "kw": "And",
       "text": "Percy free tier (5000 screenshots/mois) suffit v1"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "10.7",
     "epic": 10,
     "title": "Lighthouse mobile ≥90 release gate",
     "role": "Murat",
     "want": "Lighthouse-CI mobile sur home + 1 slug + /press scores ≥90 a11y / ≥85 perf / ≥95 SEO",
     "benefit": "critère go S6 LOCKED atteint",
     "ac": [
      {
       "kw": "Given",
       "text": "Lighthouse-CI workflow déjà actif Epic 2 (informatif)"
      },
      {
       "kw": "When",
       "text": "Epic 10 le passe en <b>bloquant CI</b>"
      },
      {
       "kw": "Then",
       "text": "assert scores sur les 3 URLs : Accessibility ≥95, Performance ≥85 mobile, SEO ≥95, Best Practices ≥90"
      },
      {
       "kw": "And",
       "text": "workflow fail si threshold pas atteint"
      },
      {
       "kw": "And",
       "text": "rapport HTML archivé artifact"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "10.8",
     "epic": 10,
     "title": "axe-core CLI final validation",
     "role": "Murat",
     "want": "<code>npx @axe-core/cli</code> retourne 0 violation AA sur 5 pages clés",
     "benefit": "WCAG 2.2 AA strictement enforced",
     "ac": [
      {
       "kw": "Given",
       "text": "workflow <code>a11y.yml</code> (Epic 2 informatif)"
      },
      {
       "kw": "When",
       "text": "Epic 10 le passe en <b>bloquant CI</b>"
      },
      {
       "kw": "Then",
       "text": "<code>npx @axe-core/cli</code> sur 5 URLs retourne 0 violation"
      },
      {
       "kw": "And",
       "text": "workflow fail si violation détectée"
      },
      {
       "kw": "And",
       "text": "rapport JSON archivé"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "10.9",
     "epic": 10,
     "title": "Pest OWASP A01-A04 final consolidation",
     "role": "Murat",
     "want": "tests Pest OWASP A01 (Epic 5) + A02 (Epic 4) + A03 (Epic 5) + A04 (Epic 9) tous green",
     "benefit": "bloquant prod #2 (Pest OWASP A01-A04) validé",
     "ac": [
      {
       "kw": "Given",
       "text": "suite <code>tests/Security/*Test.php</code> (4 fichiers)"
      },
      {
       "kw": "When",
       "text": "<code>vendor/bin/pest tests/Security/ --parallel</code>"
      },
      {
       "kw": "Then",
       "text": "tous les tests A01 (AuthTest), A02 (CryptographyTest), A03 (InjectionTest), A04 (InsecureDesignTest) green"
      },
      {
       "kw": "And",
       "text": "workflow CI bloquant"
      },
      {
       "kw": "And",
       "text": "rapport security archivé"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "10.10",
     "epic": 10,
     "title": "Cross-browser smoke tests Playwright",
     "role": "Murat",
     "want": "smoke tests Playwright sur 5 pages × Chrome + Firefox + WebKit (Safari mobile)",
     "benefit": "compatibilité navigateurs validée",
     "ac": [
      {
       "kw": "Given",
       "text": "workflow <code>playwright-cross-browser.yml</code>"
      },
      {
       "kw": "When",
       "text": "il s'exécute sur PR"
      },
      {
       "kw": "Then",
       "text": "5 pages × 3 navigateurs = 15 smoke tests parallèles"
      },
      {
       "kw": "And",
       "text": "chaque test : page charge sans erreur JS console + screenshot"
      },
      {
       "kw": "And",
       "text": "workflow informatif (flaky cross-browser)"
      },
      {
       "kw": "And",
       "text": "failures Playwright traces archivées artifact"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "10.11",
     "epic": 10,
     "title": "Performance budget enforcement S6",
     "role": "Murat",
     "want": "performance budget bloquant CI à partir d'Epic 10",
     "benefit": "budgets perf enforced avant release",
     "ac": [
      {
       "kw": "Given",
       "text": "Lighthouse-CI avec budgets configurés"
      },
      {
       "kw": "When",
       "text": "Epic 10 active enforcement"
      },
      {
       "kw": "Then",
       "text": "budgets bloquants :"
      },
      {
       "kw": "And",
       "text": "workflow fail si tout dépassement"
      },
      {
       "kw": "And",
       "text": "dashboard Lighthouse-CI expose trends 30 derniers commits"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "10.12",
     "epic": 10,
     "title": "Bug bash session + critical fixes",
     "role": "Alex + Murat",
     "want": "session bug bash dédiée fin S6 (2-3h) avec 2-3 testeurs amis sur staging",
     "benefit": "bugs ressentis catchés avant release publique S7",
     "ac": [
      {
       "kw": "Given",
       "text": "staging déployé fin S5 (<code>staging.skeleton-streamer.dev</code>)"
      },
      {
       "kw": "When",
       "text": "Alex organise bug bash"
      },
      {
       "kw": "Then",
       "text": "chaque tester explore 5 pages clés"
      },
      {
       "kw": "And",
       "text": "bugs reportés via GitHub Issues template <code>bug-bash</code>"
      },
      {
       "kw": "And",
       "text": "Alex triage critical vs nice-to-have (v1.1)"
      },
      {
       "kw": "And",
       "text": "<b>critical fixes mergés avant fin S6</b>"
      },
      {
       "kw": "And",
       "text": "rapport <code>docs/bug-bash/2026-XX-session-1.md</code>"
      }
     ],
     "notes": [],
     "status": "backlog"
    }
   ]
  },
  {
   "num": 11,
   "title": "OSS Publication",
   "phase": "Phase 4/S7 ~3.5j sans demo live",
   "pitch": "Fork-streamer trouve un README \"front store\" crédible (screenshots + GIF demo locale + value prop scannable en 30s), peut consulter 12+ ADRs publics, lance <code>make install-dev-full</code> sur VPS vierge avec confiance (Bats E2E nightly green sur <b>3 distros</b> : Ubuntu 24.04 + Debian 12 + Fedora 40). <b>Demo live droppée v1</b> (économie 2j+ réinvestis en buffer Epic 5/7).",
   "meta": {
    "FRs covered": "FR-OSS-1, FR-OSS-2, FR-OSS-4, FR-OSS-5, FR-OSS-6 (FR-OSS-3 Demo live DROPPED v1)",
    "NFRs critical": "NFR-Sec-5 (Bats nightly bloquant prod #4 — split avec Epic 2)",
    "Critère go": "<code>make install-dev-full</code> sur VPS vierge → <code>/health</code> 200 OK en &lt;15min sur les 3 distros (PRD §10.3 LOCKED + Murat critère 3-distros)"
   },
   "amendments": [
    "<b>Demo live DROPPED v1</b> (décision Alex 2026-05-23, reportée v1.1 si premiers users la réclament — Murat reco)",
    "<b>Bats E2E sur 3 distros</b> (Murat : Ubuntu 24.04 + Debian 12 + Fedora 40 — sinon OSS = mensonge)",
    "Effort réduit ~3.5j (vs 5j initial avec demo)",
    "README \"front store\" cohérent avec <code>make install-dev-full &lt;15min</code> comme wedge OSS (sans demo, l'installer fiable + Bats badge = preuve)"
   ],
   "effort": "3.5j",
   "status": "backlog",
   "retro": "optional",
   "stories": [
    {
     "id": "11.1",
     "epic": 11,
     "title": "README \"front store\" finalisé",
     "role": "Fork-Streamer",
     "want": "<code>README.md</code> \"front store\" — screenshots + GIF demo locale + value prop scannable en 30s + Quick Start",
     "benefit": "je décide en 30s si forker (sans demo live publique — droppée v1)",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>README.md</code> root du repo"
      },
      {
       "kw": "When",
       "text": "je le lis sur GitHub"
      },
      {
       "kw": "Then",
       "text": "structure :"
      },
      {
       "kw": "And",
       "text": "<b>aucune mention \"demo live\"</b> (droppée v1)"
      },
      {
       "kw": "And",
       "text": "lecture en &lt;30s scannable"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "11.2",
     "epic": 11,
     "title": "LICENSE MIT",
     "role": "Fork-Streamer",
     "want": "fichier <code>LICENSE</code> MIT standard à la racine",
     "benefit": "la licence est explicite + reconnue par GitHub",
     "ac": [
      {
       "kw": "Given",
       "text": "fichier <code>LICENSE</code> à la racine"
      },
      {
       "kw": "When",
       "text": "GitHub parse le repo"
      },
      {
       "kw": "Then",
       "text": "badge \"MIT\" affiché automatiquement"
      },
      {
       "kw": "And",
       "text": "texte standard MIT avec copyright <code>2026 Alex {nom_complet}</code>"
      },
      {
       "kw": "And",
       "text": "Alex peut customiser <code>{nom_complet}</code> (placeholder skeleton)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "11.3",
     "epic": 11,
     "title": "CODE_OF_CONDUCT.md",
     "role": "OSS communauté",
     "want": "<code>CODE_OF_CONDUCT.md</code> standard Contributor Covenant v2.1",
     "benefit": "le repo est inclusif et professionnel",
     "ac": [
      {
       "kw": "Given",
       "text": "fichier <code>CODE_OF_CONDUCT.md</code>"
      },
      {
       "kw": "When",
       "text": "je le lis"
      },
      {
       "kw": "Then",
       "text": "texte Contributor Covenant v2.1 standard"
      },
      {
       "kw": "And",
       "text": "email contact remplacé par <code>$settings-&gt;contact_email</code> ou placeholder"
      },
      {
       "kw": "And",
       "text": "GitHub affiche badge \"Code of Conduct\" automatiquement"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "11.4",
     "epic": 11,
     "title": "CONTRIBUTING.md",
     "role": "Fork-Streamer contributeur potentiel",
     "want": "<code>CONTRIBUTING.md</code> documenant setup local, code style, PR template, scope",
     "benefit": "PRs sont alignées sans friction",
     "ac": [
      {
       "kw": "Given",
       "text": "fichier <code>CONTRIBUTING.md</code>"
      },
      {
       "kw": "When",
       "text": "je le lis"
      },
      {
       "kw": "Then",
       "text": "sections :"
      },
      {
       "kw": "And",
       "text": "PR template <code>.github/PULL_REQUEST_TEMPLATE.md</code> créé"
      },
      {
       "kw": "And",
       "text": "issue templates <code>.github/ISSUE_TEMPLATE/{bug,feature,question}.md</code> créés"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "11.5",
     "epic": 11,
     "title": "SECURITY.md",
     "role": "Security researcher",
     "want": "<code>SECURITY.md</code> documenant security disclosure responsible",
     "benefit": "vulnérabilités reportées via canal privé responsible",
     "ac": [
      {
       "kw": "Given",
       "text": "fichier <code>SECURITY.md</code>"
      },
      {
       "kw": "When",
       "text": "je le lis"
      },
      {
       "kw": "Then",
       "text": "sections :"
      },
      {
       "kw": "And",
       "text": "<code>public/.well-known/security.txt</code> (Epic 3) référencé"
      },
      {
       "kw": "And",
       "text": "GitHub Security tab activé"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "11.6",
     "epic": 11,
     "title": "3 nouveaux ADRs (atteindre 12+ cible)",
     "role": "Fork-Streamer + Winston",
     "want": "3 ADRs supplémentaires pour atteindre 12+ ADRs (9 existants)",
     "benefit": "toutes les décisions structurantes party-mode documentées",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>docs/adr/</code> (9 ADRs existants)"
      },
      {
       "kw": "When",
       "text": "Epic 11 termine"
      },
      {
       "kw": "Then",
       "text": "3 nouveaux ADRs écrits :"
      },
      {
       "kw": "And",
       "text": "chaque ADR au format standard (Contexte / Décision / Conséquences / Référence débat)"
      },
      {
       "kw": "And",
       "text": "<code>docs/adr/README.md</code> index mis à jour"
      },
      {
       "kw": "And",
       "text": "lien depuis <code>docs/architecture/11-glossaire-adrs.md</code>"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "11.7",
     "epic": 11,
     "title": "Bats E2E install &lt;15min sur 3 distros",
     "role": "Murat",
     "want": "workflow <code>nightly-multi-distro.yml</code> lançant <code>bats tests/install.bats</code> sur Ubuntu 24.04 + Debian 12 + Fedora 40",
     "benefit": "4ᵉ bloquant prod validé end-to-end multi-distro",
     "ac": [
      {
       "kw": "Given",
       "text": "workflow <code>.github/workflows/nightly-multi-distro.yml</code>"
      },
      {
       "kw": "When",
       "text": "il s'exécute chaque nuit"
      },
      {
       "kw": "Then",
       "text": "3 jobs parallèles en containers Docker éphémères :"
      },
      {
       "kw": "And",
       "text": "chaque job clone le repo + exécute <code>make install-dev-full</code> + curl <code>/health</code>"
      },
      {
       "kw": "And",
       "text": "assert <code>/health</code> 200 OK + JSON <code>{database, cache, queue} = \"ok\"</code>"
      },
      {
       "kw": "And",
       "text": "temps total &lt;15min par distro"
      },
      {
       "kw": "And",
       "text": "workflow fail si 1 distro échoue"
      },
      {
       "kw": "And",
       "text": "<b>sans cette validation 3-distro, Epic 11 n'est pas done</b> (Murat critère succès)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "11.8",
     "epic": 11,
     "title": "<code>docs/design-system.md</code> doc finale",
     "role": "Fork-Streamer + Sally",
     "want": "<code>docs/design-system.md</code> doc finale référençant tokens + composants + patterns + anti-patterns",
     "benefit": "source de vérité visuelle en 1 page",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>docs/design-system.md</code>"
      },
      {
       "kw": "When",
       "text": "je le lis"
      },
      {
       "kw": "Then",
       "text": "sections :"
      },
      {
       "kw": "And",
       "text": "doc référencée depuis README + CONTRIBUTING"
      },
      {
       "kw": "And",
       "text": "synchronisée avec <code>ux-design-specification.md</code>"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "11.9",
     "epic": 11,
     "title": "README badges (CI, Bats, license, etc.)",
     "role": "Fork-Streamer",
     "want": "badges README en haut (CI, Bats nightly, MIT, PHP, Laravel, Postgres, Coverage)",
     "benefit": "je vois en 3s que le projet est maintenu et fonctionnel",
     "ac": [
      {
       "kw": "Given",
       "text": "README header"
      },
      {
       "kw": "When",
       "text": "je le lis sur GitHub"
      },
      {
       "kw": "Then",
       "text": "badges affichés (shields.io) :"
      },
      {
       "kw": "And",
       "text": "badges cliquables (mènent aux workflows / coverage / license)"
      }
     ],
     "notes": [],
     "status": "backlog"
    },
    {
     "id": "11.10",
     "epic": 11,
     "title": "Quick-start tutorial <code>docs/process/quick-start.md</code>",
     "role": "Fork-Streamer débutant",
     "want": "<code>docs/process/quick-start.md</code> tutorial en 5 étapes",
     "benefit": "je passe de \"découverte repo\" à \"site live\" en &lt;30min",
     "ac": [
      {
       "kw": "Given",
       "text": "<code>docs/process/quick-start.md</code>"
      },
      {
       "kw": "When",
       "text": "je le lis"
      },
      {
       "kw": "Then",
       "text": "5 étapes claires avec code snippets :"
      },
      {
       "kw": "And",
       "text": "chaque étape a screenshot ou GIF court"
      },
      {
       "kw": "And",
       "text": "estimé total &lt;30min"
      },
      {
       "kw": "And",
       "text": "tutorial testé par 1 ami fork-streamer fin S7"
      }
     ],
     "notes": [],
     "status": "backlog"
    }
   ]
  }
 ],
 "requirements": [
  {
   "code": "FR-Public-1",
   "family": "FR",
   "group": "Module Public",
   "text": "Homepage différencie LIVE vs OFFLINE avec premier glance &lt;300ms (badge Lava si LIVE, dernière review hero + 3 récentes + replay YouTube si OFFLINE)."
  },
  {
   "code": "FR-Public-2",
   "family": "FR",
   "group": "Module Public",
   "text": "Page About avec bio FR + EN, parcours streaming, valeurs éditoriales archétype Ponce."
  },
  {
   "code": "FR-Public-3",
   "family": "FR",
   "group": "Module Public",
   "text": "Header sticky discret 48px mobile / 56px desktop (logo + 3 items max + état LIVE intégré), pas de burger menu (3 items toujours visibles)."
  },
  {
   "code": "FR-Public-4",
   "family": "FR",
   "group": "Module Public",
   "text": "Footer site standard (mentions légales, presse, RSS visible texte, GitHub, copyright)."
  },
  {
   "code": "FR-Public-5",
   "family": "FR",
   "group": "Module Public",
   "text": "Sitemap.xml + RSS générés automatiquement, <code>&lt;lastmod&gt;</code> reflète <code>last_updated_at</code>, mis à jour au publish review."
  },
  {
   "code": "FR-Public-6",
   "family": "FR",
   "group": "Module Public",
   "text": "Schema.org structuré : <code>Person</code> (homepage), <code>Review</code> + <code>VideoGame</code> (review page), <code>Article</code> + <code>Person</code> (about), <code>datePublished</code> + <code>dateModified</code> sur reviews."
  },
  {
   "code": "FR-Public-7",
   "family": "FR",
   "group": "Module Public",
   "text": "Pages d'archive navigable first-class <code>/{year}</code>, <code>/{tag}</code>, <code>/{game}</code> avec pagination cursor (scale jusqu'à 100+ articles M+24)."
  },
  {
   "code": "FR-Live-1",
   "family": "FR",
   "group": "Module Live",
   "text": "Badge LIVE via Twitch Helix poll 60s côté serveur (cache Redis), affichage instantané côté client, \"LIVE since 2h17m\" texture temporelle."
  },
  {
   "code": "FR-Live-2",
   "family": "FR",
   "group": "Module Live",
   "text": "Embed Twitch player + chat iframe officielles, cookie consent pré-chargement obligatoire, chat masqué &lt;768px mobile."
  },
  {
   "code": "FR-Live-3",
   "family": "FR",
   "group": "Module Live",
   "text": "Scène OFFLINE designée comme état nominal : composant Blade \"Hors ligne, dernier stream il y a X\" + dernière review hero + lien dernier replay YouTube."
  },
  {
   "code": "FR-Live-4",
   "family": "FR",
   "group": "Module Live",
   "text": "Status sidebar avec viewers concurrents si LIVE (\"247 viewers right now\"), dernière VOD si OFFLINE."
  },
  {
   "code": "FR-Live-5",
   "family": "FR",
   "group": "Module Live",
   "text": "Circuit breaker fallback OFFLINE silencieux après 3 retries Helix (pas d'alerte UI \"API down\")."
  },
  {
   "code": "FR-Reviews-1",
   "family": "FR",
   "group": "Module Reviews",
   "text": "Modèle <code>Article</code> unique avec enum <code>type</code> (review|news|preview) — <code>note</code>/<code>vod_youtube_url</code>/<code>game_id</code> nullable pour news/preview (OQ9 LOCKED)."
  },
  {
   "code": "FR-Reviews-2",
   "family": "FR",
   "group": "Module Reviews",
   "text": "CRUD Filament admin avec champs : titre, slug ASCII pur (Str::slug Laravel natif — OQ3 LOCKED), cover 16:9 webp, body Markdown, note 0-10 nullable, jeu lié nullable, vod_youtube_url nullable, type enum, published_at, last_updated_at, revision_note Markdown court optionnel."
  },
  {
   "code": "FR-Reviews-3",
   "family": "FR",
   "group": "Module Reviews",
   "text": "YoutubeValidator avant publish — ping Helix vérifie que la VOD existe (jamais lien mort en prod), toast warning si Helix down avec override possible."
  },
  {
   "code": "FR-Reviews-4",
   "family": "FR",
   "group": "Module Reviews",
   "text": "Page review publique avec verdict above-the-fold mobile &lt;5s : H1 + note visible (display 60-96px) + verdict 1-3 phrases en intro + corps article 720px max-width 18px line-height 1.7."
  },
  {
   "code": "FR-Reviews-5",
   "family": "FR",
   "group": "Module Reviews",
   "text": "YT embed <i>petit</i> max 480×270 aligné colonne lecture, jamais full-bleed."
  },
  {
   "code": "FR-Reviews-6",
   "family": "FR",
   "group": "Module Reviews",
   "text": "Timecodes inline cliquables <code>[00:42]</code> ouvrent YouTube <code>?t=42</code> nouvel onglet."
  },
  {
   "code": "FR-Reviews-7",
   "family": "FR",
   "group": "Module Reviews",
   "text": "Compteur vues page detail uniquement, seuil minimum 100 vues (anti-vanity Ponce, pas en index)."
  },
  {
   "code": "FR-Reviews-8",
   "family": "FR",
   "group": "Module Reviews",
   "text": "Update-in-place workflow — <code>last_updated_at</code> auto-bump à chaque save post-publish, badge \"Mis à jour le X\" visible front si Y &gt; X+30j, Schema.org <code>dateModified</code>."
  },
  {
   "code": "FR-Reviews-9",
   "family": "FR",
   "group": "Module Reviews",
   "text": "Comments <b>OFF J1</b> (OQ1+OQ2 RÉVISÉS party-mode) — migrations Filament + Akismet pré-câblé en code dormant via feature flag <code>comments.enabled=false</code>, activation conditionnelle M+1 sur 3 signaux mesurables."
  },
  {
   "code": "FR-Reviews-10",
   "family": "FR",
   "group": "Module Reviews",
   "text": "Job nightly check disponibilité VOD YouTube (si supprimée → flag <code>vod_unavailable=true</code> + affichage gracieux)."
  },
  {
   "code": "FR-Reviews-11",
   "family": "FR",
   "group": "Module Reviews",
   "text": "Composant \"articles liés\" en fin d'article AVANT CTA Twitter/Discord (algo : tags partagés ≥2, pattern \"Capture before bounce\")."
  },
  {
   "code": "FR-Reviews-12",
   "family": "FR",
   "group": "Module Reviews",
   "text": "CTAs Twitter/Discord fin d'article tenant-aware (<code>&lt;x-cta.post-read :twitter=\"$settings-&gt;twitter\" :discord=\"$settings-&gt;discord\"&gt;</code>), 1 clic nouvel onglet, copy archétype Ponce <i>\"On en discute ailleurs\"</i>, <b>pas de Lava</b>."
  },
  {
   "code": "FR-Reviews-13",
   "family": "FR",
   "group": "Module Reviews",
   "text": "UTM bidirectionnel sur CTAs : <code>?utm_source=site&amp;utm_medium=post-read-cta&amp;utm_campaign={article-slug}&amp;utm_content={platform}</code>."
  },
  {
   "code": "FR-Press-1",
   "family": "FR",
   "group": "Module PressKit",
   "text": "Page <code>/press</code> avec hiérarchie verticale stricte Stats &gt; Photo &gt; Bio (casse l'instinct \"photo first\")."
  },
  {
   "code": "FR-Press-2",
   "family": "FR",
   "group": "Module PressKit",
   "text": "Stats P50 médianes — viewers concurrents médiane (jamais mean, jamais followers Twitch vanity), heures stream total, nombre VODs YouTube, \"Streaming depuis 4 ans\" texture temporelle."
  },
  {
   "code": "FR-Press-3",
   "family": "FR",
   "group": "Module PressKit",
   "text": "Bio FR + EN bilingue v1 (Claude/ChatGPT + relecture Alex — OQ4 LOCKED), workflow doc à créer Phase 3."
  },
  {
   "code": "FR-Press-4",
   "family": "FR",
   "group": "Module PressKit",
   "text": "Téléchargements SVG / PNG / Kit complet — chacun individuel 1 clic = 1 fichier, pas de zip global."
  },
  {
   "code": "FR-Press-5",
   "family": "FR",
   "group": "Module PressKit",
   "text": "Formulaire contact (nom, mail, sujet, message) → email Alex via Resend driver natif (OQ8 LOCKED, free tier 100/jour) + log Spatie ActivityLog."
  },
  {
   "code": "FR-Press-6",
   "family": "FR",
   "group": "Module PressKit",
   "text": "Trust signaling — méthodologie stats visible (lien \"Comment je calcule\" à 1 clic max, page dédiée), historique transparent (X articles publiés sur Y mois), press kit \"as a template\" qui crédibilise par qualité repo OSS."
  },
  {
   "code": "FR-Press-7",
   "family": "FR",
   "group": "Module PressKit",
   "text": "Bouton \"Copier le lien press kit\" UTM-tracké pour JTBD n°3 dev gifting (~1h dev S5, Mary risque P5)."
  },
  {
   "code": "FR-Press-8",
   "family": "FR",
   "group": "Module PressKit",
   "text": "Composant <code>&lt;x-press.kit&gt;</code> paramétrable tenant-aware dès J1 (Victor R6 anti-fragile)."
  },
  {
   "code": "FR-Press-9",
   "family": "FR",
   "group": "Module PressKit",
   "text": "URLs sociales (Twitter, Discord, autres) lues depuis table <code>settings</code> éditable Filament — jamais hardcodées (Victor R6 mitigation risque Twitter implosion 2027)."
  },
  {
   "code": "FR-Admin-1",
   "family": "FR",
   "group": "Module Admin",
   "text": "Filament v3 panels + Laravel Sanctum + Spatie Permission v7, route <code>/admin</code>."
  },
  {
   "code": "FR-Admin-2",
   "family": "FR",
   "group": "Module Admin",
   "text": "Role <code>super-admin</code> (Alex seul utilisateur v1)."
  },
  {
   "code": "FR-Admin-3",
   "family": "FR",
   "group": "Module Admin",
   "text": "Resources Filament : <code>ArticleResource</code> (review/news/preview unifié), <code>GameResource</code> (catalogue référencé), <code>SettingsResource</code> (URLs sociales + bio FR+EN + photo presse), <code>PressContactResource</code> (lecture seule audit)."
  },
  {
   "code": "FR-Admin-4",
   "family": "FR",
   "group": "Module Admin",
   "text": "<code>CommentResource</code> — code dormant J1 (cf. FR-Reviews-9), activable M+1."
  },
  {
   "code": "FR-Admin-5",
   "family": "FR",
   "group": "Module Admin",
   "text": "Composant brouillon réseaux sociaux Filament (S5) — génère texte copy-pastable Twitter/Mastodon/Bluesky à partir d'une review, pas d'API auto-publish v1."
  },
  {
   "code": "FR-Admin-6",
   "family": "FR",
   "group": "Module Admin",
   "text": "Autosave 60s natif Filament Forms (<code>-&gt;autosave()</code>) + toast silencieux \"Saved 23:14:32\"."
  },
  {
   "code": "FR-Admin-7",
   "family": "FR",
   "group": "Module Admin",
   "text": "Preview inline non-modale dans Filament Forms (pas de modale \"Voulez-vous publier ?\")."
  },
  {
   "code": "FR-Admin-8",
   "family": "FR",
   "group": "Module Admin",
   "text": "Login Sanctum via panneau Filament avec rate limiting 5/min/IP."
  },
  {
   "code": "FR-Scaff-1",
   "family": "FR",
   "group": "Scaffolding modulaire",
   "text": "Arborescence cible <code>src/app/Core/</code> + <code>src/app/Modules/{Public, Live, Reviews, PressKit, Admin}/</code> (ADR-0009)."
  },
  {
   "code": "FR-Scaff-2",
   "family": "FR",
   "group": "Scaffolding modulaire",
   "text": "<code>Streamer</code> model + migration + seeder (un seul row v1, multi-streamer prêt v2+)."
  },
  {
   "code": "FR-Scaff-3",
   "family": "FR",
   "group": "Scaffolding modulaire",
   "text": "<code>BelongsToStreamerScope</code> global scope + trait <code>BelongsToStreamer</code> + middleware <code>SetCurrentStreamer</code> qui bind dans container."
  },
  {
   "code": "FR-Scaff-4",
   "family": "FR",
   "group": "Scaffolding modulaire",
   "text": "<code>App\\Core\\Support\\CurrentStreamer</code> singleton accessible via <code>app(CurrentStreamer::class)</code>, <b>fail-loud</b> si non bindé."
  },
  {
   "code": "FR-Scaff-5",
   "family": "FR",
   "group": "Scaffolding modulaire",
   "text": "<code>src/config/modules.php</code> + bootstrap conditionnel dans <code>AppServiceProvider::register()</code> (chargement service providers par module selon ENV)."
  },
  {
   "code": "FR-Scaff-6",
   "family": "FR",
   "group": "Scaffolding modulaire",
   "text": "Laravel Pennant publish + table <code>features</code> (1h coût, toggles dev solo J1 — ADR + roundtable)."
  },
  {
   "code": "FR-Scaff-7",
   "family": "FR",
   "group": "Scaffolding modulaire",
   "text": "Commande artisan <code>tenancy:assert</code> qui vérifie <code>Streamer::count() === 1</code>, CI bloquant."
  },
  {
   "code": "FR-Scaff-8",
   "family": "FR",
   "group": "Scaffolding modulaire",
   "text": "Modules activables via ENV <code>MODULE_&lt;NAME&gt;_ENABLED=true|false</code> (anti-WordPress runtime — ADR-0001)."
  },
  {
   "code": "FR-Scaff-9",
   "family": "FR",
   "group": "Scaffolding modulaire",
   "text": "Test Pest qui scanne <code>app/Modules/*/Models/</code> et vérifie inclusion trait <code>BelongsToStreamer</code>, CI bloquant."
  },
  {
   "code": "FR-Scaff-10",
   "family": "FR",
   "group": "Scaffolding modulaire",
   "text": "Migrations module-scoped — chaque module a son dossier <code>Database/migrations/</code> enregistré via <code>loadMigrationsFrom()</code> dans son provider (pas de mix dans <code>database/migrations/</code> racine)."
  },
  {
   "code": "FR-Install-1",
   "family": "FR",
   "group": "Installer / DX",
   "text": "<code>make install-dev-full</code> idempotent avec sentinel <code>.install-state/&lt;step&gt;-done</code> + lockfile <code>.install-state/lock.yml</code> (sha256 composer.lock + php -v + node -v + timestamp)."
  },
  {
   "code": "FR-Install-2",
   "family": "FR",
   "group": "Installer / DX",
   "text": "Flags <code>--dry-run</code> + <code>--resume-from=&lt;step&gt;</code> sur tous les scripts d'install."
  },
  {
   "code": "FR-Install-3",
   "family": "FR",
   "group": "Installer / DX",
   "text": "Refactor <code>scripts/lib/common.sh</code> (DRY shared lib avec <code>die()</code>, <code>retry()</code>, <code>require_cmd()</code>, <code>ensure_idempotent()</code>, <code>trap ERR</code>)."
  },
  {
   "code": "FR-Install-4",
   "family": "FR",
   "group": "Installer / DX",
   "text": "Bats E2E <code>tests/bats/install.bats</code> lancée en CI nightly bloquant (bloquant prod #4 Murat)."
  },
  {
   "code": "FR-Install-5",
   "family": "FR",
   "group": "Installer / DX",
   "text": "Re-découpage profiles Docker <code>prod/dev/dev-tools/ops</code> (Watchtower séparé de dev-tools — Winston R1)."
  },
  {
   "code": "FR-Install-6",
   "family": "FR",
   "group": "Installer / DX",
   "text": "Templates qualité versionnés (<code>docker/php/php.ini.template</code>, <code>apache/vhost.conf.template</code>) — substitution ENV au démarrage."
  },
  {
   "code": "FR-Install-7",
   "family": "FR",
   "group": "Installer / DX",
   "text": "README \"front store\" Phase 4 (screenshots + GIF demo + value prop en 30s scannable)."
  },
  {
   "code": "FR-Obs-1",
   "family": "FR",
   "group": "Observabilité",
   "text": "Sentry SDK install + DSN env (free tier 5k events/mois) + breadcrumbs Laravel auto."
  },
  {
   "code": "FR-Obs-2",
   "family": "FR",
   "group": "Observabilité",
   "text": "Pulse install + DB séparée <code>postgres-pulse</code> container Docker isolé (ADR-0004), exclu des backups."
  },
  {
   "code": "FR-Obs-3",
   "family": "FR",
   "group": "Observabilité",
   "text": "Spatie Health checks register (DB, Cache, Queue, Disk, OpcacheMemory, HttpsCertificateExpiry) sur <code>/health</code>."
  },
  {
   "code": "FR-Obs-4",
   "family": "FR",
   "group": "Observabilité",
   "text": "Uptime-Kuma container externe + monitor <code>/health</code> + alerts Discord (cut v1 si glissement, gain 1j)."
  },
  {
   "code": "FR-Obs-5",
   "family": "FR",
   "group": "Observabilité",
   "text": "Spatie Schedule Monitor v4 pour cron jobs (backup, OG retry, YT availability check)."
  },
  {
   "code": "FR-Obs-6",
   "family": "FR",
   "group": "Observabilité",
   "text": "Pulse rotation interne 7 jours max (<code>pulse:trim --hours=168</code> scheduler quotidien)."
  },
  {
   "code": "FR-CI-1",
   "family": "FR",
   "group": "CI / Quality",
   "text": "GitHub Actions wrappers (<code>scripts/ci/test.sh</code>, <code>lint.sh</code>, <code>deploy.sh</code>, <code>quality.sh</code>) provider-agnostic."
  },
  {
   "code": "FR-CI-2",
   "family": "FR",
   "group": "CI / Quality",
   "text": "Matrice CI PHP 8.4 + 8.5.1 × Postgres 17."
  },
  {
   "code": "FR-CI-3",
   "family": "FR",
   "group": "CI / Quality",
   "text": "Pre-commit hook (Gitleaks → ECS --fix → PHPStan L8 → Pest --parallel)."
  },
  {
   "code": "FR-CI-4",
   "family": "FR",
   "group": "CI / Quality",
   "text": "Gates CI (lint-ecs bloquant, static-phpstan-l8 bloquant, tests-pest bloquant, pest-drift informatif, rector dry-run informatif, snyk-scan alert HIGH)."
  },
  {
   "code": "FR-CI-5",
   "family": "FR",
   "group": "CI / Quality",
   "text": "Gitleaks pre-commit + CI (bloquant prod #1 Murat)."
  },
  {
   "code": "FR-CI-6",
   "family": "FR",
   "group": "CI / Quality",
   "text": "Pest security suite OWASP A01-A04 dans <code>tests/Security/{Auth,AccessControl,Injection,Cryptography}Test.php</code> (bloquant prod #2 Murat)."
  },
  {
   "code": "FR-CI-7",
   "family": "FR",
   "group": "CI / Quality",
   "text": "axe-core CLI sur home + 1 slug review + /press + Lighthouse mobile (a11y ≥95, perf ≥85, SEO ≥95) bloquant CI."
  },
  {
   "code": "FR-CI-8",
   "family": "FR",
   "group": "CI / Quality",
   "text": "Pest pyramide test 70% unit / 20% feature / 5% Pact / 5% E2E Playwright (cible S6 70% baseline)."
  },
  {
   "code": "FR-Sec-1",
   "family": "FR",
   "group": "Sécurité",
   "text": "Cookie consent pré-embed Twitch/YouTube avec Spatie cookie-consent, bandeau bas-droite max 64px hauteur, placeholder cliquable si refus (bloquant prod #3 Murat)."
  },
  {
   "code": "FR-Sec-2",
   "family": "FR",
   "group": "Sécurité",
   "text": "Headers HTTP middleware global (HSTS preload, CSP via spatie/laravel-csp, X-Frame-Options DENY, X-Content-Type-Options nosniff, Referrer-Policy strict-origin-when-cross-origin)."
  },
  {
   "code": "FR-Sec-3",
   "family": "FR",
   "group": "Sécurité",
   "text": "Rate limiting Laravel (api 60/min/IP, login 5/min/IP, register 3/min/IP, comment.store 10/h/user si activé M+1, contact-form 3/h/IP)."
  },
  {
   "code": "FR-Sec-4",
   "family": "FR",
   "group": "Sécurité",
   "text": "Infra serveur hardening (SSH key-only, UFW 22/80/443, fail2ban sur SSHD + Apache login attempts, Dependabot + Renovate)."
  },
  {
   "code": "FR-Sec-5",
   "family": "FR",
   "group": "Sécurité",
   "text": "<code>php artisan env:encrypt</code> natif Laravel pour secrets (ADR-0006), clé <code>LARAVEL_ENV_ENCRYPTION_KEY</code> en env var serveur."
  },
  {
   "code": "FR-Sec-6",
   "family": "FR",
   "group": "Sécurité",
   "text": "Jobs sensibles implementent <code>ShouldBeEncrypted</code> (payload chiffré queue Redis)."
  },
  {
   "code": "FR-Sec-7",
   "family": "FR",
   "group": "Sécurité",
   "text": "<code>public/.well-known/security.txt</code> généré à l'install, personnalisable."
  },
  {
   "code": "FR-Backup-1",
   "family": "FR",
   "group": "Backup",
   "text": "<code>scripts/ops/backup-local.sh</code> quotidien (cron 03:00, pg_dump, rotation 14j, gzip -9) — ACTIVÉ par défaut."
  },
  {
   "code": "FR-Backup-2",
   "family": "FR",
   "group": "Backup",
   "text": "<code>scripts/ops/backup-offsite.sh</code> DÉSACTIVÉ par défaut (<code>BACKUP_OFFSITE_ENABLED=false</code>), activable 5min via rclone + Mega 20GB / Drive 15GB / pCloud 10GB free tier."
  },
  {
   "code": "FR-Backup-3",
   "family": "FR",
   "group": "Backup",
   "text": "Exclusion <code>postgres-pulse</code> des backups quotidiens (regénérable, ADR-0004)."
  },
  {
   "code": "FR-Backup-4",
   "family": "FR",
   "group": "Backup",
   "text": "Test Bats <code>tests/bats/backup-local.bats</code> lance dump + vérifie integrity <code>pg_restore --list</code>."
  },
  {
   "code": "FR-OG-1",
   "family": "FR",
   "group": "OG Images dynamiques pré-générées",
   "text": "4 templates Blade : <code>og/review-stellar.blade.php</code> (note ≥9), <code>og/review-solid.blade.php</code> (7-8), <code>og/review-light.blade.php</code> (≤6), <code>og/news.blade.php</code> (sans note) — OQ5 LOCKED 3 variantes + news."
  },
  {
   "code": "FR-OG-2",
   "family": "FR",
   "group": "OG Images dynamiques pré-générées",
   "text": "Job async <code>GenerateOgImage::dispatch($article)</code> à publish via Browsershot (timeout 30s, max_tries 3, queue dédiée)."
  },
  {
   "code": "FR-OG-3",
   "family": "FR",
   "group": "OG Images dynamiques pré-générées",
   "text": "Fallback OG statique automatique si échec génération (Pulse alert sur failed jobs)."
  },
  {
   "code": "FR-OG-4",
   "family": "FR",
   "group": "OG Images dynamiques pré-générées",
   "text": "Format unique 1200×630, background <code>#0A0A0B</code> flat, cover game left 40%, logo discret bottom-right, IBM Plex Sans + Mono."
  },
  {
   "code": "FR-OG-5",
   "family": "FR",
   "group": "OG Images dynamiques pré-générées",
   "text": "Stockage <code>public/og/{slug}.png</code>, généré au moment du <code>publish</code>, jamais à la volée."
  },
  {
   "code": "FR-OG-6",
   "family": "FR",
   "group": "OG Images dynamiques pré-générées",
   "text": "Tests Pest snapshot visuel via PixelMatch (3 PNG de référence en <code>tests/fixtures/og/</code>) — détecte régressions visuelles non intentionnelles."
  },
  {
   "code": "FR-OSS-1",
   "family": "FR",
   "group": "Polish OSS",
   "text": "README \"front store\" final (screenshots + GIF demo + value prop en 30s scannable)."
  },
  {
   "code": "FR-OSS-2",
   "family": "FR",
   "group": "Polish OSS",
   "text": "12+ ADRs publics documentés dans <code>docs/adr/</code> (9 existants + 3+ à créer)."
  },
  {
   "code": "FR-OSS-3",
   "family": "FR",
   "group": "Polish OSS",
   "text": "Demo live sous-domaine sandbox <code>demo.skeleton-streamer.dev</code> (coupable si glissement, gain 1.5j)."
  },
  {
   "code": "FR-OSS-4",
   "family": "FR",
   "group": "Polish OSS",
   "text": "Fichiers OSS standards : <code>LICENSE</code> (MIT), <code>CODE_OF_CONDUCT.md</code>, <code>CONTRIBUTING.md</code>, <code>SECURITY.md</code>."
  },
  {
   "code": "FR-OSS-5",
   "family": "FR",
   "group": "Polish OSS",
   "text": "Bats E2E duplicabilité skeleton (<code>make install-dev-full</code> &lt;15min VPS vierge → <code>/health</code> 200 OK)."
  },
  {
   "code": "FR-OSS-6",
   "family": "FR",
   "group": "Polish OSS",
   "text": "Documentation handoff <code>docs/design-system.md</code> (tokens + composants + patterns + anti-patterns)."
  },
  {
   "code": "NFR-Perf-1",
   "family": "NFR",
   "group": "Performance",
   "text": "Time-to-first-content (TTFC) layout — titre + note visibles above-the-fold mobile en &lt;1.5s sur 4G (mesuré Lighthouse / WebPageTest)."
  },
  {
   "code": "NFR-Perf-2",
   "family": "NFR",
   "group": "Performance",
   "text": "Largest Contentful Paint (LCP) &lt;2.5s sur Lighthouse mobile."
  },
  {
   "code": "NFR-Perf-3",
   "family": "NFR",
   "group": "Performance",
   "text": "Cumulative Layout Shift (CLS) &lt;0.05 (cible 0) — cover image dimensions reservées + fonts preload IBM Plex."
  },
  {
   "code": "NFR-Perf-4",
   "family": "NFR",
   "group": "Performance",
   "text": "Total Blocking Time (TBT) &lt;200ms sur Lighthouse mobile."
  },
  {
   "code": "NFR-Perf-5",
   "family": "NFR",
   "group": "Performance",
   "text": "JS bundle public (Livewire + Alpine + custom) &lt;80KB minifié+gzipped."
  },
  {
   "code": "NFR-Perf-6",
   "family": "NFR",
   "group": "Performance",
   "text": "CSS bundle public &lt;40KB minifié+gzipped."
  },
  {
   "code": "NFR-Perf-7",
   "family": "NFR",
   "group": "Performance",
   "text": "Images cover review &lt;100KB webp (validation Filament backend)."
  },
  {
   "code": "NFR-Perf-8",
   "family": "NFR",
   "group": "Performance",
   "text": "Lighthouse mobile scores : perf ≥85, a11y ≥95, SEO ≥95, best practices ≥90 (bloquant CI à partir de S6)."
  },
  {
   "code": "NFR-Perf-9",
   "family": "NFR",
   "group": "Performance",
   "text": "Comments queue p95 &lt;200ms (si activé M+1)."
  },
  {
   "code": "NFR-Perf-10",
   "family": "NFR",
   "group": "Performance",
   "text": "Helix proxy p95 &lt;500ms (cache Redis 60s + circuit breaker)."
  },
  {
   "code": "NFR-Sec-1",
   "family": "NFR",
   "group": "Sécurité",
   "text": "Gitleaks pre-commit + CI bloquant (bloquant prod #1) — repo OSS public = secret leak irréversible."
  },
  {
   "code": "NFR-Sec-2",
   "family": "NFR",
   "group": "Sécurité",
   "text": "Pest security suite OWASP A01-A04 (Auth, Access Control, Injection, Cryptography) — bloquant prod #2."
  },
  {
   "code": "NFR-Sec-3",
   "family": "NFR",
   "group": "Sécurité",
   "text": "Cookie consent pré-embed Twitch+YouTube fonctionnel — bloquant prod #3."
  },
  {
   "code": "NFR-Sec-4",
   "family": "NFR",
   "group": "Sécurité",
   "text": "Bats smoke installer nightly bloquant — bloquant prod #4 (E2E duplicabilité skeleton)."
  },
  {
   "code": "NFR-Sec-5",
   "family": "NFR",
   "group": "Sécurité",
   "text": "Aucune fuite de secrets en repo (Gitleaks pre-commit + CI workflow step)."
  },
  {
   "code": "NFR-Sec-6",
   "family": "NFR",
   "group": "Sécurité",
   "text": "Multi-tenant prêt — <code>streamer_id</code> sur toutes tables métier J1, mais RLS Postgres NOT ENABLED v1 (ADR-0002, additif v2+ ~3-4j non breaking)."
  },
  {
   "code": "NFR-Sec-7",
   "family": "NFR",
   "group": "Sécurité",
   "text": "Snyk scan PHP + Node hebdomadaire (alert si nouvelle HIGH/CRITICAL, pas bloquant)."
  },
  {
   "code": "NFR-Sec-8",
   "family": "NFR",
   "group": "Sécurité",
   "text": "Mozilla Observatory CLI staging gate A minimum."
  },
  {
   "code": "NFR-Quality-1",
   "family": "NFR",
   "group": "Qualité code",
   "text": "PHPStan level 8 (Larastan v3) — zéro erreur sur tous <code>app/Modules/*</code> à S6."
  },
  {
   "code": "NFR-Quality-2",
   "family": "NFR",
   "group": "Qualité code",
   "text": "ECS (Easy Coding Standard v13) PSR-12 — zéro warning à S6."
  },
  {
   "code": "NFR-Quality-3",
   "family": "NFR",
   "group": "Qualité code",
   "text": "Pest 4 coverage 70% baseline à S6 (mesurable via <code>pest --coverage</code>)."
  },
  {
   "code": "NFR-Quality-4",
   "family": "NFR",
   "group": "Qualité code",
   "text": "Rector v2.3 dry-run informatif (refactoring suggestions PHP 8.5 + Laravel 12, pas bloquant v1)."
  },
  {
   "code": "NFR-Quality-5",
   "family": "NFR",
   "group": "Qualité code",
   "text": "Pyramide test 70% unit / 20% feature / 5% Pact / 5% E2E Playwright (cible roadmap qualité)."
  },
  {
   "code": "NFR-Quality-6",
   "family": "NFR",
   "group": "Qualité code",
   "text": "Pest Drift mutation testing nightly (informatif), seuil 70% mutation score (pas 100%)."
  },
  {
   "code": "NFR-Quality-7",
   "family": "NFR",
   "group": "Qualité code",
   "text": "driftingly/rector-laravel v2 rules appliqués (refactoring Laravel-specific)."
  },
  {
   "code": "NFR-A11y-1",
   "family": "NFR",
   "group": "Accessibilité",
   "text": "Contraste texte body AA 4.5:1 minimum (la majorité passent AAA grâce à bg <code>#0A0A0B</code>)."
  },
  {
   "code": "NFR-A11y-2",
   "family": "NFR",
   "group": "Accessibilité",
   "text": "Contraste texte large ≥18px ou ≥14px bold : AA 3:1 minimum."
  },
  {
   "code": "NFR-A11y-3",
   "family": "NFR",
   "group": "Accessibilité",
   "text": "Tap targets mobile ≥44×44px (Apple HIG)."
  },
  {
   "code": "NFR-A11y-4",
   "family": "NFR",
   "group": "Accessibilité",
   "text": "Navigation clavier complète (Tab order logique, Enter/Space active boutons, Escape ferme modales)."
  },
  {
   "code": "NFR-A11y-5",
   "family": "NFR",
   "group": "Accessibilité",
   "text": "Focus visible — outline ring Lava 0.4 opacity + outline-offset 2px sur tous <code>:focus-visible</code>."
  },
  {
   "code": "NFR-A11y-6",
   "family": "NFR",
   "group": "Accessibilité",
   "text": "Reduced motion respect — <code>@media (prefers-reduced-motion: reduce)</code> → durations 0.01ms (badge LIVE pulse devient statique)."
  },
  {
   "code": "NFR-A11y-7",
   "family": "NFR",
   "group": "Accessibilité",
   "text": "Skip-to-content link <code>&lt;a href=\"#main\"&gt;</code> premier focusable de la page."
  },
  {
   "code": "NFR-A11y-8",
   "family": "NFR",
   "group": "Accessibilité",
   "text": "<code>&lt;html lang=\"fr\"&gt;</code> exclusif v1 (audience FR-only)."
  },
  {
   "code": "NFR-A11y-9",
   "family": "NFR",
   "group": "Accessibilité",
   "text": "Alt text obligatoire sur toute image (validation Filament backend)."
  },
  {
   "code": "NFR-A11y-10",
   "family": "NFR",
   "group": "Accessibilité",
   "text": "Heading hierarchy stricte (H1 unique, H2/H3 séquentiels, pas de saut)."
  },
  {
   "code": "NFR-Cadence-1",
   "family": "NFR",
   "group": "Cadence éditoriale",
   "text": "Cadence éditoriale steady 3 articles/mois après M+1 (mitigation P1 PRD §8 — pas tenue = SEO mort)."
  },
  {
   "code": "NFR-Cadence-2",
   "family": "NFR",
   "group": "Cadence éditoriale",
   "text": "Workflow publish review brouillon → publié &lt;10 min chrono (critère go S2 LOCKED)."
  },
  {
   "code": "NFR-Cadence-3",
   "family": "NFR",
   "group": "Cadence éditoriale",
   "text": "Capital M0 = 3 articles publiés jour 1 (sweet spot signal éditorial vivant)."
  },
  {
   "code": "NFR-Cadence-4",
   "family": "NFR",
   "group": "Cadence éditoriale",
   "text": "Métrique stratégique M+12 : % trafic organique sur articles &gt;6 mois &gt;40% (signal moat evergreen compounding)."
  },
  {
   "code": "NFR-Cadence-5",
   "family": "NFR",
   "group": "Cadence éditoriale",
   "text": "Métrique stratégique M+18 : % trafic organique articles &gt;6 mois &gt;60%."
  },
  {
   "code": "NFR-Metric-1",
   "family": "NFR",
   "group": "Métriques M+6 LOCKED",
   "text": "1500 visiteurs uniques/mois sur le site (M+6)."
  },
  {
   "code": "NFR-Metric-2",
   "family": "NFR",
   "group": "Métriques M+6 LOCKED",
   "text": "+200 followers Twitch attribués UTM (M+6) — discipline stream-side mandatory."
  },
  {
   "code": "NFR-Metric-3",
   "family": "NFR",
   "group": "Métriques M+6 LOCKED",
   "text": "10-15 articles publiés cumulés (M+6)."
  },
  {
   "code": "NFR-Metric-4",
   "family": "NFR",
   "group": "Métriques M+6 LOCKED",
   "text": "Time-on-page médiane reviews &gt;3min."
  },
  {
   "code": "NFR-Metric-5",
   "family": "NFR",
   "group": "Métriques M+6 LOCKED",
   "text": "Bounce rate reviews &lt;60%."
  },
  {
   "code": "NFR-Metric-6",
   "family": "NFR",
   "group": "Métriques M+6 LOCKED",
   "text": "Home→embed Twitch (LIVE) &gt;40%."
  },
  {
   "code": "NFR-Metric-7",
   "family": "NFR",
   "group": "Métriques M+6 LOCKED",
   "text": "Home→article (OFFLINE) &gt;25%."
  },
  {
   "code": "NFR-Metric-8",
   "family": "NFR",
   "group": "Métriques M+6 LOCKED",
   "text": "Downloads SVG individuels press &gt;5/mois M+3+."
  },
  {
   "code": "NFR-Metric-9",
   "family": "NFR",
   "group": "Métriques M+6 LOCKED",
   "text": "Taux réponse pitchs Keymailer &gt;15% M+6."
  },
  {
   "code": "NFR-Metric-10",
   "family": "NFR",
   "group": "Métriques M+6 LOCKED",
   "text": "1er fork actif M+6, 2-3 streamers hébergés gratos M+9, 1 review page-1 Google long-tail M+6."
  },
  {
   "code": "NFR-Browser-1",
   "family": "NFR",
   "group": "Compatibilité navigateurs",
   "text": "Support Chrome / Edge (Chromium) / Firefox Evergreen."
  },
  {
   "code": "NFR-Browser-2",
   "family": "NFR",
   "group": "Compatibilité navigateurs",
   "text": "Support Safari macOS 17+ (2023+)."
  },
  {
   "code": "NFR-Browser-3",
   "family": "NFR",
   "group": "Compatibilité navigateurs",
   "text": "Support Safari iOS 16+."
  },
  {
   "code": "NFR-Browser-4",
   "family": "NFR",
   "group": "Compatibilité navigateurs",
   "text": "Support Samsung Internet stable récent (secondaire, BrowserStack si signal)."
  },
  {
   "code": "NFR-Browser-5",
   "family": "NFR",
   "group": "Compatibilité navigateurs",
   "text": "Non-support explicite IE 11, Opera Mini, navigateurs forks obscurs."
  },
  {
   "code": "NFR-Stack-1",
   "family": "NFR",
   "group": "Stack technique",
   "text": "PHP 8.4 LTS-friendly cible par défaut, 8.5.1 derrière flag."
  },
  {
   "code": "NFR-Stack-2",
   "family": "NFR",
   "group": "Stack technique",
   "text": "Laravel 12 (re-check L13 octobre 2026, Filament v3 = verrou écosystème)."
  },
  {
   "code": "NFR-Stack-3",
   "family": "NFR",
   "group": "Stack technique",
   "text": "PostgreSQL 17 Alpine seul moteur (ADR-0007), pas de matrice multi-DB."
  },
  {
   "code": "NFR-Stack-4",
   "family": "NFR",
   "group": "Stack technique",
   "text": "Redis 8.6 Alpine (cache + queue + sessions)."
  },
  {
   "code": "NFR-Stack-5",
   "family": "NFR",
   "group": "Stack technique",
   "text": "Node 24 LTS Krypton (frontend build)."
  },
  {
   "code": "NFR-Stack-6",
   "family": "NFR",
   "group": "Stack technique",
   "text": "Apache 2.4 HTTPS/HTTP2 (ADR-0005, Caddy reporté v1.5)."
  },
  {
   "code": "NFR-Mobile-1",
   "family": "NFR",
   "group": "Responsive & Mobile-first",
   "text": "Mobile-first contenu (Reader-Gamer Chercheur Google prio v1) — chaque écran designé d'abord pour 360px portrait."
  },
  {
   "code": "NFR-Mobile-2",
   "family": "NFR",
   "group": "Responsive & Mobile-first",
   "text": "Desktop-first admin Filament (1280px+)."
  },
  {
   "code": "NFR-Mobile-3",
   "family": "NFR",
   "group": "Responsive & Mobile-first",
   "text": "Tablette portrait (≥768&lt;1024) délibérément ignorée — traitée comme mobile XL."
  },
  {
   "code": "NFR-Mobile-4",
   "family": "NFR",
   "group": "Responsive & Mobile-first",
   "text": "Premier glance LIVE/OFFLINE perception &lt;300ms."
  },
  {
   "code": "NFR-Mobile-5",
   "family": "NFR",
   "group": "Responsive & Mobile-first",
   "text": "Article body max-width 720px desktop immuable (Stripe Press pattern)."
  },
  {
   "code": "NFR-Mobile-6",
   "family": "NFR",
   "group": "Responsive & Mobile-first",
   "text": "Chat Twitch iframe masqué &lt;768px (PRD §7 mobile-first contenu)."
  },
  {
   "code": "NFR-SEO-1",
   "family": "NFR",
   "group": "SEO",
   "text": "Schema.org Review + VideoGame + Person + Article complet sur toutes pages relevantes."
  },
  {
   "code": "NFR-SEO-2",
   "family": "NFR",
   "group": "SEO",
   "text": "Sitemap.xml + RSS auto-générés, <code>&lt;lastmod&gt;</code> reflète <code>last_updated_at</code>."
  },
  {
   "code": "NFR-SEO-3",
   "family": "NFR",
   "group": "SEO",
   "text": "Slug long éditorial <code>/reviews/{slug}</code> (Str::slug ASCII pur, max 180 chars, unique global)."
  },
  {
   "code": "NFR-SEO-4",
   "family": "NFR",
   "group": "SEO",
   "text": "Update-in-place préserve link equity + dateModified (challenge #9 LOCKED)."
  },
  {
   "code": "NFR-SEO-5",
   "family": "NFR",
   "group": "SEO",
   "text": "Internal linking automatique entre reviews liées (tags partagés ≥2)."
  },
  {
   "code": "NFR-SEO-6",
   "family": "NFR",
   "group": "SEO",
   "text": "Pas de duplicate content (URL canonical) entre archive pages et listing."
  },
  {
   "code": "NFR-SEO-7",
   "family": "NFR",
   "group": "SEO",
   "text": "OG images pré-générées 1200×630 (Twitter Card + Facebook OG)."
  },
  {
   "code": "NFR-SEO-8",
   "family": "NFR",
   "group": "SEO",
   "text": "Schema.org <code>datePublished</code> + <code>dateModified</code> sur reviews — boost Google freshness."
  },
  {
   "code": "NFR-Monit-1",
   "family": "NFR",
   "group": "Monitoring & Backup",
   "text": "Sentry free tier (5k events/mois) — erreurs prod externes."
  },
  {
   "code": "NFR-Monit-2",
   "family": "NFR",
   "group": "Monitoring & Backup",
   "text": "Pulse sur DB séparée <code>postgres-pulse</code> (ADR-0004) — éviter contention I/O."
  },
  {
   "code": "NFR-Monit-3",
   "family": "NFR",
   "group": "Monitoring & Backup",
   "text": "Pulse DB rotation 7j max + alert Discord à 80% disk usage."
  },
  {
   "code": "NFR-Monit-4",
   "family": "NFR",
   "group": "Monitoring & Backup",
   "text": "Uptime-Kuma monitor <code>/health</code> + alert Discord (cut v1 si glissement)."
  },
  {
   "code": "NFR-Monit-5",
   "family": "NFR",
   "group": "Monitoring & Backup",
   "text": "Logs JSON structurés sur disque + logrotate."
  },
  {
   "code": "NFR-Backup-1",
   "family": "NFR",
   "group": "Monitoring & Backup",
   "text": "Rotation 14 jours backup local Postgres app (suppression plus ancien si &gt;14)."
  },
  {
   "code": "NFR-Backup-2",
   "family": "NFR",
   "group": "Monitoring & Backup",
   "text": "Test integrity <code>pg_restore --list</code> après chaque dump (Bats nightly)."
  },
  {
   "code": "NFR-Backup-3",
   "family": "NFR",
   "group": "Monitoring & Backup",
   "text": "Upgrade backup B2 payant <b>avant</b> d'héberger données tiers (M+6+ trigger LOCKED ADR-0003)."
  },
  {
   "code": "NFR-Risk-1",
   "family": "NFR",
   "group": "Risques produit",
   "text": "P1 cadence éditoriale 3/mois (mitigation : capital M0 = 3 articles J1, checklist publication, Murat flag scope creep si Alex code au lieu d'écrire)."
  },
  {
   "code": "NFR-Risk-2",
   "family": "NFR",
   "group": "Risques produit",
   "text": "P2 UTM Twitch unidirectionnel (mitigation : checklist stream-side obligatoire, panel Twitch + <code>!commande</code> + lower-third)."
  },
  {
   "code": "NFR-Risk-3",
   "family": "NFR",
   "group": "Risques produit",
   "text": "P3 press kit pas crédible M+1 (mitigation : 3 reviews publiées + bio FR+EN + stats P50 visibles M0, pitch templaté)."
  },
  {
   "code": "NFR-Risk-4",
   "family": "NFR",
   "group": "Risques produit",
   "text": "P5 JTBD n°3 dev gifting non tracké (mitigation : UTM auto-généré bouton \"copier le lien\" S5 ~1h dev)."
  },
  {
   "code": "NFR-Risk-5",
   "family": "NFR",
   "group": "Risques produit",
   "text": "P6 OG génération lente (mitigation : job async + retry 3x + fallback OG statique)."
  },
  {
   "code": "NFR-Risk-6",
   "family": "NFR",
   "group": "Risques produit",
   "text": "P7 Reader-Gamer juge note vanity (mitigation : verdict en intro justifie note, barre Lava 9+ seulement si vraie conviction)."
  },
  {
   "code": "NFR-Risk-7",
   "family": "NFR",
   "group": "Risques produit",
   "text": "P8 Filament v3 deprecated par v4 (mitigation : pin version exacte Composer, re-évaluation L13/Filament v4 octobre 2026)."
  },
  {
   "code": "AR-Starter-1",
   "family": "AR",
   "group": "Starter Template / Bootstrap",
   "text": "<b>Pas de starter custom</b> — <code>composer create-project laravel/laravel src</code> Laravel 12 vanilla, puis ajout Filament v3 via <code>composer require filament/filament</code> + <code>php artisan filament:install --panels</code>. Skeleton est l'add-on autour du <code>/src</code> vide."
  },
  {
   "code": "AR-Starter-2",
   "family": "AR",
   "group": "Starter Template / Bootstrap",
   "text": "<code>/src</code> vide à J0 — Phase 1 <code>make install-dev-full</code> installe Laravel 12 + migrations 16 tables + <code>/health</code> 200 OK (déjà testé end-to-end 2026-05-08 mémoire session)."
  },
  {
   "code": "AR-Stack-1",
   "family": "AR",
   "group": "Stack runtime",
   "text": "PHP-FPM 8.4 LTS-friendly conteneur <code>php</code>, PHP 8.5.1 derrière flag."
  },
  {
   "code": "AR-Stack-2",
   "family": "AR",
   "group": "Stack runtime",
   "text": "Apache 2.4 HTTPS/HTTP2 conteneur <code>apache</code> (ADR-0005, Caddy reporté v1.5)."
  },
  {
   "code": "AR-Stack-3",
   "family": "AR",
   "group": "Stack runtime",
   "text": "PostgreSQL 17 Alpine conteneur <code>postgres</code> (ADR-0007)."
  },
  {
   "code": "AR-Stack-4",
   "family": "AR",
   "group": "Stack runtime",
   "text": "PostgreSQL 17 Alpine conteneur isolé <code>postgres-pulse</code> (ADR-0004)."
  },
  {
   "code": "AR-Stack-5",
   "family": "AR",
   "group": "Stack runtime",
   "text": "Redis 8.6 Alpine conteneur <code>redis</code>."
  },
  {
   "code": "AR-Stack-6",
   "family": "AR",
   "group": "Stack runtime",
   "text": "Node.js LTS Krypton 24 conteneur <code>node</code> (profile dev uniquement)."
  },
  {
   "code": "AR-Modular-1",
   "family": "AR",
   "group": "Architecture modulaire",
   "text": "Structure <code>app/Core/</code> + <code>app/Modules/{Public, Live, Reviews, PressKit, Admin}/</code> PSR-4 natif."
  },
  {
   "code": "AR-Modular-2",
   "family": "AR",
   "group": "Architecture modulaire",
   "text": "Refus explicites listés : <code>nwidart/laravel-modules</code>, DDD/hexagonal, repositories systématiques, façades custom, event bus J1, CQRS/Command Bus, DTOs systématiques, <code>app/Domain</code>/<code>UseCases</code>/<code>Application</code>, discovery automatique Filament."
  },
  {
   "code": "AR-Modular-3",
   "family": "AR",
   "group": "Architecture modulaire",
   "text": "Service providers conditionnels via <code>config/modules.php</code> + <code>AppServiceProvider::register()</code> boucle."
  },
  {
   "code": "AR-Modular-4",
   "family": "AR",
   "group": "Architecture modulaire",
   "text": "Migrations module-scoped (<code>Modules/X/Database/migrations/</code>) + <code>loadMigrationsFrom()</code> dans provider."
  },
  {
   "code": "AR-Modular-5",
   "family": "AR",
   "group": "Architecture modulaire",
   "text": "Routes module-scoped (<code>Modules/X/routes.php</code>) + chargement provider."
  },
  {
   "code": "AR-Modular-6",
   "family": "AR",
   "group": "Architecture modulaire",
   "text": "Tests par module (<code>tests/Feature/Modules/X/</code>, <code>tests/Unit/Modules/X/</code>)."
  },
  {
   "code": "AR-Data-1",
   "family": "AR",
   "group": "Données",
   "text": "Colonne <code>streamer_id BIGINT NOT NULL</code> sur toutes les tables métier J1."
  },
  {
   "code": "AR-Data-2",
   "family": "AR",
   "group": "Données",
   "text": "Index composite <code>(streamer_id, created_at DESC)</code> sur tables fréquemment listées."
  },
  {
   "code": "AR-Data-3",
   "family": "AR",
   "group": "Données",
   "text": "Slug <code>VARCHAR(180) UNIQUE</code> pour Reviews."
  },
  {
   "code": "AR-Data-4",
   "family": "AR",
   "group": "Données",
   "text": "<code>published_at TIMESTAMP NULL</code> + <code>last_updated_at TIMESTAMP NULL</code> pour différentiation brouillon/publié/maintenu."
  },
  {
   "code": "AR-Data-5",
   "family": "AR",
   "group": "Données",
   "text": "<code>cover_url TEXT NULL</code> (pas stockage local v1, embed/CDN externe ou Filament FileUpload local)."
  },
  {
   "code": "AR-Data-6",
   "family": "AR",
   "group": "Données",
   "text": "Type JSONB + index GIN pour metadata (settings Filament, payloads webhooks Twitch/YouTube)."
  },
  {
   "code": "AR-Data-7",
   "family": "AR",
   "group": "Données",
   "text": "Full-text search FR natif (<code>to_tsvector('french', body)</code>) — disponible mais non-activé v1, prêt v1.5+."
  },
  {
   "code": "AR-Docker-1",
   "family": "AR",
   "group": "Infra Docker",
   "text": "Profile aucun (Production) : apache, php, postgres, postgres-pulse, redis."
  },
  {
   "code": "AR-Docker-2",
   "family": "AR",
   "group": "Infra Docker",
   "text": "Profile <code>dev</code> : + node, mailpit, adminer."
  },
  {
   "code": "AR-Docker-3",
   "family": "AR",
   "group": "Infra Docker",
   "text": "Profile <code>tools</code> : + dozzle, it-tools, watchtower."
  },
  {
   "code": "AR-Docker-4",
   "family": "AR",
   "group": "Infra Docker",
   "text": "Profile <code>dev-extra</code> : + phpmyadmin, redis-commander."
  },
  {
   "code": "AR-Docker-5",
   "family": "AR",
   "group": "Infra Docker",
   "text": "Images custom (php, apache, node) — pinned Dockerfile, exclu Watchtower auto-update."
  },
  {
   "code": "AR-Docker-6",
   "family": "AR",
   "group": "Infra Docker",
   "text": "Images officielles (postgres:17-alpine, redis:8.6-alpine, adminer, mailpit) — Watchtower auto-update."
  },
  {
   "code": "AR-Docker-7",
   "family": "AR",
   "group": "Infra Docker",
   "text": "Réseau bridge interne, seul <code>apache</code> expose <code>:80</code> et <code>:443</code> à l'hôte."
  },
  {
   "code": "AR-Quality-1",
   "family": "AR",
   "group": "Stack qualité",
   "text": "<code>pestphp/pest</code> ^4 + <code>pestphp/pest-plugin-laravel</code> ^4 + <code>pestphp/pest-plugin-drift</code> ^4 (mutation testing)."
  },
  {
   "code": "AR-Quality-2",
   "family": "AR",
   "group": "Stack qualité",
   "text": "<code>larastan/larastan</code> ^3 — PHPStan level 8."
  },
  {
   "code": "AR-Quality-3",
   "family": "AR",
   "group": "Stack qualité",
   "text": "<code>symplify/easy-coding-standard</code> ^13 — PSR-12."
  },
  {
   "code": "AR-Quality-4",
   "family": "AR",
   "group": "Stack qualité",
   "text": "<code>rector/rector</code> ^2.3 + <code>driftingly/rector-laravel</code> ^2 (rules PHP 8.5 + Laravel 12)."
  },
  {
   "code": "AR-Quality-5",
   "family": "AR",
   "group": "Stack qualité",
   "text": "<code>nunomaduro/phpinsights</code> ^2.14 (metrics)."
  },
  {
   "code": "AR-Quality-6",
   "family": "AR",
   "group": "Stack qualité",
   "text": "<code>php-code-archeology/php-code-archeology</code> ^2 (architecture metrics + churn)."
  },
  {
   "code": "AR-Quality-7",
   "family": "AR",
   "group": "Stack qualité",
   "text": "Snyk security scanning (PHP + Node, hebdomadaire)."
  },
  {
   "code": "AR-App-1",
   "family": "AR",
   "group": "Stack applicative",
   "text": "<code>filament/filament</code> ^3 (admin panel + tenancy native OFF v1, ON v2+)."
  },
  {
   "code": "AR-App-2",
   "family": "AR",
   "group": "Stack applicative",
   "text": "<code>livewire/livewire</code> ^3 (composants serveur, cohérence Filament)."
  },
  {
   "code": "AR-App-3",
   "family": "AR",
   "group": "Stack applicative",
   "text": "<code>laravel/sanctum</code> ^4 (tokens API + SPA cookies)."
  },
  {
   "code": "AR-App-4",
   "family": "AR",
   "group": "Stack applicative",
   "text": "<code>spatie/laravel-permission</code> ^7 (roles + permissions)."
  },
  {
   "code": "AR-App-5",
   "family": "AR",
   "group": "Stack applicative",
   "text": "<code>spatie/laravel-activitylog</code> ^5 (audit trail JSON structured)."
  },
  {
   "code": "AR-App-6",
   "family": "AR",
   "group": "Stack applicative",
   "text": "<code>spatie/laravel-csp</code> ^3 (headers Content-Security-Policy)."
  },
  {
   "code": "AR-App-7",
   "family": "AR",
   "group": "Stack applicative",
   "text": "<code>spatie/laravel-cookie-consent</code> (RGPD pré-embed Twitch/YouTube)."
  },
  {
   "code": "AR-App-8",
   "family": "AR",
   "group": "Stack applicative",
   "text": "<code>spatie/laravel-health</code> ^1 (endpoint <code>/health</code> JSON)."
  },
  {
   "code": "AR-App-9",
   "family": "AR",
   "group": "Stack applicative",
   "text": "<code>spatie/laravel-schedule-monitor</code> ^4 (surveillance cron)."
  },
  {
   "code": "AR-App-10",
   "family": "AR",
   "group": "Stack applicative",
   "text": "<code>laravel/pennant</code> ^1 (feature flags J1 toggles dev solo + gating SaaS v3)."
  },
  {
   "code": "AR-App-11",
   "family": "AR",
   "group": "Stack applicative",
   "text": "<code>laravel/horizon</code> ^5 (queue monitoring <code>/horizon</code>)."
  },
  {
   "code": "AR-App-12",
   "family": "AR",
   "group": "Stack applicative",
   "text": "<code>laravel/pulse</code> ^1 (realtime monitoring <code>/pulse</code> sur DB séparée)."
  },
  {
   "code": "AR-App-13",
   "family": "AR",
   "group": "Stack applicative",
   "text": "<code>laravel/telescope</code> ^5 (debug dev only, <code>/telescope</code>)."
  },
  {
   "code": "AR-App-14",
   "family": "AR",
   "group": "Stack applicative",
   "text": "<code>fruitcake/laravel-debugbar</code> ^4 (dev only)."
  },
  {
   "code": "AR-App-15",
   "family": "AR",
   "group": "Stack applicative",
   "text": "<code>blade-ui-kit/blade-icons</code> + Lucide pack (iconographie stroke 1.5px)."
  },
  {
   "code": "AR-App-16",
   "family": "AR",
   "group": "Stack applicative",
   "text": "<code>barryvdh/laravel-ide-helper</code> ^3 (autocompletion IDE)."
  },
  {
   "code": "AR-Ext-1",
   "family": "AR",
   "group": "Intégrations externes",
   "text": "Twitch Helix API client (rate-limit aware, cache Redis 60s) — badge LIVE + viewers concurrents."
  },
  {
   "code": "AR-Ext-2",
   "family": "AR",
   "group": "Intégrations externes",
   "text": "YouTube Helix API client (validation VOD existence, job nightly check disponibilité)."
  },
  {
   "code": "AR-Ext-3",
   "family": "AR",
   "group": "Intégrations externes",
   "text": "Resend SMTP outbound (driver Laravel natif) — formulaire contact press kit (OQ8 LOCKED, free tier 100/jour)."
  },
  {
   "code": "AR-Ext-4",
   "family": "AR",
   "group": "Intégrations externes",
   "text": "Browsershot (FFmpeg + Chrome headless) pour génération OG images."
  },
  {
   "code": "AR-Ext-5",
   "family": "AR",
   "group": "Intégrations externes",
   "text": "Pas de S3/Backblaze/MinIO v1 (stockage local + symlink Laravel standard)."
  },
  {
   "code": "AR-Ext-6",
   "family": "AR",
   "group": "Intégrations externes",
   "text": "Pas de Sentry payant (free tier 5k events/mois suffit v1)."
  },
  {
   "code": "AR-Ext-7",
   "family": "AR",
   "group": "Intégrations externes",
   "text": "Pas de Nightwatch payant v1 (Sentry + Pulse couvrent)."
  },
  {
   "code": "AR-Roadmap-1",
   "family": "AR",
   "group": "Roadmap exécution",
   "text": "Phase 0 / S0 — Scaffolding modulaire 40h (25h back + 14.5h front + 0.5h buffer) — <b>bloquant tout S1</b>."
  },
  {
   "code": "AR-Roadmap-2",
   "family": "AR",
   "group": "Roadmap exécution",
   "text": "Phase 1 / S-2 → S-1 — Refactor skeleton install ~10j."
  },
  {
   "code": "AR-Roadmap-3",
   "family": "AR",
   "group": "Roadmap exécution",
   "text": "Phase 2 / S0 — Bootstrap obs/CI ~6j (Sentry + Pulse + Health + Uptime-Kuma + GitHub Actions + backups + hardening VPS)."
  },
  {
   "code": "AR-Roadmap-4",
   "family": "AR",
   "group": "Roadmap exécution",
   "text": "Phase 3 / S1 → S6 — Produit v1 ~24j (S1 Live + S2 Reviews + S3 SKIP comments + S4 SEO+Press+OG + S5 Preview+Cookie+UTM + S6 Polish Caravaggio)."
  },
  {
   "code": "AR-Roadmap-5",
   "family": "AR",
   "group": "Roadmap exécution",
   "text": "Phase 4 / S7 — Polish OSS ~5j (README + ADRs + Demo live optionnelle + fichiers OSS + Bats E2E)."
  },
  {
   "code": "AR-Roadmap-6",
   "family": "AR",
   "group": "Roadmap exécution",
   "text": "Total ~55j sur 50j ouvrés → réalisme 11-12 semaines."
  },
  {
   "code": "AR-Roadmap-7",
   "family": "AR",
   "group": "Roadmap exécution",
   "text": "Mitigation glissement — cut Demo live + Uptime-Kuma v1 → ~53j → tient en 10 sem avec ~1j buffer."
  },
  {
   "code": "AR-Flag-1",
   "family": "AR",
   "group": "Feature flags Pennant J1",
   "text": "<code>og-dynamic-pre-render</code> — bascule génération job vs fallback OG statique (mitigation P6)."
  },
  {
   "code": "AR-Flag-2",
   "family": "AR",
   "group": "Feature flags Pennant J1",
   "text": "<code>comments-enabled</code> — coupe globalement la modération si activée M+1 puis surcharge."
  },
  {
   "code": "AR-Flag-3",
   "family": "AR",
   "group": "Feature flags Pennant J1",
   "text": "<code>youtube-helix-check</code> — désactive check VOD nightly si quota API dépassé."
  },
  {
   "code": "AR-Flag-4",
   "family": "AR",
   "group": "Feature flags Pennant J1",
   "text": "<code>keymailer-pitch-tracker</code> — active tracking acceptation pitchs (mesure JTBD §4.2)."
  },
  {
   "code": "AR-Process-1",
   "family": "AR",
   "group": "Pages process à créer",
   "text": "<code>docs/process/03-stream-discipline.md</code> (Phase 2) — mitigation P2 UTM Twitch (panel Twitch + !commande + lower-third checklist)."
  },
  {
   "code": "AR-Process-2",
   "family": "AR",
   "group": "Pages process à créer",
   "text": "<code>docs/process/04-publication-checklist.md</code> (Phase 2) — mitigation P1 cadence éditoriale."
  },
  {
   "code": "AR-Process-3",
   "family": "AR",
   "group": "Pages process à créer",
   "text": "<code>docs/process/04-bio-en-workflow.md</code> (Phase 3) — workflow Claude/ChatGPT + relecture Alex (OQ4)."
  },
  {
   "code": "AR-Process-4",
   "family": "AR",
   "group": "Pages process à créer",
   "text": "<code>docs/design-system.md</code> (Phase 0/S0) — tokens + composants + patterns + anti-patterns."
  },
  {
   "code": "AR-Process-5",
   "family": "AR",
   "group": "Pages process à créer",
   "text": "<code>docs/process/secrets-management.md</code> (Phase 2) — <code>env:encrypt</code> workflow + rotation + recovery."
  },
  {
   "code": "AR-Risk-1",
   "family": "AR",
   "group": "Risques architecturaux flaggés à monitorer",
   "text": "Couplage inter-modules direct (acceptable v1, refactor events v1.5 si &gt;3 cas)."
  },
  {
   "code": "AR-Risk-2",
   "family": "AR",
   "group": "Risques architecturaux flaggés à monitorer",
   "text": "<code>streamer_id</code> oublié dans migration (test Pest scan migrations, bloquant CI dès S0)."
  },
  {
   "code": "AR-Risk-3",
   "family": "AR",
   "group": "Risques architecturaux flaggés à monitorer",
   "text": "RLS naïf si activé prématurément (ADR-0002 + doc, ne pas activer avant audit Filament v3 tenancy)."
  },
  {
   "code": "AR-Risk-4",
   "family": "AR",
   "group": "Risques architecturaux flaggés à monitorer",
   "text": "Pulse DB sature disque VPS (Spatie Health check DiskSpace + rotation 7j max + alert Discord à 80%)."
  },
  {
   "code": "AR-Risk-5",
   "family": "AR",
   "group": "Risques architecturaux flaggés à monitorer",
   "text": "OG image génération lente bloque publish (job async + retry 3x + fallback OG statique, fallback en place dès S4)."
  },
  {
   "code": "AR-Risk-6",
   "family": "AR",
   "group": "Risques architecturaux flaggés à monitorer",
   "text": "Backup offsite jamais activé (M+6 hard-stop avant 1er streamer ami hébergé)."
  },
  {
   "code": "AR-Risk-7",
   "family": "AR",
   "group": "Risques architecturaux flaggés à monitorer",
   "text": "Pennant tables grossissent si flag-fest (audit S6 si &gt;20 flags, prévision &lt;10)."
  },
  {
   "code": "AR-Risk-8",
   "family": "AR",
   "group": "Risques architecturaux flaggés à monitorer",
   "text": "PostgreSQL 17 trop récent en prod hosting (vérifier dispo image Alpine stable, fallback Postgres 16 si bloquant)."
  },
  {
   "code": "UX-DR-1",
   "family": "UX-DR",
   "group": "Composants Blade base",
   "text": "<code>&lt;x-button&gt;</code> 3 variants (<code>primary</code> Lava réservé 4 catégories : LIVE/CTA primaire site/notes 9+/destructives admin · <code>secondary</code> standards · <code>ghost</code> tertiaires) + 5 states (default/hover/active/disabled/loading) + focus-visible."
  },
  {
   "code": "UX-DR-2",
   "family": "UX-DR",
   "group": "Composants Blade base",
   "text": "<code>&lt;x-card&gt;</code> container <code>bg-surface</code> + border configurable, 3 states (default/hover subtle elevation/selected)."
  },
  {
   "code": "UX-DR-3",
   "family": "UX-DR",
   "group": "Composants Blade base",
   "text": "<code>&lt;x-badge&gt;</code> inline pour status/tags/états — variants neutre/lava (LIVE only)/state-ok/state-warn/state-err."
  },
  {
   "code": "UX-DR-4",
   "family": "UX-DR",
   "group": "Composants Blade base",
   "text": "<code>&lt;x-icon-button&gt;</code> icon-only + tooltip natif + <code>aria-label</code> <b>obligatoire</b> via prop."
  },
  {
   "code": "UX-DR-5",
   "family": "UX-DR",
   "group": "Composants Blade base",
   "text": "<code>&lt;x-divider&gt;</code> separator horizontal/vertical avec optional text + <code>role=\"separator\"</code>."
  },
  {
   "code": "UX-DR-6",
   "family": "UX-DR",
   "group": "Composants Blade base",
   "text": "<code>&lt;x-toast&gt;</code> notification 4 types (success/error/warning/info) auto-dismiss 4-6s + dismissible + stack max 3 FIFO + <code>role=\"status\"|\"alert\"</code> selon type."
  },
  {
   "code": "UX-DR-7",
   "family": "UX-DR",
   "group": "Composants Time-as-texture",
   "text": "<code>&lt;x-time-relative :datetime=\"...\"&gt;</code> Carbon FR (\"il y a 3 jours\", \"depuis 2h17m\") + <code>&lt;time datetime=\"...\"&gt;</code> HTML sémantique + refresh client Alpine 60s pour durées évolutives."
  },
  {
   "code": "UX-DR-8",
   "family": "UX-DR",
   "group": "Composants Time-as-texture",
   "text": "<code>&lt;x-time-absolute :datetime=\"...\" :format=\"...\"&gt;</code> (\"14 mars 2026\") format paramétrable Carbon FR."
  },
  {
   "code": "UX-DR-9",
   "family": "UX-DR",
   "group": "Composants Time-as-texture",
   "text": "<code>&lt;x-time-dual :published :updated&gt;</code> (\"Publié X · Mis à jour Y\") conditionnel — updated affiché seulement si &gt; +30j."
  },
  {
   "code": "UX-DR-10",
   "family": "UX-DR",
   "group": "Composants Time-as-texture",
   "text": "<code>&lt;x-time-since :datetime=\"...\"&gt;</code> (\"Streaming depuis 4 ans\") format durée explicite."
  },
  {
   "code": "UX-DR-11",
   "family": "UX-DR",
   "group": "Composants Layout",
   "text": "<code>&lt;x-layouts.public&gt;</code> header sticky + footer + cookie gate + slots title/meta/main + skip-to-content link visible au focus + <code>&lt;html lang=\"fr\"&gt;</code>."
  },
  {
   "code": "UX-DR-12",
   "family": "UX-DR",
   "group": "Composants Layout",
   "text": "<code>&lt;x-layouts.minimal&gt;</code> pour pages erreur/système — pas de header/footer."
  },
  {
   "code": "UX-DR-13",
   "family": "UX-DR",
   "group": "Composants Public partagés",
   "text": "<code>&lt;x-nav&gt;</code> header sticky 48px mobile / 56px desktop — logo + 3 items max (Reviews/About/Press) + état LIVE intégré + backdrop-blur subtil + pas de burger menu."
  },
  {
   "code": "UX-DR-14",
   "family": "UX-DR",
   "group": "Composants Public partagés",
   "text": "<code>&lt;x-footer.follow&gt;</code> bloc \"Suivre Alex\" persistant footer (Pattern 3 \"Capture before bounce\") — Twitter + Discord + RSS visible texte, tenant-aware via <code>$settings</code>."
  },
  {
   "code": "UX-DR-15",
   "family": "UX-DR",
   "group": "Composants Public partagés",
   "text": "<code>&lt;x-footer&gt;</code> site standard (mentions légales · presse · GitHub · contact · copyright année courante) — pas de Lava."
  },
  {
   "code": "UX-DR-16",
   "family": "UX-DR",
   "group": "Composants Public partagés",
   "text": "<code>&lt;x-consent-gate&gt;</code> cookie consent bandeau bas-droite max 64px hauteur, 3 boutons text-link (Accept/Refuse/Personnaliser), jamais d'overlay plein écran."
  },
  {
   "code": "UX-DR-17",
   "family": "UX-DR",
   "group": "Composants Live",
   "text": "<code>&lt;livewire:live-status-badge&gt;</code> poll 60s + texte temporel \"LIVE since 2h17m\" Lava pulsant + circuit breaker 3 retries → fallback OFFLINE silencieux."
  },
  {
   "code": "UX-DR-18",
   "family": "UX-DR",
   "group": "Composants Live",
   "text": "<code>&lt;x-twitch-embed :channel=\"...\"&gt;</code> iframe officielle + cookie gate bloquant pré-chargement + chat masqué <code>@media (max-width: 767px)</code>."
  },
  {
   "code": "UX-DR-19",
   "family": "UX-DR",
   "group": "Composants Live",
   "text": "<code>&lt;x-offline-scene&gt;</code> \"Hors ligne · dernier stream il y a X\" + dernière review hero + replay YouTube + CTA press kit."
  },
  {
   "code": "UX-DR-20",
   "family": "UX-DR",
   "group": "Composants Reviews",
   "text": "<code>&lt;x-reviews.card&gt;</code> listing review (cover lazy + titre + note display compactée + verdict 1 ligne + <code>&lt;x-time-relative&gt;</code> date), variants archive vs sidebar."
  },
  {
   "code": "UX-DR-21",
   "family": "UX-DR",
   "group": "Composants Reviews",
   "text": "<code>&lt;x-reviews.header :article&gt;</code> above-the-fold mobile &lt;5s — titre H1 28-48px + note display 60-96px (couleur dépend tier) + verdict 1-3 phrases + <code>&lt;x-time-dual&gt;</code> métadonnées + \"8 min de lecture\"."
  },
  {
   "code": "UX-DR-22",
   "family": "UX-DR",
   "group": "Composants Reviews",
   "text": "<code>&lt;x-reviews.body :markdown&gt;</code> corps article max-width 720px desktop, padding-x 16px mobile, IBM Plex Sans 17-18px line-height 1.7."
  },
  {
   "code": "UX-DR-23",
   "family": "UX-DR",
   "group": "Composants Reviews",
   "text": "<code>&lt;x-reviews.timecode :video :time&gt;</code> \"[00:42]\" cliquable → YouTube <code>?t=42</code> nouvel onglet + <code>rel=\"noopener noreferrer\"</code>."
  },
  {
   "code": "UX-DR-24",
   "family": "UX-DR",
   "group": "Composants Reviews",
   "text": "<code>&lt;x-reviews.related :article&gt;</code> 3 cards horizontales articles liés (tags partagés ≥2) en fin d'article AVANT CTA Twitter/Discord (Pattern 3)."
  },
  {
   "code": "UX-DR-25",
   "family": "UX-DR",
   "group": "Composants Reviews",
   "text": "<code>&lt;x-reviews.archive-grid&gt;</code> listing pages <code>/{year}</code> / <code>/{tag}</code> / <code>/{game}</code> cursor pagination (scale 100+ articles M+24)."
  },
  {
   "code": "UX-DR-26",
   "family": "UX-DR",
   "group": "Composants Reviews",
   "text": "<code>&lt;x-reviews.empty-state&gt;</code> état nominal page archive vide (pattern Raycast — texte + CTA \"Voir tous les articles\", pas placeholder)."
  },
  {
   "code": "UX-DR-27",
   "family": "UX-DR",
   "group": "Composants CTAs",
   "text": "<code>&lt;x-cta.post-read :twitter :discord&gt;</code> fin d'article inline (pas sticky) — composant Blade tenant-aware lit <code>$settings-&gt;twitter</code> + <code>$settings-&gt;discord</code> (Victor R6) — copy archétype Ponce <i>\"On en discute ailleurs\"</i> — 1 clic nouvel onglet <code>_blank</code> + <code>rel=\"noopener noreferrer\"</code> — <b>pas de Lava</b> (preserve rareté signal LIVE)."
  },
  {
   "code": "UX-DR-28",
   "family": "UX-DR",
   "group": "Composants CTAs",
   "text": "<code>&lt;x-cta.live-now :stream-url&gt;</code> CTA primaire LIVE (Lava authorized — catégorie 1 des 4 réservées) — visible uniquement si état LIVE."
  },
  {
   "code": "UX-DR-29",
   "family": "UX-DR",
   "group": "Composants CTAs",
   "text": "<code>&lt;x-cta.copy-press-link&gt;</code> bouton \"Copier le lien press kit\" UTM-tracké (Alpine clipboard API + toast confirmation) — JTBD n°3 dev gifting tracking S5."
  },
  {
   "code": "UX-DR-30",
   "family": "UX-DR",
   "group": "Composants Press Kit",
   "text": "<code>&lt;x-press.kit :streamer&gt;</code> page <code>/press</code> tenant-aware Victor R6 — hiérarchie verticale stricte Stats &gt; Photo &gt; Bio (casse instinct \"photo first\") — max-width 960px desktop (13\" MacBook Air écran cible)."
  },
  {
   "code": "UX-DR-31",
   "family": "UX-DR",
   "group": "Composants Press Kit",
   "text": "<code>&lt;x-press.stats-block :data&gt;</code> P50 médianes (viewers + heures stream + nb VODs) avec <code>&lt;x-time-since&gt;</code> \"Streaming depuis 4 ans\" + sparkline subtile 7 derniers jours — jamais mean, jamais followers Twitch."
  },
  {
   "code": "UX-DR-32",
   "family": "UX-DR",
   "group": "Composants Press Kit",
   "text": "<code>&lt;x-press.trust-section&gt;</code> slots <code>data</code> + <code>methodology</code> (Pattern 2 trust signaling unifié) — méthodologie à 1 clic max (Wirecutter pattern)."
  },
  {
   "code": "UX-DR-33",
   "family": "UX-DR",
   "group": "Composants Press Kit",
   "text": "<code>&lt;x-press.download-button :file :format&gt;</code> SVG / PNG / Kit individuel — 1 clic = 1 fichier, pas zip global."
  },
  {
   "code": "UX-DR-34",
   "family": "UX-DR",
   "group": "Composants Press Kit",
   "text": "<code>&lt;x-press.contact-form&gt;</code> Livewire form (nom, mail, sujet, message) + validation inline real-time + Honeypot anti-spam + Resend driver natif (OQ8)."
  },
  {
   "code": "UX-DR-35",
   "family": "UX-DR",
   "group": "Templates OG Images",
   "text": "<code>og/review-stellar.blade.php</code> — note ≥9, barre Lava bottom + accent visuel fort + note 180px Lava <code>#FF5722</code>."
  },
  {
   "code": "UX-DR-36",
   "family": "UX-DR",
   "group": "Templates OG Images",
   "text": "<code>og/review-solid.blade.php</code> — note 7-8, pas de barre Lava, note 180px texte primaire <code>rgba(255,255,255,.92)</code>, accent état succès <code>#22C55E</code> discret."
  },
  {
   "code": "UX-DR-37",
   "family": "UX-DR",
   "group": "Templates OG Images",
   "text": "<code>og/review-light.blade.php</code> — note ≤6, note 180px texte secondaire <code>rgba(255,255,255,.60)</code>, pas d'accent (ton sobre, honnête)."
  },
  {
   "code": "UX-DR-38",
   "family": "UX-DR",
   "group": "Templates OG Images",
   "text": "<code>og/news.blade.php</code> — type ≠ review (news, preview), pas de note, titre 100% surface, badge <code>NEWS</code> ou <code>PREVIEW</code> Lava bottom-left."
  },
  {
   "code": "UX-DR-39",
   "family": "UX-DR",
   "group": "Templates OG Images",
   "text": "Composition commune 4 templates — background <code>#0A0A0B</code> flat (pas gradient), cover game left 40% si reviews, logo discret bottom-right, format unique 1200×630, IBM Plex Sans + Mono."
  },
  {
   "code": "UX-DR-40",
   "family": "UX-DR",
   "group": "Design tokens + Single source of truth",
   "text": "Tokens CSS variables dans <code>resources/css/tokens.css</code> (palette dark + Lava + states + typo + spacing + motion) — single source of truth, documenté <code>docs/architecture/2-stack-technique.md</code> §2.5."
  },
  {
   "code": "UX-DR-41",
   "family": "UX-DR",
   "group": "Design tokens + Single source of truth",
   "text": "Tailwind 4 config référence tokens CSS variables (<code>bg: 'var(--bg)'</code>, <code>'lava': 'var(--accent-lava)'</code>, etc.) — pas hardcode hex."
  },
  {
   "code": "UX-DR-42",
   "family": "UX-DR",
   "group": "Design tokens + Single source of truth",
   "text": "IBM Plex Sans + IBM Plex Mono self-hosted via <code>@fontsource</code> avec <code>preload</code> 3 weights (400, 600 sans, 400 mono) + <code>font-display: swap</code> (FOUT)."
  },
  {
   "code": "UX-DR-43",
   "family": "UX-DR",
   "group": "Design tokens + Single source of truth",
   "text": "Motion CSS pur — <code>--ease-default: cubic-bezier(0.16, 1, 0.3, 1)</code> + <code>--duration-default: 200ms</code> non bouncy — liste fixe disciplinée (badge LIVE pulse, hover CTA, page transition — rien d'autre)."
  },
  {
   "code": "UX-DR-44",
   "family": "UX-DR",
   "group": "Design tokens + Single source of truth",
   "text": "Discipline 90/8/2 mono/accent/états — Lava <code>#FF5722</code> réservé strictement 4 catégories — audit régulier <code>grep \"lava\" resources/</code>."
  },
  {
   "code": "UX-DR-45",
   "family": "UX-DR",
   "group": "Design tokens + Single source of truth",
   "text": "Dark-only assumé (pas toggle light) — signal d'identité Linear/Raycast/Astro Studio."
  },
  {
   "code": "UX-DR-46",
   "family": "UX-DR",
   "group": "Type scale + Spacing + Layout responsive",
   "text": "Type scale mobile-first — H1 28→48px / H2 22→28px / H3 18→20px / Body article 17→18px line-height 1.7 / Body UI 15→16px / Caption mono 13→14px / Note display 60→96px / Note OG 180px (1200×630)."
  },
  {
   "code": "UX-DR-47",
   "family": "UX-DR",
   "group": "Type scale + Spacing + Layout responsive",
   "text": "Spacing scale Tailwind 4px base — space-4 (16px) padding mobile / space-8 (32px) gaps standard / space-12 (48px) entre H2 et corps / space-24 (96px) gaps blocs majeurs."
  },
  {
   "code": "UX-DR-48",
   "family": "UX-DR",
   "group": "Type scale + Spacing + Layout responsive",
   "text": "Layout grid responsive — Mobile 1-col fluide padding-x 16px, Desktop max-width 1024px container / Article body 720px immuable / Press kit 960px max-width."
  },
  {
   "code": "UX-DR-49",
   "family": "UX-DR",
   "group": "Type scale + Spacing + Layout responsive",
   "text": "Cover image lazy-loaded + <code>width</code>/<code>height</code> attributes dimensions réservées (CLS=0) + <code>loading=\"lazy\"</code> natif + WebP format."
  },
  {
   "code": "UX-DR-50",
   "family": "UX-DR",
   "group": "UX patterns cross-cutting",
   "text": "Pattern \"Time as texture\" omniprésent (Direction C) — composants <code>&lt;x-time-<i>&gt;</code> IBM Plex Mono pour métadonnées temporelles, format Carbon FR systématique, liste </i>intentionnelle* (audit S6 Caravaggio)."
  },
  {
   "code": "UX-DR-51",
   "family": "UX-DR",
   "group": "UX patterns cross-cutting",
   "text": "Pattern \"Trust signaling progressif\" — composant <code>&lt;x-press.trust-section&gt;</code> slots data + methodology, méthodologie à 1 clic max, stats P50 médianes, historique transparent."
  },
  {
   "code": "UX-DR-52",
   "family": "UX-DR",
   "group": "UX patterns cross-cutting",
   "text": "Pattern \"Capture before bounce\" — articles liés AVANT CTA Twitter/Discord (Victor R6), <code>&lt;x-footer.follow&gt;</code> persistant footer, bouton \"Copier le lien press kit\" en fin /press."
  },
  {
   "code": "UX-DR-53",
   "family": "UX-DR",
   "group": "UX patterns cross-cutting",
   "text": "Pattern \"Fallback gracieux silencieux\" — aucune alerte UI \"API down\", Helix down → OFFLINE silencieux, Browsershot fail → OG statique, YT unavailable → flag <code>vod_unavailable</code> + affichage gracieux."
  },
  {
   "code": "UX-DR-54",
   "family": "UX-DR",
   "group": "UX patterns cross-cutting",
   "text": "Pattern \"Discipline anti-dark-pattern\" — aucune modale \"Are you sure ?\" sur actions non-destructives, no exit-intent popup, no newsletter déguisée, no scroll-jacking sticky bottom mobile."
  },
  {
   "code": "UX-DR-55",
   "family": "UX-DR",
   "group": "Accessibility",
   "text": "Skip-to-content link <code>&lt;a href=\"#main\"&gt;Aller au contenu&lt;/a&gt;</code> premier focusable, <code>sr-only focus:not-sr-only</code>."
  },
  {
   "code": "UX-DR-56",
   "family": "UX-DR",
   "group": "Accessibility",
   "text": "Tap targets mobile minimum 44×44px (Apple HIG) — boutons jamais plus petits + buttons full-width sur mobile dans forms."
  },
  {
   "code": "UX-DR-57",
   "family": "UX-DR",
   "group": "Accessibility",
   "text": "Focus visible — outline ring Lava 0.4 opacity 2px + <code>outline-offset: 2px</code> sur tous <code>:focus-visible</code>."
  },
  {
   "code": "UX-DR-58",
   "family": "UX-DR",
   "group": "Accessibility",
   "text": "Reduced motion CSS <code>@media (prefers-reduced-motion: reduce)</code> → durations 0.01ms, badge LIVE pulse devient statique opacity 1."
  },
  {
   "code": "UX-DR-59",
   "family": "UX-DR",
   "group": "Accessibility",
   "text": "Heading hierarchy stricte — H1 unique par page, H2/H3 séquentiels (validé axe-core CLI)."
  },
  {
   "code": "UX-DR-60",
   "family": "UX-DR",
   "group": "Accessibility",
   "text": "Color blindness safeguards — états (success/warn/error) toujours couleur + icône + texte cumulés, notes 9+/10 Lava + texte gros, liens texte couleur + underline."
  },
  {
   "code": "UX-DR-61",
   "family": "UX-DR",
   "group": "Implementation guidelines",
   "text": "Composants PSR-4 par module — <code>app/Modules/{Module}/Views/components/</code> (ADR-0009) + service provider enregistre via <code>Blade::componentNamespace()</code>."
  },
  {
   "code": "UX-DR-62",
   "family": "UX-DR",
   "group": "Implementation guidelines",
   "text": "Composants typés props PHP 8.4 enum ou DTOs (ex. <code>&lt;x-button variant=\"primary\"&gt;</code> avec enum <code>ButtonVariant</code>) — améliore PHPStan L8."
  },
  {
   "code": "UX-DR-63",
   "family": "UX-DR",
   "group": "Implementation guidelines",
   "text": "Tests Pest Browser sur composants critiques (badge LIVE, CTA, time-as-texture) — Tab walkthrough + alt presence + ARIA labels."
  },
  {
   "code": "UX-DR-64",
   "family": "UX-DR",
   "group": "Implementation guidelines",
   "text": "Slots pour flexibilité, props pour configuration — pattern Blade idiomatique, pas d'over-abstraction."
  },
  {
   "code": "UX-DR-65",
   "family": "UX-DR",
   "group": "Implementation guidelines",
   "text": "Documentation handoff <code>docs/design-system.md</code> Phase 0/S0 ~2h — tokens + composants + patterns + anti-patterns cumulatif steps 2/5/8/12."
  }
 ]
};

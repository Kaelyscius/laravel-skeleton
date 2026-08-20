<?php

declare(strict_types=1);

namespace App\Core\Console\Commands;

use App\Core\Support\TrustedProxies;
use Illuminate\Console\Command;

/**
 * Deploy gate for `TRUSTED_PROXIES` (Story 1.10a AC5, review decision D8).
 *
 * The entrypoint runs this BEFORE `php artisan config:cache`. That order is the
 * whole point: the refusal it carries used to be a `throw` inside
 * `config/proxies.php`, which fired while `config/` was being loaded — so one
 * typo broke `config:cache` at container start and then every artisan command
 * an operator could have used to repair it. Here the refusal is just as hard and
 * just as loud, but the application stays bootable and the check stays testable.
 *
 * Reads `config('proxies.problems')`, which `App\Core\Support\TrustedProxies`
 * fills at parse time. Because it is a config value, it is frozen into the
 * configuration cache alongside `proxies.at` — so this command tells the truth
 * both before and after `config:cache`.
 */
final class ProxiesCheckCommand extends Command
{
    protected $signature = 'proxies:check';

    protected $description = 'Assert TRUSTED_PROXIES parses to something that can actually match a client (Story 1.10a AC5).';

    public function handle(): int
    {
        /** @var array<int, string> $problems */
        $problems = config('proxies.problems', []);

        /** @var string|array<int, string> $at */
        $at = config('proxies.at');

        if ($problems === []) {
            $this->info(sprintf(
                'TRUSTED_PROXIES OK : %s',
                self::describe($at),
            ));

            // ⚠️ LE JOKER RESTE LÉGITIME, MAIS IL NE DOIT PLUS ÊTRE SILENCIEUX
            // (finding Q17, revue du 2026-08-20).
            //
            // Le défaut est passé de `*` à `REMOTE_ADDR` dans `.env.example`. Or
            // `.env.example` n'est pas `.env` : toute instance DÉJÀ DÉPLOYÉE garde
            // son `*` — donc son seau de limitation falsifiable — et rien ne le
            // détectait ni ne le signalait. Ce n'est pas une erreur (le joker
            // explicite reste une décision valable sur Laravel Cloud ou Vapor),
            // donc pas un échec ; mais l'opérateur qui met à jour doit le lire.
            if ($at === '*') {
                $this->newLine();
                $this->warn('⚠️  TRUSTED_PROXIES vaut `*` : TOUTE adresse d\'Internet est un proxy de confiance.');
                $this->warn('   `request()->ip()` rend alors le `X-Forwarded-For` écrit par le client, et la');
                $this->warn('   limitation des tentatives de connexion donne UN SEAU NEUF PAR TENTATIVE.');
                $this->warn('   C\'était le défaut jusqu\'au 2026-08-09 ; il ne l\'est plus. Si votre');
                $this->warn('   infrastructure ne garantit pas l\'en-tête, écrivez `TRUSTED_PROXIES=REMOTE_ADDR`');
                $this->warn('   ou énumérez vos proxys en CIDR (voir `.env.example`).');
            }

            return self::SUCCESS;
        }

        $this->error('TRUSTED_PROXIES est mal renseigné — le déploiement est refusé ici, pas au démarrage :');

        foreach ($problems as $problem) {
            $this->line('  • ' . $problem);
        }

        $this->newLine();
        $this->warn(sprintf(
            'Valeur effective si vous passez outre : %s',
            self::describe($at),
        ));
        $this->warn(
            'Une entrée qui ne correspond à aucun client fait rendre à `request()->ip()` l\'adresse du '
            . 'proxy amont : tous les clients partagent alors UN SEUL seau de limitation.',
        );

        return self::FAILURE;
    }

    /**
     * @param  string|array<int, string>  $at
     */
    private static function describe(string|array $at): string
    {
        if (is_string($at)) {
            return $at;
        }

        // `TRUST_NOBODY` N'EST PAS une absence de réglage : c'est LE défaut sûr, et
        // l'imprimer tel quel (`0.0.0.0/32`) laisserait un opérateur croire à une
        // valeur bizarre héritée d'ailleurs. On dit ce que ça FAIT.
        if ($at === TrustedProxies::TRUST_NOBODY || $at === []) {
            return 'aucun proxy de confiance (défaut sûr — X-Forwarded-* ignoré, request()->ip() = pair TCP)';
        }

        return implode(', ', $at);
    }
}

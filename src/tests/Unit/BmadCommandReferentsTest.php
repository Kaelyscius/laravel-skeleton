<?php

declare(strict_types=1);

use Tests\Support\RepoFile;

/*
|------------------------------------------------------------------------------
| Toute commande BMad prescrite par les docs de process doit exister — et vivre
|------------------------------------------------------------------------------
|
| 🔴 CE TEST EXISTE PARCE QUE LA MISE À JOUR BMAD 6.11.0 DU 2026-08-20 A LAISSÉ
|    SIX COMMANDES SANS AUCUN RÉFÉRENT DANS `02-bmad-workflow.md`.
|
| `bmad-shard-doc`, `bmad-index-docs`, `bmad-check-implementation-readiness`,
| `bmad-create-ux-design`, `bmad-distillator` et `bmad-simplify` ont disparu du
| disque : les taper ne fait RIEN. Douze autres sont devenues des redirections
| dépréciées. Aucun signal, aucune alerte — le document de process disait
| simplement quoi taper, et ce qu'il disait était devenu faux.
|
| C'est le motif dominant de ce dépôt (« l'affirmation précède son référent »),
| installé cette fois dans le document qui décrit COMMENT travailler. Le
| précédent est `BoostGuidelinesTest`, qui verrouille que tout import `@chemin`
| d'un fichier de consignes résout sur disque, après qu'un outil amont y eut
| injecté une consigne pointant vers un `.ai/rules` inexistant.
|
|------------------------------------------------------------------------------
| ⚠️ CE GARDE-FOU EST LOCAL, ET C'EST ÉCRIT PLUTÔT QUE SUBI
|------------------------------------------------------------------------------
|
| `.claude/skills/` est GITIGNORÉ (`.gitignore:229`) : les skills sont installées
| par machine par l'installeur BMad, jamais versionnées. La CI clone donc un
| dépôt qui n'en contient aucune.
|
| ⛔ Un test qui exigerait leur présence serait ROUGE EN CI pour une raison sans
| rapport avec ce qu'il mesure — exactement le défaut Q4 corrigé le même jour
| (un SHA figé qui rougissait sur un clone superficiel). On ne refait pas ce
| défaut en le déplaçant d'un fichier.
|
| Il se déclare donc `skipped` quand le répertoire est absent, avec un message
| qui dit pourquoi. C'est le bon compromis : la dérive naît sur le poste du
| développeur, à l'instant d'une mise à jour BMad, et c'est là que ce test
| tourne — à chaque `make test`.
|
|------------------------------------------------------------------------------
| ⛔ POURQUOI ON N'EXTRAIT QUE LES `/bmad-…` PRÉFIXÉS D'UNE BARRE
|------------------------------------------------------------------------------
|
| La barre oblique est la façon dont on INVOQUE une commande. Sans elle, on
| PARLE d'une commande. La distinction n'est pas cosmétique : elle écarte
| `_bmad-output/` (un chemin) sans liste d'exceptions à entretenir, et elle laisse
| les blocs historiques nommer les commandes retirées.
|
| ⚠️ La barre doit AUSSI ne pas être précédée d'une barre ou d'un caractère de
| mot : sans ce détail, `https://bmad-method.com` produisait `/bmad-method`, et le
| garde-fou accusait une URL de référence d'être une commande morte. Constaté à
| l'écriture, le 2026-08-20 — première exécution, premier faux positif. La parade
| est de corriger la VISÉE plutôt que le texte du document, leçon déjà payée ici
| par un grep qui rougissait sur son propre commentaire.
|
| Second filet : les blocs `<!-- bmad-referents:ignore -->`. Ils existent parce
| qu'un bandeau de migration DOIT nommer les commandes dépréciées pour expliquer
| la migration — et qu'un garde-fou qui rougit sur le commentaire expliquant son
| propre motif s'éteint en effaçant la seule trace de la décision. Ce piège a
| déjà été rencontré ici, avec un grep textuel, le 2026-08-20.
*/

/**
 * Les documents de process qui PRESCRIVENT des commandes.
 *
 * @var list<string>
 */
const PROCESS_DOCS = [
    'docs/process/02-bmad-workflow.md',
    'docs/process/03-boucle-qualite.md',
    // La reading room PRESCRIT elle aussi des commandes — sa carte « plafond »
    // nomme celles qui comptent dans le quota. Un document qui prescrit entre
    // dans ce garde-fou, quel que soit son format : l'extraction est textuelle
    // et les blocs `bmad-referents:ignore` sont déjà des commentaires HTML.
    'docs/reading-room/index.html',
];

/**
 * Retire les régions explicitement marquées comme historiques.
 */
function withoutHistoricalBlocks(string $markdown): string
{
    return (string) preg_replace(
        '/<!--\s*bmad-referents:ignore.*?<!--\s*\/bmad-referents:ignore\s*-->/s',
        '',
        $markdown,
    );
}

/**
 * Les commandes BMad qu'un document dit d'EXÉCUTER.
 *
 * @return list<string>
 */
function prescribedBmadCommands(string $relative): array
{
    preg_match_all(
        '#(?<![\w/])/(bmad-[a-z0-9-]+)#',
        withoutHistoricalBlocks(RepoFile::read($relative)),
        $matches,
    );

    /** @var list<string> $names */
    $names = array_values(array_unique($matches[1]));
    sort($names);

    return $names;
}

function installedSkillsDirectory(): string
{
    return RepoFile::root() . '/.claude/skills';
}

it('finds a meaningful number of prescribed commands to reason about', function (): void {
    /*
     * ⚠️ LE PRÉALABLE, ET IL N'EST PAS DÉCORATIF.
     *
     * Sans lui, une régression du motif d'extraction rendrait la liste vide, et
     * les deux tests suivants seraient verts en ne vérifiant RIEN. C'est la forme
     * exacte du garde-fou silencieux que ce fichier existe pour empêcher.
     *
     * Le seuil est bas et grossier À DESSEIN : il n'atteste pas d'un compte juste,
     * seulement que le parseur a bien un sujet.
     *
     * 📌 CE QU'IL NE GARDE PAS, ET POURQUOI C'EST SANS DANGER — vérifié par
     * mutation le 2026-08-20, pas déduit. Une première rédaction de ce commentaire
     * annonçait qu'il attraperait « une balise `ignore` mal fermée qui avalerait
     * tout le fichier ». C'ÉTAIT FAUX : le motif d'exclusion exige la balise
     * fermante, donc une balise ouverte et jamais refermée n'exclut RIEN — le
     * garde-fou devient plus strict, pas plus laxiste. La mutation correspondante
     * est restée verte, et c'est elle qui a corrigé le commentaire. Le déséquilibre
     * des balises est néanmoins vérifié ci-dessous : c'est une faute de rédaction
     * qui mérite d'être nommée, même quand elle échoue du bon côté.
     */
    foreach (PROCESS_DOCS as $doc) {
        expect(prescribedBmadCommands($doc))
            ->not->toBeEmpty("Aucune commande BMad extraite de {$doc} : l'extraction est cassée, ou une balise `bmad-referents:ignore` non refermée a avalé le document.");
    }

    expect(count(prescribedBmadCommands('docs/process/02-bmad-workflow.md')))
        ->toBeGreaterThan(20, 'Le document de workflow ne prescrit presque plus de commandes : l\'extraction ne voit plus ce qu\'elle devrait voir.');

    // Les blocs historiques doivent être refermés. Une balise orpheline ne casse
    // rien (l'exclusion n'a alors pas lieu), mais elle signale une intention non
    // exprimée : l'auteur croyait avoir mis quelque chose hors périmètre.
    foreach (PROCESS_DOCS as $doc) {
        $markdown = RepoFile::read($doc);

        expect(substr_count($markdown, '<!-- bmad-referents:ignore'))
            ->toBe(
                substr_count($markdown, '<!-- /bmad-referents:ignore'),
                "Balises `bmad-referents:ignore` déséquilibrées dans {$doc} : un bloc historique "
                    . "est ouvert et jamais refermé. L'exclusion n'a pas lieu — le garde-fou est plus "
                    . 'strict que prévu, pas plus laxiste — mais l\'intention est perdue.',
            );
    }
});

it('prescribes only BMad commands that exist on disk', function (): void {

    $skills = installedSkillsDirectory();

    $missing = [];

    foreach (PROCESS_DOCS as $doc) {
        foreach (prescribedBmadCommands($doc) as $command) {
            if (! is_dir($skills . '/' . $command)) {
                $missing[] = "{$doc} → /{$command}";
            }
        }
    }

    expect($missing)
        ->toBe(
            [],
            "Des documents de process prescrivent des commandes BMad qui N'EXISTENT PAS :\n  "
                . implode("\n  ", $missing)
                . "\nLes taper ne fait rien. Re-pointez-les, ou déplacez la mention dans un bloc "
                . '`<!-- bmad-referents:ignore -->` si elle est historique.',
        );
})->skip(
    // ⛔ JAMAIS un vert silencieux : Pest imprime la raison du skip à chaque exécution.
    //
    // ⚠️ `fn` et NON `static fn` : `TestCall::skip()` fait `$condition->bindTo(null)`,
    // qui rend `null` sur une closure statique — d'où un `call_user_func(): Argument
    // #1 must be a valid callback` parfaitement opaque. Constaté ici le 2026-08-20.
    fn (): bool => ! is_dir(installedSkillsDirectory()),
    'Skills BMad non installées ici (.claude/skills/ est gitignoré, donc absent de tout clone CI). '
    . 'Ce garde-fou ne tourne que sur un poste de développement — le seul endroit où la dérive naît.',
);

it('prescribes no BMad command that has been deprecated', function (): void {
    /*
     * Une commande dépréciée REDIRIGE encore : rien ne casse aujourd'hui, et
     * c'est précisément ce qui rend la dérive invisible. Le jour où la
     * redirection sautera, le document de process désignera du vide — et
     * personne ne saura depuis quand.
     *
     * BMad déclare la dépréciation dans la `description` du SKILL.md. C'est le
     * référent que l'outil lui-même consomme ; on lit celui-là, pas une liste
     * de noms tenue à la main qui dériverait à la mise à jour suivante.
     */
    $skills = installedSkillsDirectory();

    $skills = installedSkillsDirectory();
    $deprecated = [];

    foreach (PROCESS_DOCS as $doc) {
        foreach (prescribedBmadCommands($doc) as $command) {
            $manifest = $skills . '/' . $command . '/SKILL.md';

            if (! is_file($manifest)) {
                continue; // absence traitée par le test précédent
            }

            $description = '';

            foreach (explode("\n", (string) file_get_contents($manifest)) as $line) {
                if (str_starts_with($line, 'description:')) {
                    $description = $line;

                    break;
                }
            }

            if (stripos($description, 'deprecated') !== false) {
                $deprecated[] = "{$doc} → /{$command}";
            }
        }
    }

    expect($deprecated)
        ->toBe(
            [],
            "Des documents de process prescrivent des commandes BMad DÉPRÉCIÉES :\n  "
                . implode("\n  ", $deprecated)
                . "\nElles redirigent encore, donc rien ne casse — jusqu'au jour où la redirection "
                . 'disparaîtra. Re-pointez-les vers la commande vivante.',
        );
})->skip(
    fn (): bool => ! is_dir(installedSkillsDirectory()),
    'Skills BMad non installées ici (.claude/skills/ gitignoré) — voir le test précédent.',
);

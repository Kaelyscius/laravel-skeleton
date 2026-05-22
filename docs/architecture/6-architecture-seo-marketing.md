# 6. Architecture SEO & marketing

## 6.1 Structure URL Reviews

**Format** : `/reviews/{long-slug-éditorial}` — ex. `/reviews/elden-ring-2-mon-verdict`

Refus explicites :
- ❌ `/r/{slug}` — wedge "Press Office" prématuré
- ❌ `/{year}/{month}/{slug}` — tue evergreen

Slug : généré au publish via `Str::slug($title)`, max 180 chars, unique global.

## 6.2 Format article

| Élément | Spec |
|---|---|
| Longueur | 1200 mots cible (plancher 800, plafond 2000) |
| YouTube embed | **Petit**, pas full-width above-the-fold |
| Timecodes | Inline cliquables `[00:42]` → `https://youtu.be/{id}?t=42` |
| Compteur vues | Page détail uniquement, seuil min 100 vues (pas en index — anti-vanity Ponce) |
| Cover | 16:9, `webp` optimisé, lazy-loaded |
| Métadonnées | `<title>` + `<meta description>` + Open Graph + Twitter Card + Schema.org `Review`+`VideoGame` |

## 6.3 Stratégie contenu (LOCKED Mary+John)

- **Mix** : 70% reviews longues / 30% news+previews
- **Cadence** : steady 3 articles/mois (pas de sprints — algo Google + Twitch UTM)
- **Capital M0** : 3 articles publiés jour 1 (sweet spot signal éditorial vivant)

## 6.4 OG images dynamiques pré-générées (wedge CRITICAL S4)

**Génération** : au moment du `publish` via job dispatché → `public/og/{slug}.png`.

```php
class GenerateOgImage implements ShouldQueue
{
    public function __construct(public Article $article) {}

    public function handle(): void
    {
        $template = $this->resolveTemplate($this->article);
        $png = Browsershot::html(view("og.{$template}", ['article' => $this->article]))
            ->windowSize(1200, 630)
            ->screenshot();
        Storage::disk('public_og')->put($this->article->slug.'.png', $png);
    }

    private function resolveTemplate(Article $a): string
    {
        if ($a->type !== 'review' || $a->note === null) {
            return 'news'; // news + preview = template neutre sans note
        }
        return match (true) {
            $a->note >= 9 => 'review-stellar',
            $a->note >= 7 => 'review-solid',
            default       => 'review-light',
        };
    }
}
```

**Pas** de génération à la volée (+800ms TTFB tue le partage social).

### 6.4.1 Trois variantes (décision OQ5 PRD 2026-05-22)

Décision PRD : **3 variantes Blade dédiées** plutôt qu'un template unique avec note dynamique. Trade-off accepté : maintenance 3× pour expression visuelle différenciée par tier de note. Une 4ᵉ variante neutre pour news/preview (sans note).

| Template Blade | Cible | Caractéristiques |
|---|---|---|
| `og/review-stellar.blade.php` | Reviews note ≥ 9 | Barre Lava bottom + accent visuel fort + note 180px Lava `#FF5722` |
| `og/review-solid.blade.php` | Reviews note 7-8 | Pas de barre Lava, note 180px texte primaire `rgba(255,255,255,.92)`, accent état succès `#22C55E` discret |
| `og/review-light.blade.php` | Reviews note ≤ 6 | Note 180px texte secondaire `rgba(255,255,255,.60)`, pas d'accent (ton sobre, honnête) |
| `og/news.blade.php` | News + preview (`type ≠ review`) | Pas de note, titre 100% surface, badge `NEWS` ou `PREVIEW` Lava bottom-left |

### 6.4.2 Composition commune aux 4 variantes

- Background `#0A0A0B` flat (pas de gradient — anti-pattern Caravaggio)
- Cover game (left 40% si reviews, full-width discret si news)
- Logo discret bottom-right
- Format unique : 1200×630 (pas 1200×1200 Insta — faux besoin)
- Typo : IBM Plex Sans (titre) + IBM Plex Mono (métadonnées)

### 6.4.3 Tests OG par variante

- Test Pest dispatché par variante : `OgImageVariantTest::test_stellar_template_renders_lava_bar()`, etc.
- Snapshot visuel via PixelMatch (3 PNG de référence en `tests/fixtures/og/`) — détecte régressions visuelles non intentionnelles

## 6.5 Press Kit `/press`

**Hiérarchie** : Stats live > Photo > Bio.

**Stats affichées** :
- Viewers concurrents moyens P50 (médiane, pas mean — honnêteté Ponce)
- Heures streamées total
- Nombre de vidéos YouTube
- ❌ **Pas** followers Twitch (vanity, gameable)

**Bio** : FR + EN bilingue v1 (signal international, cohérent README EN).

**Téléchargements** : choix multiple individuel (SVG / PNG / kit complet) — **pas de zip global** (un dev sérieux veut le SVG seul).

## 6.6 Tracking UTM

- Auto-génération UTM sur bouton "copier le lien" (JTBD n°3 dev gifting) — S5, ~1h dev
- Checklist stream-side obligatoire (panel Twitch + `!commande` + lower-third) — documentée dans `docs/process/stream-discipline.md`

---

/* ═══════════════════════════════════════════════════════════════════════════
   Reading Room — comportements partagés.

   Aucune dépendance. Le fichier s'exécute au chargement de n'importe laquelle
   des huit pages et n'active que ce qu'il trouve dans le DOM.

   Trois familles :
     1. Chrome     — navigation courante, accordéons, onglets, provenances.
     2. Plan       — rendu des 11 epics / 131 stories depuis `data/plan.js`.
     3. Exigences  — rendu des 333 exigences, avec recherche et filtres.
   ═══════════════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  const $ = (sel, root) => (root || document).querySelector(sel);
  const $$ = (sel, root) => Array.from((root || document).querySelectorAll(sel));

  const STATUS = {
    done:          { label: 'livré',       cls: 'ok',   dot: 'd-ok' },
    review:        { label: 'en revue',    cls: 'info', dot: 'd-info' },
    'in-progress': { label: 'en cours',    cls: 'now',  dot: 'd-now' },
    'ready-for-dev': { label: 'prête',     cls: 'warn', dot: 'd-warn' },
    backlog:       { label: 'à faire',     cls: '',     dot: 'd-idle' },
    optional:      { label: 'optionnel',   cls: '',     dot: 'd-idle' },
  };
  const st = (k) => STATUS[k] || STATUS.backlog;

  /* ── 1. Chrome ─────────────────────────────────────────────────────────── */

  /** Marque l'entrée de nav correspondant au fichier courant. */
  function markCurrentPage() {
    const here = (location.pathname.split('/').pop() || 'index.html');
    $$('nav.top .links a').forEach((a) => {
      const target = a.getAttribute('href').split('#')[0];
      if (target === here) { a.setAttribute('aria-current', 'page'); }
    });
  }

  /**
   * Accordéon générique : un bouton `aria-expanded` suivi d'un `.body`.
   * La hauteur est animée par `max-height`, donc bornée par la CSS — d'où le
   * recalcul explicite pour les contenus longs (une story porte jusqu'à 12 AC).
   */
  function wireDisclosures(root) {
    $$('[data-toggle]', root || document).forEach((btn) => {
      if (btn.dataset.wired) { return; }
      btn.dataset.wired = '1';
      btn.addEventListener('click', () => {
        const panel = btn.parentElement.querySelector('.body');
        const open = btn.getAttribute('aria-expanded') === 'true';
        btn.setAttribute('aria-expanded', String(!open));
        if (!panel) { return; }
        panel.classList.toggle('open', !open);
        panel.style.maxHeight = open ? '' : panel.scrollHeight + 40 + 'px';
      });
    });
  }

  /** Compteurs de tableau de bord : chacun révèle sa provenance. */
  function wireProvenance() {
    $$('.metric[data-prov]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const panel = document.getElementById(btn.dataset.prov);
        const open = btn.getAttribute('aria-expanded') === 'true';
        $$('.metric[data-prov]').forEach((o) => {
          if (o !== btn) { o.setAttribute('aria-expanded', 'false'); }
        });
        $$('.prov').forEach((p) => { if (p !== panel) { p.classList.remove('open'); } });
        btn.setAttribute('aria-expanded', String(!open));
        if (panel) { panel.classList.toggle('open', !open); }
      });
    });
  }

  function wireTabs() {
    $$('[role="tablist"]').forEach((list) => {
      const tabs = $$('[role="tab"]', list);
      tabs.forEach((tab) => {
        tab.addEventListener('click', () => {
          tabs.forEach((t) => {
            const on = t === tab;
            t.setAttribute('aria-selected', String(on));
            const pane = document.getElementById(t.getAttribute('aria-controls'));
            if (pane) { pane.hidden = !on; }
          });
        });
        tab.addEventListener('keydown', (e) => {
          const i = tabs.indexOf(tab);
          if (e.key === 'ArrowRight') { tabs[(i + 1) % tabs.length].focus(); }
          if (e.key === 'ArrowLeft') { tabs[(i - 1 + tabs.length) % tabs.length].focus(); }
        });
      });
    });
  }

  /* ── Outils de recherche ───────────────────────────────────────────────── */

  const strip = (s) => String(s)
    .replace(/<[^>]*>/g, ' ')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '') // « sécurité » se cherche « securite »
    .toLowerCase();

  /** Surligne les occurrences dans du HTML déjà rendu, sans casser les balises. */
  function highlight(html, needle) {
    if (!needle) { return html; }
    const parts = html.split(/(<[^>]*>)/);
    const rx = new RegExp('(' + needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + ')', 'gi');
    return parts.map((p) => (p.startsWith('<') ? p : p.replace(rx, '<mark>$1</mark>'))).join('');
  }

  /** Débounce court : la frappe reste fluide sur 131 stories rendues. */
  function debounce(fn, ms) {
    let t;
    return function () {
      clearTimeout(t);
      const args = arguments;
      t = setTimeout(() => fn.apply(null, args), ms || 120);
    };
  }

  /* ── 2. Plan : epics et stories ────────────────────────────────────────── */

  function renderPlan(mount, plan) {
    const state = { q: '', epic: 'all', status: 'all' };

    const epicFilters = $('#f-epic');
    const statusFilters = $('#f-status');
    const input = $('#q');
    const tally = $('#tally');

    if (epicFilters) {
      epicFilters.innerHTML =
        '<button class="fbtn" aria-pressed="true" data-epic="all">Tous <span class="cnt">' +
        plan.counts.stories + '</span></button>' +
        plan.epics.map((e) =>
          '<button class="fbtn" aria-pressed="false" data-epic="' + e.num + '">E' + e.num +
          ' <span class="cnt">' + e.stories.length + '</span></button>').join('');
    }
    if (statusFilters) {
      const tallies = {};
      plan.epics.forEach((e) => e.stories.forEach((s) => {
        tallies[s.status] = (tallies[s.status] || 0) + 1;
      }));
      statusFilters.innerHTML =
        '<button class="fbtn" aria-pressed="true" data-status="all">Tous statuts</button>' +
        Object.keys(tallies).sort().map((k) =>
          '<button class="fbtn" aria-pressed="false" data-status="' + k + '">' +
          '<span class="dot ' + st(k).dot + '"></span>' + st(k).label +
          ' <span class="cnt">' + tallies[k] + '</span></button>').join('');
    }

    function storyHtml(s, q) {
      const info = st(s.status);
      const acHtml = s.ac.map((a) =>
        '<li><span class="kw kw-' + a.kw + '">' + a.kw + '</span>' +
        '<span class="txt">' + highlight(a.text, q) + '</span></li>').join('');
      const notes = s.notes.length
        ? '<div class="note warn" style="margin-top:14px">' +
          s.notes.map((n) => '<p>' + n + '</p>').join('') + '</div>'
        : '';
      return '' +
        '<article class="story" data-epic="' + s.epic + '" data-status="' + s.status +
        '" data-hay="' + strip(s.id + ' ' + s.title + ' ' + s.role + ' ' + s.want + ' ' +
          s.benefit + ' ' + s.ac.map((a) => a.text).join(' ')) + '">' +
        '<button data-toggle aria-expanded="false">' +
        '<span class="dot ' + info.dot + ' sdot"></span>' +
        '<span class="sid">' + s.id + '</span>' +
        '<span class="st">' + highlight(s.title, q) +
        '<span class="role">' + s.role + ' · ' + s.ac.length + ' critère' +
        (s.ac.length > 1 ? 's' : '') + " d'acceptation</span></span>" +
        '<span class="chip ' + info.cls + '">' + info.label + '</span>' +
        '<span class="chev">›</span></button>' +
        '<div class="body"><div class="in">' +
        '<div class="narrative">' +
        '<div><span class="k">En tant que</span> ' + s.role + '</div>' +
        '<div><span class="k">je veux</span> ' + highlight(s.want, q) + '</div>' +
        '<div><span class="k">afin que</span> ' + highlight(s.benefit, q) + '</div>' +
        '</div>' +
        '<h4 class="min" style="margin:0 0 8px">Critères d\'acceptation</h4>' +
        '<ul class="ac">' + acHtml + '</ul>' + notes +
        '</div></div></article>';
    }

    function epicHtml(e, q) {
      const done = e.stories.filter((s) => s.status === 'done').length;
      const moving = e.stories.filter((s) => s.status === 'review' ||
        s.status === 'in-progress').length;
      const pct = Math.round((done / e.stories.length) * 100);
      const info = st(e.status);
      const meta = Object.keys(e.meta).map((k) =>
        '<div><span class="k">' + k + '</span> ' + e.meta[k] + '</div>').join('');
      return '' +
        '<section class="epic" id="epic-' + e.num + '" data-epic="' + e.num + '">' +
        '<header>' +
        '<span class="num">' + e.num + '</span>' +
        '<div class="hd">' +
        '<h3>' + highlight(e.title, q) + '</h3>' +
        '<div style="display:flex;gap:6px;flex-wrap:wrap">' +
        '<span class="chip ' + info.cls + '">' + info.label + '</span>' +
        (e.phase ? '<span class="chip">' + e.phase + '</span>' : '') +
        (e.effort ? '<span class="chip">' + e.effort + '</span>' : '') +
        '<span class="chip">' + e.stories.length + ' stories</span>' +
        '</div>' +
        '<p class="pitch">' + highlight(e.pitch, q) + '</p>' +
        (meta ? '<div class="narrative" style="margin-top:12px;font-size:12.5px">' +
          meta + '</div>' : '') +
        '</div>' +
        '<div class="side"><div class="prog">' +
        '<div class="track"><i class="' + (pct === 100 ? 'fill-ok' : 'fill-done') +
        '" style="width:' + pct + '%"></i>' +
        '<i class="fill-now" style="width:' +
        Math.round((moving / e.stories.length) * 100) + '%"></i></div>' +
        '<div class="cap">' + done + ' / ' + e.stories.length + ' livrées</div>' +
        '</div></div>' +
        '</header>' +
        e.stories.map((s) => storyHtml(s, q)).join('') +
        '</section>';
    }

    function paint() {
      const q = strip(state.q);
      mount.innerHTML = plan.epics
        .filter((e) => state.epic === 'all' || String(e.num) === state.epic)
        .map((e) => epicHtml(e, state.q))
        .join('');

      let shown = 0;
      $$('.story', mount).forEach((el) => {
        const okStatus = state.status === 'all' || el.dataset.status === state.status;
        const okQuery = !q || el.dataset.hay.indexOf(q) !== -1;
        const on = okStatus && okQuery;
        el.hidden = !on;
        if (on) { shown += 1; }
      });
      $$('.epic', mount).forEach((el) => {
        el.hidden = $$('.story:not([hidden])', el).length === 0;
      });
      if (tally) {
        tally.textContent = shown + ' / ' + plan.counts.stories + ' stories';
      }
      if (!shown) {
        mount.innerHTML = '<p class="empty">Aucune story ne correspond. ' +
          'Essayez un autre terme, ou relâchez un filtre.</p>';
      }
      wireDisclosures(mount);
      // Une recherche active déplie ce qu'elle a trouvé : sinon le terme
      // surligné reste invisible dans un accordéon fermé.
      if (q) {
        $$('.story:not([hidden])', mount).slice(0, 40).forEach((el) => {
          const btn = $('[data-toggle]', el);
          const panel = $('.body', el);
          btn.setAttribute('aria-expanded', 'true');
          panel.classList.add('open');
          panel.style.maxHeight = panel.scrollHeight + 40 + 'px';
        });
      }
    }

    if (input) {
      input.addEventListener('input', debounce(() => {
        state.q = input.value.trim();
        paint();
      }, 140));
    }
    const clear = $('.search .clear');
    if (clear) {
      clear.addEventListener('click', () => {
        input.value = ''; state.q = ''; paint(); input.focus();
      });
    }
    if (epicFilters) {
      epicFilters.addEventListener('click', (e) => {
        const b = e.target.closest('[data-epic]');
        if (!b) { return; }
        state.epic = b.dataset.epic;
        $$('[data-epic]', epicFilters).forEach((o) =>
          o.setAttribute('aria-pressed', String(o === b)));
        paint();
      });
    }
    if (statusFilters) {
      statusFilters.addEventListener('click', (e) => {
        const b = e.target.closest('[data-status]');
        if (!b) { return; }
        state.status = b.dataset.status;
        $$('[data-status]', statusFilters).forEach((o) =>
          o.setAttribute('aria-pressed', String(o === b)));
        paint();
      });
    }

    // Lien profond vers un epic. Deux formes acceptées, et ce n'est pas une
    // redondance : `#epic-5` est une ancre PRODUITE AU RENDU — donc invérifiable
    // par un garde-fou statique —, tandis que `?epic=5` est une cible que rien
    // ne peut casser en silence. Les renvois inter-pages emploient la seconde ;
    // la première reste comprise pour les liens déjà partagés.
    const wanted = (location.search.match(/[?&]epic=(\d+)/) ||
                    location.hash.match(/^#epic-(\d+)$/) || [])[1];
    if (wanted && epicFilters) {
      const b = $('[data-epic="' + wanted + '"]', epicFilters);
      if (b) { b.click(); }
    }
    paint();
  }

  /* ── 3. Exigences ──────────────────────────────────────────────────────── */

  function renderRequirements(mount, plan) {
    const state = { q: '', family: 'all' };
    const input = $('#rq');
    const fam = $('#f-family');
    const tally = $('#rtally');

    if (fam) {
      const counts = {};
      plan.requirements.forEach((r) => { counts[r.family] = (counts[r.family] || 0) + 1; });
      fam.innerHTML =
        '<button class="fbtn" aria-pressed="true" data-family="all">Toutes ' +
        '<span class="cnt">' + plan.requirements.length + '</span></button>' +
        ['FR', 'NFR', 'AR', 'UX-DR'].filter((k) => counts[k]).map((k) =>
          '<button class="fbtn" aria-pressed="false" data-family="' + k + '">' +
          (plan.families[k] ? plan.families[k].label : k) +
          ' <span class="cnt">' + counts[k] + '</span></button>').join('');
    }

    function paint() {
      const q = strip(state.q);
      const rows = plan.requirements.filter((r) =>
        (state.family === 'all' || r.family === state.family) &&
        (!q || strip(r.code + ' ' + r.group + ' ' + r.text).indexOf(q) !== -1));

      if (!rows.length) {
        mount.innerHTML = '<p class="empty">Aucune exigence ne correspond.</p>';
      } else {
        // Regroupées par famille puis par domaine : c'est l'ordre du document
        // source, et il porte du sens (les modules d'abord, les gates après).
        let html = '';
        let lastGroup = null;
        rows.forEach((r) => {
          const key = r.family + ' — ' + r.group;
          if (key !== lastGroup) {
            if (lastGroup !== null) { html += '</div>'; }
            html += '<h4 class="min">' + key + '</h4><div class="reqs">';
            lastGroup = key;
          }
          html += '<div class="req"><span class="code">' +
            highlight(r.code, state.q) + '</span><span class="meat">' +
            highlight(r.text, state.q) + '</span></div>';
        });
        html += '</div>';
        mount.innerHTML = html;
      }
      if (tally) {
        tally.textContent = rows.length + ' / ' + plan.requirements.length + ' exigences';
      }
    }

    if (input) {
      input.addEventListener('input', debounce(() => {
        state.q = input.value.trim(); paint();
      }, 140));
    }
    const clear = $('.search .clear');
    if (clear) {
      clear.addEventListener('click', () => {
        input.value = ''; state.q = ''; paint(); input.focus();
      });
    }
    if (fam) {
      fam.addEventListener('click', (e) => {
        const b = e.target.closest('[data-family]');
        if (!b) { return; }
        state.family = b.dataset.family;
        $$('[data-family]', fam).forEach((o) =>
          o.setAttribute('aria-pressed', String(o === b)));
        paint();
      });
    }
    paint();
  }

  /* ── Amorçage ──────────────────────────────────────────────────────────── */

  function boot() {
    markCurrentPage();
    wireDisclosures(document);
    wireProvenance();
    wireTabs();

    const plan = window.RR_PLAN;

    // Le tampon de fraîcheur est écrit par le générateur, pas à la main : une
    // date saisie à la main est la première chose qui ment dans un document.
    $$('[data-plan-stamp]').forEach((el) => {
      if (!plan) { el.textContent = '— données absentes'; return; }
      el.textContent = plan.generated + ' · ' + plan.commit +
        (plan.dirty ? ' · arbre modifié' : '');
    });
    $$('[data-plan-count]').forEach((el) => {
      if (plan && plan.counts[el.dataset.planCount] !== undefined) {
        el.textContent = plan.counts[el.dataset.planCount];
      }
    });

    const planMount = $('#plan');
    if (planMount) {
      if (plan) { renderPlan(planMount, plan); }
      else {
        planMount.innerHTML = '<p class="empty">' +
          '<b>data/plan.js est absent.</b><br>Régénérez-le : ' +
          '<code>python3 docs/reading-room/tools/build-plan.py</code></p>';
      }
    }

    const reqMount = $('#reqs');
    if (reqMount) {
      if (plan) { renderRequirements(reqMount, plan); }
      else {
        reqMount.innerHTML = '<p class="empty"><b>data/plan.js est absent.</b></p>';
      }
    }

    // `/` met le focus dans la recherche — raccourci attendu sur une page de
    // catalogue, et sans effet quand on est déjà en train de saisir.
    document.addEventListener('keydown', (e) => {
      if (e.key !== '/' || e.metaKey || e.ctrlKey) { return; }
      const tag = (document.activeElement.tagName || '').toLowerCase();
      if (tag === 'input' || tag === 'textarea') { return; }
      const box = $('.search input');
      if (box) { e.preventDefault(); box.focus(); box.select(); }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();

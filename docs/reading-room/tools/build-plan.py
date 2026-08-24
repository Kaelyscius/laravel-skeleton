#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Générateur du jeu de données de la reading room.

────────────────────────────────────────────────────────────────────────────────
POURQUOI CE SCRIPT EXISTE

La reading room décrit 11 epics, 131 stories et ~180 exigences. Les transcrire à
la main dans du HTML, c'est fabriquer une deuxième source de vérité qui dérivera
de la première — le motif dominant de ce dépôt (« l'affirmation précède son
référent »), appliqué cette fois à un document de 3 400 lignes.

Ce script LIT les sources d'autorité et PRODUIT `docs/reading-room/data/plan.js`.
Les pages HTML n'écrivent aucun titre de story, aucun critère d'acceptation,
aucun statut : elles rendent ce fichier.

    Sources (autorité décroissante) :
      _bmad-output/planning-artifacts/epics.md          ← epics, stories, AC, exigences
      _bmad-output/implementation-artifacts/sprint-status.yaml  ← statuts réels

⚠️ `_bmad-output/` est GITIGNORÉ. C'est précisément pourquoi le rendu est figé
dans un fichier versionné : sans ça, la reading room serait vide sur un clone.
Le prix est explicite — `plan.js` est un instantané daté, et la page le dit.

    Régénérer :  make reading-room     (ou : python3 docs/reading-room/tools/build-plan.py)
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
EPICS = ROOT / "_bmad-output/planning-artifacts/epics.md"
STATUS = ROOT / "_bmad-output/implementation-artifacts/sprint-status.yaml"
OUT = ROOT / "docs/reading-room/data/plan.js"


# ── Utilitaires ───────────────────────────────────────────────────────────────

def die(msg: str) -> None:
    """Échoue bruyamment. Un générateur qui produit un fichier vide en silence
    est exactement le garde-fou silencieux que ce dépôt traque."""
    print(f"✖ {msg}", file=sys.stderr)
    sys.exit(1)


def read(path: Path) -> str:
    if not path.is_file():
        die(f"source absente : {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def inline_md(text: str) -> str:
    """Convertit le Markdown *inline* en HTML. Volontairement minimal : gras,
    italique, code, liens. Tout le reste est échappé."""
    text = (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"<a href=\"\2\">\1</a>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"(?<![*\w])\*([^*\n]+)\*(?!\*)", r"<i>\1</i>", text)
    return text


# ── Statuts (sprint-status.yaml) ──────────────────────────────────────────────

def parse_status() -> dict[str, str]:
    """Extrait `clé: statut` du bloc `development_status:`.

    Le fichier porte des commentaires de plusieurs dizaines de lignes entre les
    clés ; on ne fait donc AUCUNE hypothèse de contiguïté — on prend toute ligne
    indentée qui ressemble à `clé: valeur` et dont la valeur est un statut connu.
    """
    known = {"backlog", "ready-for-dev", "in-progress", "review", "done", "optional"}
    out: dict[str, str] = {}
    for line in read(STATUS).splitlines():
        m = re.match(r"^\s{2,}([a-z0-9][a-z0-9._-]*):\s*([a-z-]+)\s*(#.*)?$", line)
        if m and m.group(2) in known:
            out[m.group(1)] = m.group(2)
    if len(out) < 100:
        die(f"sprint-status.yaml : {len(out)} statuts lus, attendu > 100 — extraction cassée")
    return out


def story_status(statuses: dict[str, str], epic: int, num: str) -> str:
    """Retrouve le statut d'une story par son préfixe `<epic>-<num>-`.

    Les clés du YAML sont des slugs (`1-10a-install-filament-v5-…`) tandis que
    les titres d'epics.md portent un numéro (`1.10`). On matche sur le préfixe,
    en acceptant un suffixe de lettre (1.10 → 1-10a).
    """
    base = f"{epic}-{num}"
    for key, val in statuses.items():
        if key == base or key.startswith(base + "-"):
            return val
    for key, val in statuses.items():
        if re.match(rf"^{re.escape(base)}[a-z]-", key):
            return val
    return "backlog"


# ── Exigences (FR / NFR / AR / UX-DR) ─────────────────────────────────────────

FAMILIES = {
    "FR": ("Fonctionnelles", "Ce que le produit doit faire."),
    "NFR": ("Non fonctionnelles", "Performance, sécurité, qualité, accessibilité, métriques."),
    "AR": ("Additionnelles", "Contraintes venues de l'architecture et des ADR."),
    "UX-DR": ("Design & UX", "Composants, tokens, patterns, accessibilité."),
}


def parse_requirements(md: str) -> list[dict]:
    """Chaque exigence est une puce `- **CODE** : texte`, sous un intertitre gras
    qui donne son groupe (`**Module Live (…)**`)."""
    reqs: list[dict] = []
    group = ""
    for line in md.splitlines():
        g = re.match(r"^\*\*(.+?)\*\*\s*$", line.strip())
        if g:
            group = re.sub(r"\s*\(.*?\)\s*$", "", g.group(1)).strip()
            continue
        # ⚠️ Deux formes coexistent : `FR-Public-1` (famille-domaine-n°) et
        # `UX-DR-1` (famille-n°, sans domaine). Un motif qui exige le segment du
        # milieu perd SILENCIEUSEMENT les 65 UX-DR — vu lors du premier jet.
        m = re.match(r"^-\s+\*\*(UX-DR-\d+|(?:FR|NFR|AR)-[A-Za-z0-9]+-\d+)\*\*\s*[:：]\s*(.+)$", line)
        if not m:
            continue
        code = m.group(1)
        family = "UX-DR" if code.startswith("UX-DR") else code.split("-")[0]
        reqs.append({
            "code": code,
            "family": family,
            "group": group,
            "text": inline_md(m.group(2).strip()),
        })
    if len(reqs) < 150:
        die(f"{len(reqs)} exigences extraites, attendu > 150 — le format des puces a changé")
    return reqs


# ── Résumés d'epics (section « Epic List ») ───────────────────────────────────

def parse_epic_summaries(md: str) -> dict[int, dict]:
    """La section `## Epic List` porte, pour chaque epic, un pitch d'une phrase et
    les listes FR/NFR couvertes. C'est la meilleure description courte du dépôt."""
    # ⚠️ Le séparateur porte son saut de ligne : sans lui, `## Epic 1:` matche
    # AUSSI `### Epic 1:` (dont il est un suffixe) et le bloc ressort vide.
    block = md.split("## Epic List", 1)[1].split("\n## Epic 1:", 1)[0]
    out: dict[int, dict] = {}
    chunks = re.split(r"^### Epic (\d+): ", block, flags=re.M)[1:]
    for i in range(0, len(chunks), 2):
        num = int(chunks[i])
        body = chunks[i + 1]
        title_line, _, rest = body.partition("\n")
        phase = ""
        pm = re.search(r"\(([^()]*(?:Phase|S-?\d)[^()]*)\)\s*$", title_line.strip())
        if pm:
            phase = pm.group(1).strip()
        title = re.sub(r"\s*\([^()]*(?:Phase|S-?\d)[^()]*\)\s*$", "", title_line).strip()
        paras = [p.strip() for p in rest.split("\n\n") if p.strip()]
        pitch = ""
        for p in paras:
            if not p.startswith(("**FRs", "**NFRs", "**ARs", "**UX-DRs", "**Amendements", "---", "**Critère")):
                pitch = p
                break
        meta: dict[str, str] = {}
        for label in ("FRs covered", "NFRs critical", "ARs", "UX-DRs", "Critère go"):
            mm = re.search(rf"\*\*{re.escape(label)}[^*]*\*\*\s*[:：]?\s*(.+)", rest)
            if mm:
                meta[label] = inline_md(mm.group(1).strip())
        amendments = re.findall(r"^-\s+[✅➡️]+\s*(.+)$", rest, flags=re.M)
        out[num] = {
            "title": re.sub(r"[*_]", "", title),
            "phase": phase,
            "pitch": inline_md(re.sub(r"\s+", " ", pitch)),
            "meta": meta,
            "amendments": [inline_md(a.strip()) for a in amendments],
        }
    if len(out) != 11:
        die(f"{len(out)} epics résumés, attendu 11")
    return out


# ── Budget ────────────────────────────────────────────────────────────────────

def parse_budget(md: str) -> dict[int, str]:
    out: dict[int, str] = {}
    block = md.split("### Budget recomposé post-amendements", 1)
    if len(block) < 2:
        return out
    for line in block[1].splitlines():
        m = re.match(r"^\|\s*(\d+)\s+[^|]*\|\s*([^|]+?)\s*\|", line)
        if m:
            out[int(m.group(1))] = m.group(2).strip()
    return out


# ── Stories ───────────────────────────────────────────────────────────────────

def parse_stories(md: str, statuses: dict[str, str]) -> dict[int, list[dict]]:
    """Découpe les sections `## Epic N:` détaillées, puis chaque `### Story N.M:`.

    Une story porte : un rôle (`As **X**`), une intention (`I want`), un bénéfice
    (`So that`), puis des critères d'acceptation en Given/When/Then/And, puis
    éventuellement des notes ou des amendements en citation.
    """
    epics: dict[int, list[dict]] = {}
    detail = md.split("\n## Epic 1: Foundations", 1)
    if len(detail) < 2:
        die("section détaillée des epics introuvable")
    body = "## Epic 1: Foundations" + detail[1]

    epic_chunks = re.split(r"^## Epic (\d+): ", body, flags=re.M)[1:]
    for i in range(0, len(epic_chunks), 2):
        num = int(epic_chunks[i])
        chunk = epic_chunks[i + 1]
        stories: list[dict] = []
        parts = re.split(r"^### Story ([0-9]+\.[0-9]+[a-z]?): ", chunk, flags=re.M)[1:]
        for j in range(0, len(parts), 2):
            ident = parts[j]
            raw = parts[j + 1]
            title, _, rest = raw.partition("\n")
            sub = ident.split(".", 1)[1]

            role = want = benefit = ""
            # ⚠️ Ancrer sur la fin de ligne perdait 17 stories : `As **Alex** (compliance
            # RGPD),` porte du texte APRÈS le gras. On capture le gras, puis la
            # parenthèse de qualification quand elle suit.
            rm = re.search(r"^As \*\*(.+?)\*\*\s*(\([^)]*\))?", rest, flags=re.M)
            wm = re.search(r"^I want \*\*(.+?)\*\*\s*,?\s*$", rest, flags=re.M | re.S)
            bm = re.search(r"^So that \*\*(.+?)\*\*\.?\s*$", rest, flags=re.M | re.S)
            if rm:
                role = (rm.group(1) + " " + (rm.group(2) or "")).strip()
            if wm:
                want = inline_md(re.sub(r"\s+", " ", wm.group(1).strip()))
            if bm:
                benefit = inline_md(re.sub(r"\s+", " ", bm.group(1).strip()))

            ac: list[dict] = []
            notes: list[str] = []
            after = rest.split("**Acceptance Criteria:**", 1)
            if len(after) == 2:
                for line in after[1].splitlines():
                    s = line.strip()
                    if not s:
                        continue
                    km = re.match(r"^\*\*(Given|When|Then|And|But)\*\*\s*(.*)$", s)
                    if km:
                        ac.append({"kw": km.group(1), "text": inline_md(km.group(2).strip())})
                    elif s.startswith(">") or s.startswith("**Note"):
                        notes.append(inline_md(s.lstrip("> ").strip()))
            stories.append({
                "id": ident,
                "epic": num,
                "title": inline_md(title.strip()),
                "role": role,
                "want": want,
                "benefit": benefit,
                "ac": ac,
                "notes": notes,
                "status": story_status(statuses, num, sub),
            })
        epics[num] = stories
    total = sum(len(v) for v in epics.values())
    if total < 120:
        die(f"{total} stories extraites, attendu ~131 — le format des titres a changé")
    return epics


# ── Assemblage ────────────────────────────────────────────────────────────────

def git(*args: str) -> str:
    try:
        return subprocess.run(["git", *args], cwd=ROOT, capture_output=True,
                              text=True, check=True).stdout.strip()
    except Exception:
        return "?"


def main() -> None:
    md = read(EPICS)
    statuses = parse_status()
    summaries = parse_epic_summaries(md)
    budget = parse_budget(md)
    stories = parse_stories(md, statuses)
    reqs = parse_requirements(md)

    epics = []
    for num in sorted(summaries):
        s = summaries[num]
        st = stories.get(num, [])
        epics.append({
            "num": num,
            "title": s["title"],
            "phase": s["phase"],
            "pitch": s["pitch"],
            "meta": s["meta"],
            "amendments": s["amendments"],
            "effort": budget.get(num, ""),
            "status": statuses.get(f"epic-{num}", "backlog"),
            "retro": statuses.get(f"epic-{num}-retrospective", "optional"),
            "stories": st,
        })

    payload = {
        "generated": date.today().isoformat(),
        "commit": git("rev-parse", "--short", "HEAD"),
        "branch": git("rev-parse", "--abbrev-ref", "HEAD"),
        "dirty": git("status", "--porcelain") != "",
        "counts": {
            "epics": len(epics),
            "stories": sum(len(e["stories"]) for e in epics),
            "done": sum(1 for e in epics for s in e["stories"] if s["status"] == "done"),
            "requirements": len(reqs),
        },
        "families": {k: {"label": v[0], "hint": v[1]} for k, v in FAMILIES.items()},
        "epics": epics,
        "requirements": reqs,
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        "/* GÉNÉRÉ — ne pas éditer à la main.\n"
        "   Source : _bmad-output/planning-artifacts/epics.md + sprint-status.yaml\n"
        "   Regénérer : make reading-room */\n"
        "window.RR_PLAN = " + json.dumps(payload, ensure_ascii=False, indent=1) + ";\n",
        encoding="utf-8",
    )
    c = payload["counts"]
    print(f"✔ {OUT.relative_to(ROOT)} — {c['epics']} epics · {c['stories']} stories "
          f"({c['done']} done) · {c['requirements']} exigences")


if __name__ == "__main__":
    main()

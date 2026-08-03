#!/usr/bin/env python3
"""Valide les workflows GitHub : YAML lisible, et shell des blocs `run` correct.

## Pourquoi ce script existe

`content.yml` ne se déclenchait que sur `content/**`, `tools/**` et les POI.
Modifier un workflow, ou un fichier de `.claude/agents/`, passait donc **sans
aucune CI** — et ces fichiers ne sont vérifiés par rien d'autre.

Le 2026-08-03, trois workflows ont été écrits ou refondus (`recolte.yml`,
`migrations.yml`, `content.yml`) et validés à la main : YAML puis `bash -n` sur
chaque bloc `run`. « À la main » n'est pas une garantie ; c'est ce script qui
l'est.

Ce qu'il attrape, concrètement : une indentation YAML fautive, un heredoc dont le
terminateur s'est décalé, une accolade non fermée dans un bloc `run` — trois
choses qui ne se voient qu'à l'exécution, c'est-à-dire au prochain cron.

Ce qu'il n'attrape PAS : la sémantique des expressions `${{ }}`, ni qu'une étape
fasse ce qu'elle prétend. Un `actionlint` le ferait ; il demanderait une
dépendance téléchargée, et le rapport valeur/coût ne le justifie pas encore.

Usage : Scripts/lint-workflows.py [chemin ...]   (défaut : .github/workflows)
"""
import pathlib
import re
import subprocess
import sys

try:
    import yaml
except ModuleNotFoundError:
    sys.exit("PyYAML est requis : pip install pyyaml")

# Les expressions GitHub sont substituées avant que bash ne voie le script.
# Les remplacer par un jeton inerte évite de faire échouer `bash -n` sur une
# syntaxe qui n'existe qu'au niveau du workflow — sans masquer une vraie faute
# de shell autour.
EXPR = re.compile(r"\$\{\{[^}]*\}\}")


def check(path: pathlib.Path) -> list[str]:
    problems: list[str] = []
    try:
        doc = yaml.safe_load(path.read_text())
    except yaml.YAMLError as err:
        return [f"{path}: YAML illisible — {err}"]
    if not isinstance(doc, dict) or "jobs" not in doc:
        return [f"{path}: pas de clé `jobs` — est-ce bien un workflow ?"]

    for job_name, job in (doc["jobs"] or {}).items():
        for index, step in enumerate(job.get("steps") or []):
            script = step.get("run")
            if not script:
                continue
            label = step.get("name") or f"étape {index}"
            shell = step.get("shell", "bash")
            if not shell.startswith(("bash", "sh")):
                continue
            result = subprocess.run(
                ["bash", "-n"],
                input=EXPR.sub("EXPR", script),
                text=True,
                capture_output=True,
            )
            if result.returncode != 0:
                problems.append(f"{path}: {job_name} / {label} — {result.stderr.strip()}")
    return problems


targets = [pathlib.Path(a) for a in sys.argv[1:]] or [pathlib.Path(".github/workflows")]
files: list[pathlib.Path] = []
for target in targets:
    files.extend(sorted(target.glob("*.yml")) if target.is_dir() else [target])

if not files:
    sys.exit("aucun workflow trouvé — chemin correct ?")

failures = [problem for file in files for problem in check(file)]
for problem in failures:
    print(problem, file=sys.stderr)

print(f"lint-workflows: {len(files)} workflow(s) contrôlé(s), {len(failures)} problème(s)")
sys.exit(1 if failures else 0)

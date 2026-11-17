#!/usr/bin/env python3
"""Confere o pipeline do GitHub Actions (briefing, Pipeline e cadeia de suprimentos; ADR-0027).

Uso: confere_ci.py RAIZ_REPO -> imprime 'ok|falha <id> <detalhe>'.
Ids: GATILHO (pull_request), TESTES (./gradlew build|test|check), SAST, DEPENDENCIAS, SEGREDOS,
GUARDA_MIGRACAO e GUARDA_REVERSAO (scripts/ci/guarda-migracao.sh sobre db/migration e db/reversao),
GUARDA_BASE (iteracao 9: a guarda e a lista de tabelas sensiveis saem de um checkout do commit da
branch base, nunca do PR: no mesmo job, um actions/checkout com 'ref' da base e 'path' proprio, e a
guarda invocada como '<path>/scripts/ci/guarda-migracao.sh' sobre db/migration e sobre db/reversao).
A sintaxe (actionlint) e conferida pelo runner.
"""
import glob
import os
import sys

import yaml

SAST = ("github/codeql-action/analyze", "semgrep", "spotbugs", "find-sec-bugs", "findsecbugs")
DEPS = ("dependency-check", "dependencycheck", "trivy", "osv-scanner", "dependency-review-action", "grype", "anchore/scan-action", "snyk")
SEGREDOS = ("gitleaks", "trufflehog")


def passos(wf):
    for job in (wf.get("jobs") or {}).values():
        for st in job.get("steps") or []:
            yield (str(st.get("uses", "")) + " " + str(st.get("run", ""))).lower(), str(st.get("run", ""))


def main(raiz):
    arqs = sorted(glob.glob(os.path.join(raiz, ".github/workflows/*.yml")) + glob.glob(os.path.join(raiz, ".github/workflows/*.yaml")))
    if not arqs:
        print("falha GATILHO nenhum workflow em .github/workflows")
        return
    wfs = []
    for a in arqs:
        try:
            wfs.append(yaml.safe_load(open(a)))
        except Exception as e:  # noqa: BLE001
            print(f"falha GATILHO {a} nao e YAML valido: {e}")
            return
    gat = False
    for wf in wfs:
        on = wf.get("on", wf.get(True))  # PyYAML le 'on' como True
        if (isinstance(on, dict) and "pull_request" in on) or on == "pull_request" or (isinstance(on, list) and "pull_request" in on):
            gat = True
    print(("ok" if gat else "falha") + " GATILHO workflow roda em pull_request")
    tudo = [p for wf in wfs for p in passos(wf)]
    def tem(cond):
        return any(cond(t, r) for t, r in tudo)
    print(("ok" if tem(lambda t, r: "./gradlew" in t and any(k in t for k in (" build", " test", " check"))) else "falha") + " TESTES ./gradlew build|test|check")
    print(("ok" if tem(lambda t, r: any(k in t for k in SAST)) else "falha") + " SAST analise estatica de seguranca")
    print(("ok" if tem(lambda t, r: any(k in t for k in DEPS)) else "falha") + " DEPENDENCIAS varredura de dependencias vulneraveis")
    print(("ok" if tem(lambda t, r: any(k in t for k in SEGREDOS)) else "falha") + " SEGREDOS varredura de segredos")
    g = [r for t, r in tudo if "scripts/ci/guarda-migracao.sh" in r]
    print(("ok" if any("db/migration" in r for r in g) else "falha") + " GUARDA_MIGRACAO guarda roda sobre db/migration")
    print(("ok" if any("db/reversao" in r for r in g) else "falha") + " GUARDA_REVERSAO guarda roda sobre db/reversao")
    base = {"db/migration": False, "db/reversao": False}
    for wf in wfs:
        for job in (wf.get("jobs") or {}).values():
            caminhos = []
            for st in job.get("steps") or []:
                w = st.get("with") or {}
                ref = str(w.get("ref", "")).replace(" ", "")
                if str(st.get("uses", "")).startswith("actions/checkout@") and w.get("path") and \
                        ("pull_request.base.sha" in ref or "github.base_ref" in ref):
                    caminhos.append(str(w["path"]).strip().strip("/").removeprefix("./"))
            for st in job.get("steps") or []:
                for linha in str(st.get("run", "")).splitlines():
                    cmd = linha.strip().removeprefix("./")
                    if any(c and cmd.startswith(c + "/scripts/ci/guarda-migracao.sh") for c in caminhos):
                        for k in base:
                            if k in cmd:
                                base[k] = True
    print(("ok" if all(base.values()) else "falha") + " GUARDA_BASE guarda e lista de tabelas sensiveis da branch base sobre db/migration e db/reversao do PR")


if __name__ == "__main__":
    main(sys.argv[1])

#!/usr/bin/env python3
"""F10: confere os planos do Terraform (terraform show -json) gerados sem credenciais.

Uso: confere_plano.py DIR_PLANOS RAIZ_TF COTACAO1 COTACAO2 EMAIL
  DIR_PLANOS/<raiz>-<cotacao>.json para cada raiz planejada (ambientes/dev, homolog, prod e, se existir, conta).
Imprime 'ok|falha F10.<n> <detalhe>'. Regras: docs/fase2/spec.md, F10.
"""
import glob
import json
import os
import re
import sys

dirp, raiz_tf, cot1, cot2, email = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), sys.argv[5]
TETO = 800.0
AMB = ("dev", "homolog", "prod")


def r(crit, ok, d):
    print(("ok " if ok else "falha ") + crit + " " + d)


def recursos(mod):
    for x in mod.get("resources", []) or []:
        yield x
    for c in mod.get("child_modules", []) or []:
        yield from recursos(c)


def config_recursos(mod, pref=""):
    for x in mod.get("resources", []) or []:
        yield x
    for nome, c in (mod.get("module_calls") or {}).items():
        yield from config_recursos(c.get("module", {}), pref + nome + ".")


def carrega(nome, cot):
    p = os.path.join(dirp, f"{nome.replace('/', '_')}-{cot}.json")
    return json.load(open(p)) if os.path.exists(p) else None


def tipo(plano, t):
    return [x for x in recursos(plano.get("planned_values", {}).get("root_module", {})) if x.get("type") == t]


def cfg_tipo(plano, t):
    return [x for x in config_recursos(plano.get("configuration", {}).get("root_module", {})) if x.get("type") == t]


def regiao(plano):
    pc = plano.get("configuration", {}).get("provider_config", {})
    regs = []
    for k, v in pc.items():
        if v.get("name") != "aws":
            continue
        e = v.get("expressions", {}).get("region", {})
        if "constant_value" in e:
            regs.append(e["constant_value"])
        for ref in e.get("references", []):
            if ref.startswith("var."):
                regs.append(plano.get("variables", {}).get(ref[4:], {}).get("value"))
    return regs


txt = ""
for f in glob.glob(os.path.join(raiz_tf, "**/*.tf"), recursive=True):
    txt += open(f, errors="replace").read() + "\n"

planos = {a: carrega(f"ambientes/{a}", cot1) for a in AMB}
if not all(planos.values()):
    r("F10.3", False, "falta plano de algum ambiente")
    sys.exit(0)

buckets, rds_ids = {}, {}
for a, p in planos.items():
    regs = regiao(p)
    r("F10.3", bool(regs) and all(x == "sa-east-1" for x in regs), f"{a}: provider aws em sa-east-1 ({regs})")
    # RDS
    dbs = tipo(p, "aws_db_instance")
    pgs = {x["values"].get("name"): x["values"] for x in tipo(p, "aws_db_parameter_group")}
    ok_db = bool(dbs)
    det = []
    for d in dbs:
        v = d["values"]
        conds = {
            "postgres 16": v.get("engine") == "postgres" and str(v.get("engine_version", "")).startswith("16"),
            "storage_encrypted": v.get("storage_encrypted") is True,
            "nao publico": v.get("publicly_accessible") is False,
            "PITR (backup_retention_period>=1)": (v.get("backup_retention_period") or 0) >= 1,
            "logs postgresql exportados": "postgresql" in (v.get("enabled_cloudwatch_logs_exports") or []),
            "deletion_protection em prod": a != "prod" or v.get("deletion_protection") is True,
        }
        pg = pgs.get(v.get("parameter_group_name"))
        conds["rds.force_ssl=1 no parameter group"] = bool(pg) and any(
            str(x.get("name")) == "rds.force_ssl" and str(x.get("value")) == "1" for x in (pg.get("parameter") or []))
        for k, c in conds.items():
            if not c:
                ok_db = False
                det.append(k)
        rds_ids.setdefault(a, set()).add(v.get("identifier"))
    senha_literal = any("password" in (c.get("expressions") or {}) and "constant_value" in c["expressions"]["password"]
                        for c in cfg_tipo(p, "aws_db_instance"))
    r("F10.4", ok_db and not senha_literal, f"{a}: RDS PostgreSQL 16 cifrado, privado, PITR, TLS obrigatorio, logs exportados, senha fora do codigo ({det[:3]}{' senha literal' if senha_literal else ''})")
    # S3 + KMS
    bks = tipo(p, "aws_s3_bucket")
    sse = tipo(p, "aws_s3_bucket_server_side_encryption_configuration")
    pab = tipo(p, "aws_s3_bucket_public_access_block")
    kms = tipo(p, "aws_kms_key")
    ok_sse = bool(sse) and all(
        any((rr.get("apply_server_side_encryption_by_default") or [{}])[0].get("sse_algorithm") == "aws:kms" for rr in (s["values"].get("rule") or []))
        for s in sse) and len(sse) >= len(bks)
    ok_pab = bool(pab) and len(pab) >= len(bks) and all(all(x["values"].get(k) is True for k in ("block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets")) for x in pab)
    ok_kms = bool(kms) and all(k["values"].get("enable_key_rotation") is True for k in kms)
    ok_pol = bool(tipo(p, "aws_s3_bucket_policy")) and "aws:SecureTransport" in txt and "s3:x-amz-server-side-encryption" in txt
    r("F10.5", bool(bks) and ok_sse and ok_pab and ok_kms and ok_pol,
      f"{a}: bucket privado com SSE-KMS, bloqueio publico, chave com rotacao, politica exige TLS e SSE-KMS (sse={ok_sse} pab={ok_pab} kms={ok_kms} politica={ok_pol})")
    buckets[a] = {b["values"].get("bucket") for b in bks}
    # Secrets Manager
    sec = tipo(p, "aws_secretsmanager_secret")
    nomes = " ".join(str(s["values"].get("name") or "") for s in sec)
    faltam = [c for c in ("saas_app", "saas_jobs", "saas_auth", "saas_migracao") if c not in nomes]
    literal = any("secret_string" in (c.get("expressions") or {}) and "constant_value" in c["expressions"]["secret_string"]
                  for c in cfg_tipo(p, "aws_secretsmanager_secret_version"))
    kms_sec = all("kms_key_id" in (c.get("expressions") or {}) for c in cfg_tipo(p, "aws_secretsmanager_secret"))
    r("F10.6", not faltam and not literal and kms_sec and bool(sec), f"{a}: segredos separados para saas_app, saas_jobs, saas_auth e saas_migracao, cifrados com KMS, sem valor no codigo (faltam {faltam}, literal={literal}, kms={kms_sec})")
    # Cognito
    pools = tipo(p, "aws_cognito_user_pool")
    cls = tipo(p, "aws_cognito_user_pool_client")
    ok_pool = bool(pools) and all(
        x["values"].get("mfa_configuration") in ("ON", "OPTIONAL")
        and any(s.get("enabled") is True for s in (x["values"].get("software_token_mfa_configuration") or []))
        and all((pp.get("minimum_length") or 0) >= 12 for pp in (x["values"].get("password_policy") or [{}]))
        for x in pools)

    def curto(c):
        v = c["values"]
        un = ((v.get("token_validity_units") or [{}])[0] or {}).get("access_token") or "hours"
        val = v.get("access_token_validity") or 1
        minutos = val * {"seconds": 1 / 60, "minutes": 1, "hours": 60, "days": 1440}.get(un, 60)
        return minutos <= 60 and v.get("enable_token_revocation") is True
    ok_cli = bool(cls) and all(curto(c) for c in cls)
    r("F10.7", ok_pool and ok_cli, f"{a}: Cognito com MFA TOTP habilitado, senha >= 12, access token <= 60 min e revogacao (pool={ok_pool} client={ok_cli})")
    # alarmes dos alertas do banco
    mfs = tipo(p, "aws_cloudwatch_log_metric_filter")
    alarmes = tipo(p, "aws_cloudwatch_metric_alarm")
    nomes_alarme = {x["values"].get("metric_name") for x in alarmes}
    for marcador in ("ALERTA_DDL_SAAS", "ALERTA_PREPARO_VOLUME"):
        f = [x for x in mfs if marcador in str(x["values"].get("pattern", ""))]
        metricas = {t.get("name") for x in f for t in (x["values"].get("metric_transformation") or [])}
        r("F10.8", bool(f) and bool(metricas & nomes_alarme), f"{a}: filtro de log com {marcador} e alarme na metrica")

# isolamento entre ambientes
todos = [b for a in AMB for b in buckets.get(a, set()) if b]
r("F10.9", len(todos) == len(set(todos)) and len(todos) >= 3, f"buckets distintos por ambiente ({len(todos)} nomes, {len(set(todos))} distintos)")
ids = [i for a in AMB for i in rds_ids.get(a, set()) if i]
r("F10.9", len(ids) == len(set(ids)) and len(ids) >= 3, f"instancias RDS distintas por ambiente ({len(ids)} identificadores)")

# orcamento coerente com o teto (ADR-0013), com duas cotacoes para nao aceitar valor fixo
for cot in (cot1, cot2):
    achou = []
    for f in sorted(glob.glob(os.path.join(dirp, f"*-{cot}.json"))):
        p = json.load(open(f))
        for b in tipo(p, "aws_budgets_budget"):
            v = b["values"]
            if v.get("budget_type") == "COST" and v.get("time_unit") == "MONTHLY" and v.get("limit_unit") == "USD":
                lim = float(v.get("limit_amount") or 0)
                nots = v.get("notification") or []
                atual = any(n.get("notification_type") == "ACTUAL" and float(n.get("threshold") or 999) <= 100 for n in nots)
                prev = any(n.get("notification_type") == "FORECASTED" for n in nots)
                mail = all(email in (n.get("subscriber_email_addresses") or []) for n in nots) and bool(nots)
                filtro = bool(v.get("cost_filter")) or bool(v.get("cost_filters"))
                achou.append((lim, atual, prev, mail, filtro))
    ok = any(0 < lim * cot <= TETO + 0.01 and lim * cot >= TETO * 0.5 and atual and prev and mail and not filtro for lim, atual, prev, mail, filtro in achou)
    r("F10.10", ok, f"cotacao {cot}: orcamento mensal da conta em USD com limite x cotacao entre R$ 400 e R$ 800, alerta real <= 100% e previsto, para o e-mail informado ({achou[:2]})")

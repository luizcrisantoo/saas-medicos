"""Utilitarios dos testes HTTP de aceite (F6 a F9): JWT RS256 assinado por chave local, JWKS servido
localmente, cliente HTTP sem proxy e consultas ao PostgreSQL efemero pelo psql do runner.
Nada aqui pertence ao Executor."""
import base64
import hashlib
import http.server
import json
import os
import subprocess
import threading
import time
import urllib.error
import urllib.request
import uuid

from cryptography.hazmat.primitives import hashes, hmac, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

RESULTADOS = []


def resultado(crit, ok, descr):
    RESULTADOS.append((crit, bool(ok), descr))
    print(("ok " if ok else "falha ") + crit + " " + descr, flush=True)


def b64u(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


class Chave:
    def __init__(self, kid, priv=None):
        self.kid = kid
        self.priv = priv or rsa.generate_private_key(public_exponent=65537, key_size=2048)

    @staticmethod
    def carrega(kid, caminho):
        return Chave(kid, serialization.load_pem_private_key(open(caminho, "rb").read(), password=None))

    def salva(self, caminho):
        open(caminho, "wb").write(self.priv.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                                          serialization.NoEncryption()))

    def jwk(self):
        n = self.priv.public_key().public_numbers()
        return {"kty": "RSA", "kid": self.kid, "use": "sig", "alg": "RS256",
                "n": b64u(n.n.to_bytes((n.n.bit_length() + 7) // 8, "big")), "e": b64u(n.e.to_bytes(3, "big"))}

    def pem_publico(self):
        return self.priv.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)


def jwt(chave, claims, kid=None, alg="RS256", segredo_hs=None):
    cab = {"alg": alg, "typ": "JWT"}
    if alg != "none":
        cab["kid"] = kid or chave.kid
    corpo = b64u(json.dumps(cab).encode()) + "." + b64u(json.dumps(claims).encode())
    if alg == "none":
        return corpo + "."
    if alg == "HS256":
        h = hmac.HMAC(segredo_hs, hashes.SHA256())
        h.update(corpo.encode())
        return corpo + "." + b64u(h.finalize())
    sig = chave.priv.sign(corpo.encode(), padding.PKCS1v15(), hashes.SHA256())
    return corpo + "." + b64u(sig)


def claims_cognito(sub, iss, client_id, token_use="access", exp_em=900, **extra):
    agora = int(time.time())
    c = {"sub": sub, "iss": iss, "client_id": client_id, "token_use": token_use, "scope": "aws.cognito.signin.user.admin",
         "auth_time": agora - 5, "iat": agora - 5, "exp": agora + exp_em, "jti": str(uuid.uuid4()), "username": sub}
    if token_use == "id":
        c.pop("client_id")
        c["aud"] = client_id
    c.update(extra)
    return c


def serve_jwks(porta, chaves):
    corpo = json.dumps({"keys": [k.jwk() for k in chaves]}).encode()

    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            self.send_response(200 if self.path.startswith("/jwks.json") else 404)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            if self.path.startswith("/jwks.json"):
                self.wfile.write(corpo)

        def log_message(self, *a):
            pass

    srv = http.server.ThreadingHTTPServer(("127.0.0.1", porta), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


class Resp:
    def __init__(self, status, headers, corpo):
        self.status, self.headers, self.corpo = status, headers, corpo

    def json(self):
        try:
            return json.loads(self.corpo or b"null")
        except Exception:  # noqa: BLE001
            return None

    def cookies(self):
        return [v for k, v in self.headers if k.lower() == "set-cookie"]

    def texto(self):
        return (self.corpo or b"").decode(errors="replace")


def req(metodo, url, corpo=None, cab=None):
    dados = json.dumps(corpo).encode() if corpo is not None else None
    r = urllib.request.Request(url, data=dados, method=metodo)
    if dados is not None:
        r.add_header("Content-Type", "application/json")
    for k, v in (cab or {}).items():
        r.add_header(k, v)
    try:
        with _OPENER.open(r, timeout=30) as resp:
            return Resp(resp.status, resp.getheaders(), resp.read())
    except urllib.error.HTTPError as e:
        return Resp(e.code, e.headers.items(), e.read())
    except Exception as e:  # noqa: BLE001
        return Resp(0, [], str(e).encode())


def sql(consulta):
    """Consulta como superusuario do cluster efemero (variaveis do runner: PGDIR, PGPORTA, APP_DB)."""
    r = subprocess.run(["psql", "-X", "-q", "-At", "-h", os.environ["PGDIR"], "-p", os.environ["PGPORTA"], "-U", "pgtest",
                        "-d", os.environ.get("APP_DB", "app"), "-c", consulta], capture_output=True, text=True)
    return r.stdout.strip()


def sha256hex(texto):
    return hashlib.sha256(bytes.fromhex(texto)).hexdigest()


def vaza_excecao(resp):
    """Corpo de erro nao pode trazer detalhe interno (ADR-0026, item 3)."""
    t = resp.texto().lower()
    return any(k in t for k in ("psqlexception", "sqlstate", "exception", "stacktrace", "at org.", "at saasagenda", "saas.", "select ", "error:  "))

#!/usr/bin/env bash
# Instala ferramentas fixadas (versao + sha256 oficial) em acceptance/.bin.
# Usado pelo run.sh; idempotente. Nada aqui e do Executor.
set -euo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$AQUI/.bin"; mkdir -p "$BIN"
baixa() { # url sha256 destino
  local url=$1 sha=$2 dst=$3
  if [ -f "$dst" ] && echo "$sha  $dst" | sha256sum -c --quiet - 2>/dev/null; then return 0; fi
  curl -sSL --retry 3 --max-time 300 -o "$dst" "$url"
  echo "$sha  $dst" | sha256sum -c --quiet - || { echo "sha256 divergente: $url" >&2; rm -f "$dst"; exit 1; }
}
T=$BIN/_dl; mkdir -p "$T"
if [ ! -x "$BIN/terraform" ]; then
  baixa https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip \
        186e0145f5e5f2eb97cbd785bc78f21bae4ef15119349f6ad4fa535b83b10df8 "$T/tf.zip"
  unzip -o -q "$T/tf.zip" terraform -d "$BIN"
fi
if [ ! -x "$BIN/actionlint" ]; then
  baixa https://github.com/rhysd/actionlint/releases/download/v1.7.7/actionlint_1.7.7_linux_amd64.tar.gz \
        023070a287cd8cccd71515fedc843f1985bf96c436b7effaecce67290e7e0757 "$T/al.tgz"
  tar -xzf "$T/al.tgz" -C "$BIN" actionlint
fi
if [ ! -x "$BIN/gitleaks" ]; then
  baixa https://github.com/gitleaks/gitleaks/releases/download/v8.21.2/gitleaks_8.21.2_linux_x64.tar.gz \
        5bc41815076e6ed6ef8fbecc9d9b75bcae31f39029ceb55da08086315316e3ba "$T/gl.tgz"
  tar -xzf "$T/gl.tgz" -C "$BIN" gitleaks
fi
rm -rf "$T"

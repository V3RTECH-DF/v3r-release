#!/usr/bin/env bash
# fixture.sh — monta, em diretório temporário, um pacote de mentira correto
# (a "linha de base") que cada teste copia e estraga de um jeito só, para
# provar que aquela e só aquela conferência recusa.
#
# Nada aqui escreve fora do que o chamador passar como diretório de trabalho.
#
# ⚠️ Este arquivo é `source`-ado pelo runner (tests/run-tests.sh), não
# executado como script próprio — por isso NÃO declara `set -e` aqui: faria
# a opção vazar para o shell do runner e abortá-lo na primeira recusa
# esperada de um teste (que tem código de saída 1 de propósito).

FIXTURE_SLUG="v3r-example"
FIXTURE_VERSION="1.0.0"

# build_baseline_fixture <diretório-pai>
# Cria <diretório-pai>/v3r-example/... com um pacote inteiramente correto:
# todas as 15 conferências (mais §3 e §6) passam nele.
build_baseline_fixture() {
  local parent="$1"
  local root="$parent/$FIXTURE_SLUG"
  mkdir -p "$root"

  cat > "$root/v3r-example.php" <<EOF
<?php
/**
 * Plugin Name: V3R Example
 * Version: $FIXTURE_VERSION
 */
require __DIR__ . '/vendor/autoload.php';
EOF

  cat > "$root/readme.txt" <<EOF
=== V3R Example ===
Stable tag: $FIXTURE_VERSION
EOF

  cat > "$root/package.json" <<EOF
{"name": "v3r-example", "version": "$FIXTURE_VERSION"}
EOF

  mkdir -p "$root/assets/build"
  echo "console.log(1)" > "$root/assets/build/app.js"
  echo "body{}" > "$root/assets/build/app.css"
  echo '{"app.js":"app.js"}' > "$root/assets/build/manifest.json"

  # biblioteca prefixada: árvore crua VAZIA (o correto), árvore prefixada com
  # conteúdo real.
  mkdir -p "$root/vendor/guzzlehttp/guzzle"
  mkdir -p "$root/vendor-prefixed/guzzlehttp/guzzle/src"
  cat > "$root/vendor-prefixed/guzzlehttp/guzzle/src/Client.php" <<'EOF'
<?php
namespace V3RExample\GuzzleHttp;
class Client {}
EOF

  mkdir -p "$root/vendor/composer"
  cat > "$root/vendor/composer/autoload_classmap.php" <<'EOF'
<?php
return array(
    'V3RExample\\GuzzleHttp\\Client' => __DIR__ . '/../../vendor-prefixed/guzzlehttp/guzzle/src/Client.php',
);
EOF

  cat > "$root/vendor/autoload.php" <<'EOF'
<?php
spl_autoload_register(function ($class) {
    $map = require __DIR__ . '/composer/autoload_classmap.php';
    if (isset($map[$class])) {
        require $map[$class];
    }
});
EOF

  cat > "$root/uninstall.php" <<'EOF'
<?php
// nada a fazer
EOF

  cat > "$root/CHANGELOG.md" <<EOF
## $FIXTURE_VERSION
- primeira versão
EOF

  find "$root" -type d -exec chmod 755 {} \;
  find "$root" -type f -exec chmod 644 {} \;
}

# baseline_config <caminho-de-saída>
# Copia o exemplo de declaração (que já casa com a linha de base acima).
baseline_config() {
  local out="$1"
  local repo_root
  repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." >/dev/null 2>&1 && pwd -P)"
  cp "$repo_root/examples/release.config.sh" "$out"
}

# zip_fixture <diretório-pai> <slug> <versão-do-nome> <zip-de-saída>
# Empacota <diretório-pai>/<slug> num zip nomeado "<slug>-<versão>.zip" (a
# convenção que o item 2 confere).
zip_fixture() {
  # shellcheck disable=SC2034
  # (nome_versao só documenta a convenção — quem decide o nome do zip de
  # saída é o chamador, em out_zip)
  local parent="$1" slug="$2" nome_versao="$3" out_zip="$4"
  ( cd "$parent" && zip -r -q -X "$out_zip" "$slug" )
}

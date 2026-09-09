#!/usr/bin/env bash
# run-tests.sh — suíte de testes do v3r-release. Bash puro, sem rede, sem
# instalar nada. Cada teste monta seu próprio pacote-fixture (uma cópia
# mutada da linha de base) em diretório temporário, empacota, roda
# `bin/verify-package.sh` sobre ele e confere o resultado.
#
# Uso: tests/run-tests.sh

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd -P)"
VERIFY="$REPO_ROOT/bin/verify-package.sh"

# shellcheck disable=SC1091
source "$REPO_ROOT/tests/lib/fixture.sh"

TESTS_RUN=0
TESTS_FAILED=0
CURRENT_TEST=""

# work_dir — cria um diretório de trabalho novo para o teste corrente.
#
# ⚠️ Não registra sozinho em ALL_WORKDIRS: quem chama isto o faz sempre via
# `wd="$(work_dir)"` (substituição de comando), que roda num SUBSHELL — um
# `ALL_WORKDIRS+=(...)` feito aqui dentro morreria com o subshell e nunca
# chegaria ao array do processo principal. É por isso que cada teste
# registra o diretório explicitamente, logo depois de recebê-lo.
work_dir() {
  mktemp -d "${TMPDIR:-/tmp}/v3r-release-test.XXXXXX"
}

ALL_WORKDIRS=()
cleanup_all() {
  local d
  for d in "${ALL_WORKDIRS[@]:-}"; do
    [ -n "$d" ] && rm -rf -- "$d"
  done
}
trap cleanup_all EXIT

# fail <mensagem> — registra falha do teste corrente.
fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "FALHOU — $CURRENT_TEST: $1"
}

ok() {
  echo "ok — $CURRENT_TEST"
}

# roda_verify [--all] <zip> <config> ; preenche RC e OUT.
#
# ⚠️ Não injeta --expected-version sozinha: cada teste passa a versão que
# faz sentido para o cenário que está montando (a maioria é FIXTURE_VERSION,
# mas o teste do item 2 precisa poder declarar uma versão diferente da do
# cabeçalho de propósito).
RC=0
OUT=""
roda_verify() {
  OUT="$("$VERIFY" "$@" 2>&1)"
  RC=$?
}

# assert_aprovado <zip> <config> <versão-esperada>
assert_aprovado() {
  roda_verify --expected-version "$3" "$1" "$2"
  if [ "$RC" -ne 0 ]; then
    fail "esperava aprovação (exit 0), veio $RC. Saída:
$OUT"
    return 1
  fi
  ok
}

# assert_recusado <zip> <config> <versão-esperada> <trecho-esperado-na-mensagem>
assert_recusado() {
  local zip="$1" cfg="$2" versao="$3" trecho="$4"
  roda_verify --expected-version "$versao" "$zip" "$cfg"
  if [ "$RC" -eq 0 ]; then
    fail "esperava recusa, mas o pacote foi aprovado. Saída:
$OUT"
    return 1
  fi
  if ! grep -qF -- "$trecho" <<<"$OUT"; then
    fail "recusou, mas não pela razão esperada (\"$trecho\"). Saída:
$OUT"
    return 1
  fi
  ok
}

run_test() {
  CURRENT_TEST="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  "$1"
}

# ---------------------------------------------------------------------------
# Baseline — o pacote correto passa em tudo
# ---------------------------------------------------------------------------

test_baseline_aprova() {
  local wd zip cfg
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_aprovado "$zip" "$cfg" "$FIXTURE_VERSION"
}

# ---------------------------------------------------------------------------
# §3 — versão da própria peça
# ---------------------------------------------------------------------------

test_secao3_versao_da_peca_diferente() {
  local wd zip cfg
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  # a declaração espera uma versão de v3r-release que não é a instalada
  sed -i 's/RELEASE_TOOLING_VERSION="0.1.0"/RELEASE_TOOLING_VERSION="9.9.9"/' "$cfg"
  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "versão do v3r-release"
}

# ---------------------------------------------------------------------------
# Item 1 — versão do cabeçalho vazia ou ilegível
# ---------------------------------------------------------------------------

test_item1_versao_cabecalho_ilegivel() {
  local wd zip cfg
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  # remove o número de versão do cabeçalho — a regex declarada não casa mais
  sed -i 's/ \* Version: 1.0.0/ * Version:/' "$wd/$FIXTURE_SLUG/v3r-example.php"
  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "item 1"
}

# ---------------------------------------------------------------------------
# Item 2 — versão do cabeçalho diferente da que o pacote anuncia publicar
# ---------------------------------------------------------------------------

test_item2_versao_diferente_da_esperada() {
  local wd zip cfg
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  # cabeçalho continua 1.0.0, mas quem chama a conferência PRETENDE publicar
  # 2.0.0 (--expected-version) — não há mais convenção de nome de arquivo a
  # deduzir; o nome do zip aqui é só um nome, não carrega intenção nenhuma.
  zip="$wd/v3r-example-qualquer-nome.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg" "2.0.0" "item 2"
}

# ---------------------------------------------------------------------------
# Item 3 — outro ponto de versão discorda do cabeçalho
# ---------------------------------------------------------------------------

test_item3_versao_extra_diverge() {
  local wd zip cfg
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  sed -i 's/Stable tag: 1.0.0/Stable tag: 1.0.1/' "$wd/$FIXTURE_SLUG/readme.txt"
  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "item 3"
}

# ---------------------------------------------------------------------------
# Item 4 — artefato de front sem manifesto
# ---------------------------------------------------------------------------

test_item4_artefato_sem_manifesto() {
  local wd zip cfg
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  rm -f "$wd/$FIXTURE_SLUG/assets/build/manifest.json"
  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "item 4"
}

# ---------------------------------------------------------------------------
# Item 5 — arquivo enfileirado pelo PHP ausente (o artefato continua ok)
# ---------------------------------------------------------------------------

test_item5_arquivo_enfileirado_ausente() {
  local wd zip cfg
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  # remove só o CSS enfileirado; o diretório continua não-vazio e com
  # manifesto, então o item 4 continua passando — só o item 5 quebra.
  rm -f "$wd/$FIXTURE_SLUG/assets/build/app.css"
  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "item 5"
}

# ---------------------------------------------------------------------------
# Item 6 — biblioteca prefixada ausente
# ---------------------------------------------------------------------------

test_item6_biblioteca_prefixada_ausente() {
  local wd zip cfg
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  rm -rf "$wd/$FIXTURE_SLUG/vendor-prefixed"
  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "item 6"
}

# ---------------------------------------------------------------------------
# Item 7 — a classe original AINDA resolve (prefixação pela metade)
#
# ⚠️ Isto tem que quebrar SÓ o item 7: o arquivo com a classe original é
# colocado fora das árvores vendor/vendor-prefixed, para não também acionar
# o item 8 (que já tem teste próprio).
# ---------------------------------------------------------------------------

test_item7_classe_original_ainda_resolve() {
  local wd zip cfg root
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"

  mkdir -p "$root/leaked"
  cat > "$root/leaked/Client.php" <<'EOF'
<?php
namespace GuzzleHttp;
class Client {}
EOF
  cat > "$root/vendor/composer/autoload_classmap.php" <<'EOF'
<?php
return array(
    'V3RExample\\GuzzleHttp\\Client' => __DIR__ . '/../../vendor-prefixed/guzzlehttp/guzzle/src/Client.php',
    'GuzzleHttp\\Client' => __DIR__ . '/../../leaked/Client.php',
);
EOF

  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "item 7"
}

# ---------------------------------------------------------------------------
# Item 8 — a armadilha: diretório cru com CONTEÚDO (não só existir)
# ---------------------------------------------------------------------------

test_item8_componente_nas_duas_arvores_com_conteudo() {
  local wd zip cfg root
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"

  # a árvore crua deixa de estar vazia — isto é o defeito.
  echo "<?php // sobrou aqui" > "$root/vendor/guzzlehttp/guzzle/Sobra.php"

  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "item 8"
}

# A contraprova da armadilha: diretório cru PRESENTE e VAZIO é correto e
# precisa passar. É exatamente o baseline (que já tem vendor/guzzlehttp/guzzle
# vazio) — este teste só deixa isso explícito e a prova de que discrimina.
test_item8_diretorio_cru_vazio_e_correto() {
  local wd zip cfg root
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"

  if [ ! -d "$root/vendor/guzzlehttp/guzzle" ]; then
    fail "pré-condição do teste quebrada: diretório cru não existe no baseline"
    return
  fi
  if [ -n "$(find "$root/vendor/guzzlehttp/guzzle" -mindepth 1)" ]; then
    fail "pré-condição do teste quebrada: diretório cru do baseline não está vazio"
    return
  fi

  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_aprovado "$zip" "$cfg" "$FIXTURE_VERSION"
}

# ---------------------------------------------------------------------------
# Item 9 — classe do classmap que não resolve para arquivo existente
# ---------------------------------------------------------------------------

test_item9_classmap_aponta_para_arquivo_inexistente() {
  local wd zip cfg root
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"

  cat > "$root/vendor/composer/autoload_classmap.php" <<'EOF'
<?php
return array(
    'V3RExample\\GuzzleHttp\\Client' => __DIR__ . '/../../vendor-prefixed/guzzlehttp/guzzle/src/Client.php',
    'V3RExample\\GuzzleHttp\\Fantasma' => __DIR__ . '/../../vendor-prefixed/guzzlehttp/guzzle/src/Fantasma.php',
);
EOF

  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "item 9"
}

# ---------------------------------------------------------------------------
# Item 10 — nome de classe original escapou como texto
# ---------------------------------------------------------------------------

test_item10_texto_nao_prefixado_escapou() {
  local wd zip cfg root
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"

  cat >> "$root/v3r-example.php" <<'EOF'
$classe_montada = 'GuzzleHttp\Client';
EOF

  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "item 10"
}

# ---------------------------------------------------------------------------
# Item 10, a armadilha central: o nome PREFIXADO CONTÉM o nome ORIGINAL como
# sufixo. Buscar por substring, sem mais, recusaria isto — que é exatamente
# uso CORRETO. Este é o par de controle que prova que a conferência
# discrimina: a mesma classe, com e sem o prefixo completo na frente.
#
# ⚠️ Antes da correção, ESTE teste falhava: `use V3RExample\GuzzleHttp\Client`
# (grafia simples, corretamente prefixada) continha a substring
# "GuzzleHttp\Client" e era recusado só por isso — o defeito real encontrado
# no pacote publicado do RIT360 Solidário.
# ---------------------------------------------------------------------------

test_item10_grafia_prefixada_correta_passa() {
  local wd zip cfg root
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"

  # grafia simples (uso normal de `use`) e grafia escapada (dentro de uma
  # string, como um `class_exists()`) — as duas com o prefixo completo.
  cat >> "$root/v3r-example.php" <<'EOF'
use V3RExample\GuzzleHttp\Client;
class_exists('V3RExample\\GuzzleHttp\\Client');
EOF

  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_aprovado "$zip" "$cfg" "$FIXTURE_VERSION"
}

test_item10_grafia_escapada_sem_prefixo_e_recusada() {
  local wd zip cfg root
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"

  # a MESMA classe, na grafia escapada, mas sem o prefixo — vazamento real,
  # e precisa continuar recusando mesmo depois da correção do item 10.
  cat >> "$root/v3r-example.php" <<'EOF'
class_exists('GuzzleHttp\\Client');
EOF

  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "item 10"
}

# O mapa de classes é arquivo GERADO — pode legitimamente conter o nome
# original como texto (ex.: comentário de uma entrada antiga, ou uma entrada
# de fallback do próprio Composer) sem que isso seja um vazamento do
# PRODUTO. Fica de fora desta checagem por declaração (RELEASE_CLASSMAP_FILES),
# não por estar dentro das árvores cru/prefixada.
test_item10_classmap_gerado_fica_de_fora_da_checagem() {
  local wd zip cfg root
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"

  cat >> "$root/vendor/composer/autoload_classmap.php" <<'EOF'
// entrada antiga, mantida como comentário: GuzzleHttp\Client
EOF

  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_aprovado "$zip" "$cfg" "$FIXTURE_VERSION"
}

# O defeito que este item existe para pegar é nome de classe montado como
# DADO — a ferramenta de prefixação reescreve código, não comentário. Um
# nome original sem prefixo dentro de `// comentário` e de `/** docblock */`
# não carrega classe nenhuma e precisa PASSAR. Este é o caso real que travou
# a fatia anterior: o pacote publicado do V3REvent tinha o nome original de
# uma biblioteca dentro de um `//` e de um `/** */`, com o uso funcional no
# mesmo arquivo corretamente prefixado.
test_item10_nome_original_em_comentario_e_docblock_passa() {
  local wd zip cfg root
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"

  cat >> "$root/v3r-example.php" <<'EOF'
// criação do GuzzleHttp\Client — não mais aqui.
/**
 * Antes disto o nome ficava GuzzleHttp\Client, sem prefixo.
 */
use V3RExample\GuzzleHttp\Client;
EOF

  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_aprovado "$zip" "$cfg" "$FIXTURE_VERSION"
}

# Heredoc/nowdoc é DADO, do mesmo jeito que uma string entre aspas — a
# ferramenta de prefixação não entra nele. O nome original sem prefixo
# dentro de um heredoc continua sendo o vazamento real que este item existe
# para pegar.
test_item10_nome_original_em_heredoc_e_recusado() {
  local wd zip cfg root
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"

  cat >> "$root/v3r-example.php" <<'EOF'
$texto = <<<EOT
GuzzleHttp\Client
EOT;
EOF

  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "item 10"
}

# Arquivo PHP que não tokeniza (malformado) é recusa, nomeando o arquivo —
# pacote com PHP que não se analisa é pacote suspeito. O trecho abaixo tem
# uma string entre aspas duplas sem fechamento, contendo o nome original,
# o que a torna ao mesmo tempo candidata ao pré-filtro por texto bruto E
# inanalisável pelo tokenizador (TOKEN_PARSE lança ParseError).
test_item10_arquivo_que_nao_tokeniza_e_recusado() {
  local wd zip cfg root
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"

  # shellcheck disable=SC2016
  # (aspas simples são deliberadas: é código PHP, não deve expandir no shell)
  printf '%s\n' '$quebrado = "GuzzleHttp\Client' >> "$root/v3r-example.php"

  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  # O trecho esperado é o da recusa por FALHA DE TOKENIZAÇÃO em si — não só
  # "item 10" genérico — porque o PHP tokeniza este arquivo de forma
  # tolerante mesmo sem TOKEN_PARSE (ainda reconhece a string malformada
  # como literal até o fim do arquivo) e acharia o vazamento de qualquer
  # jeito; o que este teste prova é que o CAMINHO de recusa é o de "não
  # tokenizou", não uma coincidência do achado por outra via.
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "não pôde ser analisado pelo tokenizador"
}

# ---------------------------------------------------------------------------
# Item 11 — arquivo de dados de runtime que não viajou
# ---------------------------------------------------------------------------

test_item11_arquivo_de_dados_ausente() {
  local wd zip cfg root cfg2
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  cfg2="$wd/release.config.with-runtime-data.sh"
  cp "$cfg" "$cfg2"
  cat >> "$cfg2" <<'EOF'
RELEASE_RUNTIME_DATA_FILES=(
  "vendor-prefixed/guzzlehttp/guzzle/dados/tabela.json"
)
EOF
  # propositalmente NÃO cria o arquivo em $root — é o defeito do teste.

  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg2" "$FIXTURE_VERSION" "item 11"
}

# ---------------------------------------------------------------------------
# Item 12 — caminho obrigatório ausente
# ---------------------------------------------------------------------------

test_item12_caminho_obrigatorio_ausente() {
  local wd zip cfg cfg2
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  cfg2="$wd/release.config.with-extra-required.sh"
  cp "$cfg" "$cfg2"
  cat >> "$cfg2" <<'EOF'
RELEASE_REQUIRED_PATHS=(
  "readme.txt"
  "v3r-example.php"
  "LICENSE.txt"
)
EOF
  # LICENSE.txt nunca existiu no baseline — é o defeito do teste.

  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg2" "$FIXTURE_VERSION" "item 12"
}

# ---------------------------------------------------------------------------
# Item 13 — pasta raiz do pacote diferente do identificador do produto
# ---------------------------------------------------------------------------

test_item13_pasta_raiz_errada() {
  local wd zip cfg
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  mv "$wd/$FIXTURE_SLUG" "$wd/nome-errado"
  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "nome-errado" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "item 13"
}

# ---------------------------------------------------------------------------
# Item 14 — fonte de desenvolvimento dentro do pacote
# ---------------------------------------------------------------------------

test_item14_fonte_de_desenvolvimento_presente() {
  local wd zip cfg root
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  mkdir -p "$root/node_modules/alguma-dependencia"
  echo "{}" > "$root/node_modules/alguma-dependencia/package.json"
  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "item 14"
}

# ---------------------------------------------------------------------------
# Item 15 — diretório sem permissão de travessia
# ---------------------------------------------------------------------------

test_item15_diretorio_sem_travessia() {
  local wd zip cfg root
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  chmod 700 "$root/assets/build"
  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "item 15"
}

# ---------------------------------------------------------------------------
# Item 20 — versão embutida de biblioteca prefixada (V3RCore-Code#44)
#
# A linha de base já traz `Version.php` dentro da árvore prefixada do guzzle
# (FIXTURE_LIB_VERSION), mas a declaração padrão (examples/release.config.sh)
# NÃO tem RELEASE_LIBRARY_VERSION_FILES — por isso test_baseline_aprova
# continua passando sem nunca acionar o item 20; cada teste abaixo acrescenta
# o campo por conta própria, sem tocar a declaração compartilhada.
# ---------------------------------------------------------------------------

# declara_versao_biblioteca <config> — acrescenta RELEASE_LIBRARY_VERSION_FILES
# apontando para o Version.php da linha de base (guzzle).
declara_versao_biblioteca() {
  local cfg="$1"
  cat >> "$cfg" <<'EOF'
RELEASE_LIBRARY_VERSION_FILES=(
  "guzzle|src/Version.php|const CURRENT = '\\K[0-9]+\\.[0-9]+\\.[0-9]+"
)
EOF
}

test_item20_versao_bate_com_a_esperada_aprova() {
  local wd zip cfg
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  declara_versao_biblioteca "$cfg"
  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  roda_verify --expected-version "$FIXTURE_VERSION" --expected-lib-version "guzzle=$FIXTURE_LIB_VERSION" "$zip" "$cfg"
  if [ "$RC" -ne 0 ]; then
    fail "esperava aprovação (exit 0), veio $RC. Saída:
$OUT"
    return
  fi
  ok
}

# O par de controle: a MESMA árvore, mas a versão que o build declara esperar
# é outra. Item 6-10 continuam passando (a árvore prefixada existe, resolve,
# não tem nada nas duas árvores) — só o item 20 pode recusar aqui, e a
# mensagem precisa dizer o que achou e o que esperava.
test_item20_versao_diverge_da_esperada_e_recusada() {
  local wd zip cfg
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  declara_versao_biblioteca "$cfg"
  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  roda_verify --expected-version "$FIXTURE_VERSION" --expected-lib-version "guzzle=9.9.9" "$zip" "$cfg"
  if [ "$RC" -eq 0 ]; then
    fail "esperava recusa, mas o pacote foi aprovado. Saída:
$OUT"
    return
  fi
  if ! grep -qF -- "item 20" <<<"$OUT"; then
    fail "recusou, mas não pela razão esperada (\"item 20\"). Saída:
$OUT"
    return
  fi
  if ! grep -qF -- "$FIXTURE_LIB_VERSION" <<<"$OUT" || ! grep -qF -- "9.9.9" <<<"$OUT"; then
    fail "recusou pelo item 20, mas a mensagem não diz o que achou ($FIXTURE_LIB_VERSION) e o que esperava (9.9.9). Saída:
$OUT"
    return
  fi
  ok
}

# Falha fechada: a declaração pede a conferência (RELEASE_LIBRARY_VERSION_FILES
# tem a entrada) mas ninguém passou --expected-lib-version para aquele slug —
# recusa, não aprova por omissão.
test_item20_sem_expected_lib_version_e_recusado() {
  local wd zip cfg
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  declara_versao_biblioteca "$cfg"
  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  roda_verify --expected-version "$FIXTURE_VERSION" "$zip" "$cfg"
  if [ "$RC" -eq 0 ]; then
    fail "esperava recusa (falha fechada), mas o pacote foi aprovado sem --expected-lib-version. Saída:
$OUT"
    return
  fi
  if ! grep -qF -- "item 20" <<<"$OUT"; then
    fail "recusou, mas não pela razão esperada (\"item 20\"). Saída:
$OUT"
    return
  fi
  ok
}

# Controle negativo: declaração SEM RELEASE_LIBRARY_VERSION_FILES (a
# declaração de linha de base, sem alteração nenhuma) precisa passar mesmo
# SEM --expected-lib-version nenhum — o item 20 é opt-in, não pode travar
# quem ainda não declarou biblioteca nenhuma para conferir.
test_item20_sem_declaracao_nao_afeta_pacote_correto() {
  local wd zip cfg
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_aprovado "$zip" "$cfg" "$FIXTURE_VERSION"
}

# ---------------------------------------------------------------------------
# Item 13, a ponta que o §5 destaca: pacote montado com árvore de origem
# correta, mas raiz do ZIP errada — a conferência roda sobre o zip
# desempacotado, não sobre a árvore de origem.
# ---------------------------------------------------------------------------

test_zip_com_raiz_diferente_da_origem_e_recusado() {
  local wd zip cfg root
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"

  # a árvore de ORIGEM está com o nome certo, mas o zip é montado colocando
  # o conteúdo dentro de uma pasta com outro nome — simula o empacotamento
  # que erra a raiz mesmo com a fonte correta.
  mkdir -p "$wd/embalagem-errada"
  mv "$root" "$wd/embalagem-errada/pasta-errada"
  zip="$wd/v3r-example-1.0.0.zip"
  ( cd "$wd/embalagem-errada" && zip -r -q -X "$zip" "pasta-errada" )
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "item 13"
}

# ---------------------------------------------------------------------------
# §6 — desinstalação e changelog (padrão de fábrica: exige)
# ---------------------------------------------------------------------------

test_secao6_uninstall_ausente() {
  local wd zip cfg root
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  rm -f "$root/uninstall.php"
  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "§6 (arquivo de desinstalação)"
}

test_secao6_uninstall_nao_exigido_passa() {
  local wd zip cfg root
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  rm -f "$root/uninstall.php"
  sed -i 's/RELEASE_REQUIRE_UNINSTALL=true/RELEASE_REQUIRE_UNINSTALL=false/' "$cfg"
  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_aprovado "$zip" "$cfg" "$FIXTURE_VERSION"
}

test_secao6_changelog_desatualizado() {
  local wd zip cfg root
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  sed -i 's/## 1.0.0/## 0.9.0/' "$root/CHANGELOG.md"
  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"
  assert_recusado "$zip" "$cfg" "$FIXTURE_VERSION" "§6 (changelog em dia)"
}

# ---------------------------------------------------------------------------
# Comportamento de --all
# ---------------------------------------------------------------------------

test_all_lista_tres_recusas() {
  local wd zip cfg root cfg2
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  cfg2="$wd/release.config.with-extra-required.sh"
  cp "$cfg" "$cfg2"
  cat >> "$cfg2" <<'EOF'
RELEASE_REQUIRED_PATHS=(
  "readme.txt"
  "v3r-example.php"
  "LICENSE.txt"
)
EOF
  # três defeitos independentes: item 12 (LICENSE.txt ausente), item 14
  # (node_modules presente) e item 15 (diretório sem travessia).
  mkdir -p "$root/node_modules"
  echo "{}" > "$root/node_modules/package.json"
  chmod 700 "$root/assets/build"

  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"

  roda_verify --all --expected-version "$FIXTURE_VERSION" "$zip" "$cfg2"
  if [ "$RC" -eq 0 ]; then
    fail "esperava recusa em --all. Saída:
$OUT"
    return
  fi
  local n
  n="$(grep -c '^RECUSADO' <<<"$OUT")"
  if [ "$n" -ne 3 ]; then
    fail "esperava 3 recusas listadas, vieram $n. Saída:
$OUT"
    return
  fi
  ok
}

test_sem_all_para_na_primeira() {
  local wd zip cfg root cfg2
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  root="$wd/$FIXTURE_SLUG"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  cfg2="$wd/release.config.with-extra-required.sh"
  cp "$cfg" "$cfg2"
  cat >> "$cfg2" <<'EOF'
RELEASE_REQUIRED_PATHS=(
  "readme.txt"
  "v3r-example.php"
  "LICENSE.txt"
)
EOF
  mkdir -p "$root/node_modules"
  echo "{}" > "$root/node_modules/package.json"
  chmod 700 "$root/assets/build"

  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"

  roda_verify --expected-version "$FIXTURE_VERSION" "$zip" "$cfg2"
  if [ "$RC" -eq 0 ]; then
    fail "esperava recusa. Saída:
$OUT"
    return
  fi
  local n
  n="$(grep -c '^RECUSADO' <<<"$OUT")"
  if [ "$n" -ne 1 ]; then
    fail "sem --all esperava parar na primeira recusa (1), vieram $n. Saída:
$OUT"
    return
  fi
  ok
}

# ---------------------------------------------------------------------------
# Limpeza do temporário mesmo em erro
# ---------------------------------------------------------------------------

test_limpa_temporario_mesmo_em_recusa() {
  local wd zip cfg antes depois
  wd="$(work_dir)"
  ALL_WORKDIRS+=("$wd")
  build_baseline_fixture "$wd"
  cfg="$wd/release.config.sh"
  baseline_config "$cfg"
  sed -i 's/ \* Version: 1.0.0/ * Version:/' "$wd/$FIXTURE_SLUG/v3r-example.php"
  zip="$wd/v3r-example-1.0.0.zip"
  zip_fixture "$wd" "$FIXTURE_SLUG" "$FIXTURE_VERSION" "$zip"

  antes="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'v3r-release.*' 2>/dev/null | wc -l)"
  "$VERIFY" --expected-version "$FIXTURE_VERSION" "$zip" "$cfg" >/dev/null 2>&1
  depois="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'v3r-release.*' 2>/dev/null | wc -l)"

  if [ "$depois" -ne "$antes" ]; then
    fail "sobrou diretório temporário do v3r-release depois da recusa"
    return
  fi
  ok
}

# ---------------------------------------------------------------------------
# Execução
# ---------------------------------------------------------------------------

run_test test_baseline_aprova
run_test test_secao3_versao_da_peca_diferente
run_test test_item1_versao_cabecalho_ilegivel
run_test test_item2_versao_diferente_da_esperada
run_test test_item3_versao_extra_diverge
run_test test_item4_artefato_sem_manifesto
run_test test_item5_arquivo_enfileirado_ausente
run_test test_item6_biblioteca_prefixada_ausente
run_test test_item7_classe_original_ainda_resolve
run_test test_item8_componente_nas_duas_arvores_com_conteudo
run_test test_item8_diretorio_cru_vazio_e_correto
run_test test_item9_classmap_aponta_para_arquivo_inexistente
run_test test_item10_texto_nao_prefixado_escapou
run_test test_item10_grafia_prefixada_correta_passa
run_test test_item10_grafia_escapada_sem_prefixo_e_recusada
run_test test_item10_classmap_gerado_fica_de_fora_da_checagem
run_test test_item10_nome_original_em_comentario_e_docblock_passa
run_test test_item10_nome_original_em_heredoc_e_recusado
run_test test_item10_arquivo_que_nao_tokeniza_e_recusado
run_test test_item11_arquivo_de_dados_ausente
run_test test_item12_caminho_obrigatorio_ausente
run_test test_item13_pasta_raiz_errada
run_test test_item14_fonte_de_desenvolvimento_presente
run_test test_item15_diretorio_sem_travessia
run_test test_item20_versao_bate_com_a_esperada_aprova
run_test test_item20_versao_diverge_da_esperada_e_recusada
run_test test_item20_sem_expected_lib_version_e_recusado
run_test test_item20_sem_declaracao_nao_afeta_pacote_correto
run_test test_zip_com_raiz_diferente_da_origem_e_recusado
run_test test_secao6_uninstall_ausente
run_test test_secao6_uninstall_nao_exigido_passa
run_test test_secao6_changelog_desatualizado
run_test test_all_lista_tres_recusas
run_test test_sem_all_para_na_primeira
run_test test_limpa_temporario_mesmo_em_recusa

echo ""
echo "$TESTS_RUN teste(s) rodado(s), $TESTS_FAILED falha(s)."
[ "$TESTS_FAILED" -eq 0 ]

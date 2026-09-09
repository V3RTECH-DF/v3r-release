#!/usr/bin/env bash
# verify-package.sh — a conferência do pacote montado (itens 1 a 15 e 20 do §5
# do contrato). Ver docs/contrato.md e docs/declaracao.md.
#
# Uso:
#   bin/verify-package.sh [--all] <pacote.zip> <release.config.sh>
#
# Sai com código diferente de zero na PRIMEIRA recusa (padrão), dizendo qual
# conferência recusou e o que encontrou. Com --all, continua e lista todas as
# recusas em vez de parar na primeira.
#
# Nunca escreve nada fora de um diretório temporário, que é limpo na saída —
# inclusive em erro (trap EXIT).

set -euo pipefail

# ---------------------------------------------------------------------------
# Argumentos
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
TOOLING_ROOT="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P)"

uso() {
  cat >&2 <<'EOF'
Uso: verify-package.sh [--all] --expected-version <versão>
       [--expected-lib-version <slug>=<versão> ...] <pacote.zip> <release.config.sh>

  --all                  não para na primeira recusa: roda todas as
                         conferências e lista todas as recusas encontradas.
  --expected-version <v> a versão que se PRETENDE publicar com este pacote —
                         obrigatório. É contra ela, não contra o nome do
                         arquivo .zip, que o item 2 confere o cabeçalho: a
                         convenção de nome de zip não existe entre os
                         produtos da casa, e deduzir do nome seria circular
                         (quem nomeia o zip é a mesma receita que confere).
  --expected-lib-version <slug>=<v>
                         a versão que se ESPERA que a biblioteca prefixada
                         <slug> tenha embutido — repetível, uma vez por
                         biblioteca declarada em RELEASE_LIBRARY_VERSION_FILES
                         (item 20 do §5). Quem decide o valor é quem monta o
                         build (tipicamente lendo o composer.lock ANTES de
                         empacotar) — nunca um número mantido à mão aqui.
EOF
}

ALL_MODE=false
EXPECTED_VERSION=""
declare -A EXPECTED_LIB_VERSIONS=()
ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --all) ALL_MODE=true; shift ;;
    --expected-version)
      if [ "$#" -lt 2 ]; then
        echo "erro: --expected-version exige um valor" >&2
        uso
        exit 2
      fi
      EXPECTED_VERSION="$2"
      shift 2
      ;;
    --expected-lib-version)
      if [ "$#" -lt 2 ]; then
        echo "erro: --expected-lib-version exige um valor no formato slug=versão" >&2
        uso
        exit 2
      fi
      _elv="$2"
      _elv_slug="${_elv%%=*}"
      if [ -z "$_elv_slug" ] || [ "$_elv_slug" = "$_elv" ]; then
        echo "erro: --expected-lib-version espera o formato slug=versão (recebi '$_elv')" >&2
        uso
        exit 2
      fi
      EXPECTED_LIB_VERSIONS["$_elv_slug"]="${_elv#*=}"
      unset _elv _elv_slug
      shift 2
      ;;
    -h|--help) uso; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

if [ "${#ARGS[@]}" -ne 2 ]; then
  echo "erro: são esperados exatamente dois argumentos posicionais (pacote e declaração)" >&2
  uso
  exit 2
fi

# Falha fechada: sem a versão esperada, o item 2 não tem contra o que
# conferir, e um script que se pula sozinho não pega o que existe para pegar
# (publicar uma coisa dizendo que é outra).
if [ -z "$EXPECTED_VERSION" ]; then
  echo "erro: --expected-version é obrigatório" >&2
  uso
  exit 2
fi

PACKAGE="${ARGS[0]}"
CONFIG="${ARGS[1]}"

if [ ! -f "$PACKAGE" ]; then
  echo "erro: pacote não encontrado: $PACKAGE" >&2
  exit 2
fi
if [ ! -f "$CONFIG" ]; then
  echo "erro: declaração não encontrada: $CONFIG" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Valores de fábrica dos campos da declaração — o `source` abaixo sobrescreve
# só o que o produto de fato declarar. Isso é o que permite `set -u` sem que
# um campo opcional não declarado derrube o script.
# ---------------------------------------------------------------------------

RELEASE_PRODUCT_SLUG=""
RELEASE_TOOLING_VERSION=""

RELEASE_VERSION_HEADER_FILE=""
RELEASE_VERSION_HEADER_REGEX=""
RELEASE_VERSION_EXTRA_FILES=()

RELEASE_FRONT_ARTIFACTS=()
RELEASE_FRONT_ENQUEUED_FILES=()

RELEASE_PREFIXED_LIBS=()
RELEASE_AUTOLOAD_FILE=""
RELEASE_CLASSMAP_FILES=()
RELEASE_LIBRARY_VERSION_FILES=()

RELEASE_RUNTIME_DATA_FILES=()
RELEASE_REQUIRED_PATHS=()
RELEASE_FORBIDDEN_DEV_PATHS=()

# (declarados só para o produto expor RELEASE_TEST_CMD/RELEASE_LINT_CMD à
# fatia futura que rodará os itens 16 e 17 — não são usados aqui.)
# shellcheck disable=SC2034
RELEASE_TEST_CMD=""
# shellcheck disable=SC2034
RELEASE_LINT_CMD=""

RELEASE_REQUIRE_UNINSTALL=true
RELEASE_UNINSTALL_FILE="uninstall.php"
RELEASE_REQUIRE_CHANGELOG_UPTODATE=true
RELEASE_CHANGELOG_FILE="CHANGELOG.md"
RELEASE_CHANGELOG_VERSION_REGEX=""

# shellcheck source=/dev/null
source "$CONFIG"

if [ -z "$RELEASE_PRODUCT_SLUG" ] || [ -z "$RELEASE_VERSION_HEADER_FILE" ] || [ -z "$RELEASE_VERSION_HEADER_REGEX" ]; then
  echo "erro: declaração incompleta — RELEASE_PRODUCT_SLUG, RELEASE_VERSION_HEADER_FILE e RELEASE_VERSION_HEADER_REGEX são obrigatórios" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Preparação: diretório temporário e desempacotamento
# ---------------------------------------------------------------------------

TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/v3r-release.XXXXXX")"
# shellcheck disable=SC2329
# (chamada indiretamente pelo trap, não por invocação direta)
cleanup() { rm -rf -- "$TMPDIR"; }
trap cleanup EXIT

if ! unzip -q -- "$PACKAGE" -d "$TMPDIR"; then
  echo "erro: não foi possível desempacotar $PACKAGE" >&2
  exit 2
fi

# O pacote precisa ter exatamente UMA pasta raiz (é essa pasta que o item 13
# compara com o identificador do produto). Mais de uma entrada no nível
# superior, ou uma entrada que não seja diretório, não é uma estrutura de
# plugin WordPress válida — é erro de montagem, não uma das conferências
# numeradas do §5, então aborta cedo com código de uso.
mapfile -d '' -t TOP_ENTRIES < <(find "$TMPDIR" -mindepth 1 -maxdepth 1 -print0)
if [ "${#TOP_ENTRIES[@]}" -ne 1 ] || [ ! -d "${TOP_ENTRIES[0]}" ]; then
  echo "erro: o pacote não tem uma única pasta raiz — não dá para conferir" >&2
  exit 2
fi
PKG_ROOT="${TOP_ENTRIES[0]}"
PKG_ROOT_NAME="$(basename -- "$PKG_ROOT")"

# ---------------------------------------------------------------------------
# Coleta de recusas
# ---------------------------------------------------------------------------

FAILURES=()

recusa() {
  local msg="$1"
  FAILURES+=("$msg")
  echo "RECUSADO — $msg" >&2
  if [ "$ALL_MODE" != true ]; then
    exit 1
  fi
}

# Extrai, com grep -P e a convenção "\K" (ver docs/declaracao.md), o texto da
# versão de um arquivo. Vazio (arquivo sem match) é diferença observável, não
# erro de shell — quem chama decide o que fazer com uma extração vazia.
extrai_versao() {
  local arquivo="$1" regex="$2"
  grep -oP -m1 -- "$regex" "$arquivo" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# §3 do contrato — versão da própria peça
# ---------------------------------------------------------------------------

check_versao_da_peca() {
  local local_version
  local_version="$(tr -d '[:space:]' < "$TOOLING_ROOT/VERSION" 2>/dev/null)" || true
  if [ -n "$RELEASE_TOOLING_VERSION" ] && [ "$RELEASE_TOOLING_VERSION" != "$local_version" ]; then
    recusa "versão do v3r-release (§3): a cópia local é $local_version, mas $RELEASE_PRODUCT_SLUG espera $RELEASE_TOOLING_VERSION — atualize o v3r-release antes de empacotar"
    return
  fi
}

# ---------------------------------------------------------------------------
# Item 1 e 2 — versão do cabeçalho
# ---------------------------------------------------------------------------

check_item_1_2_versao_cabecalho() {
  local header_path="$PKG_ROOT/$RELEASE_VERSION_HEADER_FILE"
  if [ ! -f "$header_path" ]; then
    recusa "item 1 (versão do cabeçalho): $RELEASE_VERSION_HEADER_FILE não existe no pacote"
    return
  fi

  local versao
  versao="$(extrai_versao "$header_path" "$RELEASE_VERSION_HEADER_REGEX")"
  if [ -z "$versao" ]; then
    recusa "item 1 (versão do cabeçalho): $RELEASE_VERSION_HEADER_FILE não tem versão legível (regex declarada não casou)"
    return
  fi

  # Item 2: a versão do cabeçalho contra a versão que se PRETENDE publicar,
  # recebida como --expected-version. Não há convenção de nome de arquivo
  # .zip entre os produtos da casa (um usa "<slug>-<versão>.zip", outro
  # "<slug>-v<versão>.zip") — deduzir do nome também seria circular, porque
  # quem nomeia o zip é a mesma receita que confere. Ver docs/declaracao.md.
  if [ "$versao" != "$EXPECTED_VERSION" ]; then
    recusa "item 2 (versão do cabeçalho x versão esperada): o cabeçalho diz $versao, mas --expected-version pediu $EXPECTED_VERSION"
    return
  fi
}

# ---------------------------------------------------------------------------
# Item 3 — outros pontos onde a versão precisa concordar
# ---------------------------------------------------------------------------

check_item_3_versao_extra() {
  local header_path="$PKG_ROOT/$RELEASE_VERSION_HEADER_FILE"
  local versao_cabecalho
  versao_cabecalho="$(extrai_versao "$header_path" "$RELEASE_VERSION_HEADER_REGEX")"
  [ -n "$versao_cabecalho" ] || return 0  # já recusado pelo item 1

  local entrada caminho regex versao
  for entrada in "${RELEASE_VERSION_EXTRA_FILES[@]:-}"; do
    [ -n "$entrada" ] || continue
    caminho="${entrada%%|*}"
    regex="${entrada#*|}"
    local alvo="$PKG_ROOT/$caminho"
    if [ ! -f "$alvo" ]; then
      recusa "item 3 (versão em $caminho): arquivo não existe no pacote"
      continue
    fi
    versao="$(extrai_versao "$alvo" "$regex")"
    if [ -z "$versao" ]; then
      recusa "item 3 (versão em $caminho): não achei versão legível com a regex declarada"
      continue
    fi
    if [ "$versao" != "$versao_cabecalho" ]; then
      recusa "item 3 (versão em $caminho): diz $versao, mas o cabeçalho diz $versao_cabecalho"
    fi
  done
}

# ---------------------------------------------------------------------------
# Item 4 — artefatos de front compilados
# ---------------------------------------------------------------------------

check_item_4_artefatos_front() {
  local entrada dir manifest alvo_dir alvo_manifest conteudo
  for entrada in "${RELEASE_FRONT_ARTIFACTS[@]:-}"; do
    [ -n "$entrada" ] || continue
    dir="${entrada%%|*}"
    manifest="${entrada#*|}"
    alvo_dir="$PKG_ROOT/$dir"
    alvo_manifest="$PKG_ROOT/$manifest"

    if [ ! -d "$alvo_dir" ]; then
      recusa "item 4 (artefato de front): diretório $dir não existe no pacote"
      continue
    fi
    conteudo="$(find "$alvo_dir" -mindepth 1 -print -quit 2>/dev/null)" || true
    if [ -z "$conteudo" ]; then
      recusa "item 4 (artefato de front): diretório $dir está vazio"
      continue
    fi
    if [ ! -f "$alvo_manifest" ]; then
      recusa "item 4 (artefato de front): manifesto $manifest não existe"
    fi
  done
}

# ---------------------------------------------------------------------------
# Item 5 — arquivos de front que o PHP enfileira
# ---------------------------------------------------------------------------

check_item_5_front_enfileirado() {
  local caminho
  for caminho in "${RELEASE_FRONT_ENQUEUED_FILES[@]:-}"; do
    [ -n "$caminho" ] || continue
    if [ ! -f "$PKG_ROOT/$caminho" ]; then
      recusa "item 5 (arquivo enfileirado pelo PHP): $caminho não existe no pacote"
    fi
  done
}

# ---------------------------------------------------------------------------
# Itens 6 a 10 — bibliotecas de terceiro prefixadas
# ---------------------------------------------------------------------------

# Resolve, via o autoload do pacote, se uma classe existe. Roda um processo
# PHP isolado por classe: barato o bastante para o número de bibliotecas que
# um plugin costuma prefixar, e evita que o require de uma classe vaze estado
# para a checagem seguinte.
php_class_existe() {
  local autoload="$1" classe="$2"
  [ -f "$autoload" ] || return 1
  # shellcheck disable=SC2016
  # (aspas simples são deliberadas: é código PHP, não deve expandir no shell)
  php -r '
    $autoload = $argv[1];
    $classe = $argv[2];
    require $autoload;
    exit(class_exists($classe) || interface_exists($classe) || trait_exists($classe) ? 0 : 1);
  ' -- "$autoload" "$classe" 2>/dev/null
}

# Duplica cada barra invertida de um texto. Usada duas vezes, com propósitos
# que colapsam na MESMA operação: (a) construir a grafia "escapada" que um
# namespace ganha dentro de uma string PHP entre aspas (cada "\" do texto
# vira "\\" no arquivo); (b) escapar backslash para virar literal dentro de
# um regex PCRE (cada "\" do texto buscado também precisa virar "\\" no
# padrão). Aplicar duas vezes sobre o nome original dá o padrão PCRE que
# casa a grafia escapada.
dobra_barra() {
  printf '%s' "${1//\\/\\\\}"
}

# extrai_literais <arquivo> <regex-pcre>
# Tokeniza <arquivo> com o tokenizador do próprio PHP (token_get_all com a
# flag TOKEN_PARSE, que faz um arquivo malformado LANÇAR erro em vez de
# devolver tokens incompletos em silêncio) e imprime, um por linha, cada
# ocorrência de <regex-pcre> encontrada DENTRO de:
#   - T_CONSTANT_ENCAPSED_STRING — literal de string ('...' ou "...");
#   - T_ENCAPSED_AND_WHITESPACE  — conteúdo de heredoc/nowdoc (é dado, do
#     mesmo jeito que uma string entre aspas; a delimitação (<<<EOT) e o
#     nome de classe usado como código ficam em tokens diferentes).
# Nunca em T_COMMENT, T_DOC_COMMENT, nem no nome de classe usado como
# código (`use Foo\Bar;`, `new Foo\Bar()`, `Foo\Bar::class`), que o PHP
# tokeniza como T_NAME_QUALIFIED/T_STRING — a ferramenta de prefixação já
# reescreve esses tokens; só o dado dentro de literal escapa dela.
#
# Retorno: 0 e a lista de ocorrências (pode ser vazia) em stdout. Não-zero
# e a mensagem de erro em stdout (para quem chama poder citá-la na recusa)
# quando o arquivo não tokeniza — arquivo ilegível ou PHP malformado.
extrai_literais() {
  local arquivo="$1" regex="$2"
  # shellcheck disable=SC2016
  # (aspas simples são deliberadas: é código PHP, não deve expandir no shell)
  php -r '
    $arquivo = $argv[1];
    $regex = $argv[2];

    $fonte = @file_get_contents($arquivo);
    if ($fonte === false) {
      echo "não foi possível ler o arquivo";
      exit(1);
    }

    try {
      $tokens = token_get_all($fonte, TOKEN_PARSE);
    } catch (\ParseError $e) {
      echo $e->getMessage();
      exit(1);
    }

    $padrao = "/" . $regex . "/";
    foreach ($tokens as $tok) {
      if (!is_array($tok)) {
        continue;
      }
      [$id, $texto] = $tok;
      if ($id !== T_CONSTANT_ENCAPSED_STRING && $id !== T_ENCAPSED_AND_WHITESPACE) {
        continue;
      }
      if (preg_match_all($padrao, $texto, $m)) {
        foreach ($m[0] as $ocorrencia) {
          echo $ocorrencia . "\n";
        }
      }
    }
    exit(0);
  ' -- "$arquivo" "$regex"
}

check_itens_6_a_10_bibliotecas_prefixadas() {
  local entrada slug dir_cru dir_prefixado classe_original classe_prefixada
  local alvo_cru alvo_prefixado autoload_path

  autoload_path="$PKG_ROOT/$RELEASE_AUTOLOAD_FILE"

  for entrada in "${RELEASE_PREFIXED_LIBS[@]:-}"; do
    [ -n "$entrada" ] || continue
    IFS='|' read -r slug dir_cru dir_prefixado classe_original classe_prefixada <<<"$entrada"

    alvo_cru="$PKG_ROOT/$dir_cru"
    alvo_prefixado="$PKG_ROOT/$dir_prefixado"

    # Item 6: a biblioteca PREFIXADA (a que o produto de fato usa em
    # produção) precisa estar presente e não vazia.
    if [ ! -d "$alvo_prefixado" ] || [ -z "$(find "$alvo_prefixado" -mindepth 1 -print -quit)" ]; then
      recusa "item 6 ($slug ausente): $dir_prefixado não existe ou está vazio no pacote"
      continue
    fi

    # Item 7, duas pontas: a classe prefixada tem que resolver, E a classe
    # original NÃO pode resolver. Testar só a primeira ponta aprovaria um
    # autoload que carrega os dois nomes — prefixação pela metade, que colide
    # com outro plugin da casa no mesmo site.
    if [ -n "$classe_prefixada" ] && [ -n "$RELEASE_AUTOLOAD_FILE" ]; then
      if ! php_class_existe "$autoload_path" "$classe_prefixada"; then
        recusa "item 7 ($slug): a classe prefixada $classe_prefixada não resolve pelo autoload do pacote"
      fi
      if [ -n "$classe_original" ] && php_class_existe "$autoload_path" "$classe_original"; then
        recusa "item 7 ($slug): a classe original $classe_original AINDA resolve — a prefixação está pela metade"
      fi
    fi

    # Item 8: o mesmo componente presente nas duas árvores. ⚠️ A ferramenta
    # de prefixação (Strauss) deixa o diretório cru VAZIO para trás — não o
    # remove. Um pacote correto TEM esse diretório, só que vazio. Por isso
    # a conferência aqui é sobre CONTEÚDO: existência do diretório cru,
    # sozinha, é o comportamento esperado e não pode reprovar nada.
    if [ -d "$alvo_cru" ] && [ -n "$(find "$alvo_cru" -mindepth 1 -print -quit)" ]; then
      recusa "item 8 ($slug nas duas árvores): $dir_cru ainda tem conteúdo — deveria estar vazio (só a prefixada em $dir_prefixado é a cópia real)"
    fi
  done

  # Item 9: cada classe do mapa de classes precisa resolver para um arquivo
  # que exista de verdade. O classmap é requerido a partir de DENTRO do
  # pacote desempacotado, para que os caminhos relativos que o Composer
  # grava (baseados em __DIR__ no momento do require) apontem para os
  # arquivos que de fato viajaram no zip — e não para onde a biblioteca
  # estava quando o classmap foi gerado.
  local classmap_rel classmap_path
  for classmap_rel in "${RELEASE_CLASSMAP_FILES[@]:-}"; do
    [ -n "$classmap_rel" ] || continue
    classmap_path="$PKG_ROOT/$classmap_rel"
    if [ ! -f "$classmap_path" ]; then
      recusa "item 9 (mapa de classes): $classmap_rel não existe no pacote"
      continue
    fi
    local faltando
    # shellcheck disable=SC2016
    # (aspas simples são deliberadas: é código PHP, não deve expandir no shell)
    faltando="$(php -r '
      $mapa = require $argv[1];
      if (!is_array($mapa)) { exit(0); }
      foreach ($mapa as $classe => $arquivo) {
        if (!is_file($arquivo)) {
          echo $classe . "\n";
        }
      }
    ' -- "$classmap_path" 2>/dev/null)" || true
    if [ -n "$faltando" ]; then
      while IFS= read -r classe; do
        [ -n "$classe" ] || continue
        recusa "item 9 (mapa de classes): $classe está no classmap de $classmap_rel mas o arquivo mapeado não existe"
      done <<<"$faltando"
    fi
  done

  # Item 10: nome de classe montado em TEXTO (string) que escapou da
  # prefixação. A ferramenta reescreve código (chamadas de classe, `use`,
  # `new X`), não dados — uma string literal com o namespace original,
  # concatenada em tempo de execução, passa batido por ela.
  #
  # ⚠️ Armadilha central: o nome PREFIXADO CONTÉM o nome ORIGINAL como
  # sufixo — `Rit360Solidario\Vendor\V3R\Core\Bootstrap` termina exatamente
  # em `V3R\Core\Bootstrap`. Buscar o nome original por substring, sem mais,
  # recusa todo pacote CORRETAMENTE prefixado: quanto mais certo o pacote,
  # mais recusas. A conferência certa é outra: uma ocorrência do nome
  # original só conta quando ela NÃO está precedida do prefixo declarado.
  # Cobre as duas grafias que aparecem em código PHP: a simples
  # (`V3R\Core\Bootstrap`) e a escapada (`V3R\\Core\\Bootstrap`, como o texto
  # aparece dentro de uma string entre aspas, onde a barra vem dobrada).
  #
  # ⚠️ Onde o defeito pode morar: SÓ dentro de literal de texto. A ferramenta
  # de prefixação reescreve código (nome de classe em `use`, `new X`,
  # `X::class`) e não reescreve dado — um nome de classe dentro de um
  # `// comentário` ou `/** docblock */` não carrega classe nenhuma, e um
  # nome em código já foi reescrito por ela. Buscar "em todo lugar menos
  # comentário" seria remendo; procurar DENTRO do literal é olhar exatamente
  # onde o problema vive. Por isso a conferência usa o tokenizador do
  # próprio PHP (já dependência declarada da peça) via `extrai_literais`,
  # e examina só T_CONSTANT_ENCAPSED_STRING (string literal) e
  # T_ENCAPSED_AND_WHITESPACE (conteúdo de heredoc/nowdoc, que é dado, não
  # código) — nunca T_COMMENT, T_DOC_COMMENT ou o nome de classe como
  # código (`use`, `T_NAME_QUALIFIED`).
  #
  # Isso é feito com alternação ORDENADA num único regex PCRE, sem
  # lookbehind (que exige largura fixa e complica sem necessidade): a
  # variante PREFIXADA de cada grafia vem ANTES da variante do nome
  # ORIGINAL puro. O motor de regex varre o texto da esquerda para a
  # direita e, em cada posição de início, tenta as alternativas na ordem
  # escrita — uma ocorrência prefixada corretamente casa inteira com a
  # alternativa mais longa a partir do início do prefixo, e o texto
  # consumido não é revisitado; só sobra para a alternativa "nome original
  # puro" a ocorrência que NÃO tem o prefixo completo na frente — que é
  # exatamente o vazamento que este item existe para pegar.
  #
  # Os arquivos GERADOS da árvore prefixada (o autoload do pacote e os
  # mapas de classe declarados) ficam de fora desta checagem: eles
  # legitimamente contêm o nome original como SUFIXO do nome prefixado
  # (ex.: o classmap do Composer/Strauss lista
  # `'Prefixo\Vendor\Mpdf\Mpdf' => ...`, e às vezes o original sozinho como
  # entrada de fallback) — são arquivo gerado, não código do produto; a
  # garantia de que cada entrada resolve para um arquivo existente já é o
  # item 9.
  local excluidos_gerados=()
  [ -n "$RELEASE_AUTOLOAD_FILE" ] && excluidos_gerados+=("$PKG_ROOT/$RELEASE_AUTOLOAD_FILE")
  local classmap_excl
  for classmap_excl in "${RELEASE_CLASSMAP_FILES[@]:-}"; do
    [ -n "$classmap_excl" ] && excluidos_gerados+=("$PKG_ROOT/$classmap_excl")
  done

  for entrada in "${RELEASE_PREFIXED_LIBS[@]:-}"; do
    [ -n "$entrada" ] || continue
    IFS='|' read -r slug dir_cru dir_prefixado classe_original classe_prefixada <<<"$entrada"
    [ -n "$classe_original" ] || continue

    local original_simples="$classe_original"
    local original_escapada
    original_escapada="$(dobra_barra "$classe_original")"
    local prefixada_simples="$classe_prefixada"
    local prefixada_escapada
    prefixada_escapada="$(dobra_barra "$classe_prefixada")"

    local pat_prefixada_simples pat_prefixada_escapada pat_original_simples pat_original_escapada
    pat_prefixada_simples="$(dobra_barra "$prefixada_simples")"
    pat_prefixada_escapada="$(dobra_barra "$prefixada_escapada")"
    pat_original_simples="$(dobra_barra "$original_simples")"
    pat_original_escapada="$(dobra_barra "$original_escapada")"

    local regex_alternado="${pat_prefixada_simples}|${pat_prefixada_escapada}|${pat_original_simples}|${pat_original_escapada}"

    # Arquivos candidatos: contêm qualquer uma das quatro grafias EM QUALQUER
    # LUGAR do arquivo (pré-filtro barato por texto bruto — comentário
    # inclusive), fora das árvores de origem (cru e prefixado, já cobertas
    # pelos itens 6 e 8) e fora dos arquivos gerados listados acima. Exclusão
    # por CAMINHO completo, não por nome de diretório: duas bibliotecas podem
    # compartilhar o mesmo nome de pasta final (ex.: "guzzle"). O filtro fino
    # — só literal de texto conta — é feito depois, arquivo por arquivo, pelo
    # tokenizador.
    local candidatos
    candidatos="$(grep -rlP -- "$regex_alternado" "$PKG_ROOT" 2>/dev/null \
      | grep -vF -- "/$dir_cru/" \
      | grep -vF -- "/$dir_prefixado/" || true)"
    if [ -n "$candidatos" ] && [ "${#excluidos_gerados[@]}" -gt 0 ]; then
      local excl
      for excl in "${excluidos_gerados[@]}"; do
        candidatos="$(printf '%s\n' "$candidatos" | grep -vxF -- "$excl" || true)"
      done
    fi

    # Por candidato, tokeniza o arquivo e confere se alguma ocorrência
    # extraída DE DENTRO DE UM LITERAL é o nome ORIGINAL puro (não consumido
    # por uma ocorrência prefixada maior) — só essa é o vazamento; a ordem
    # da alternação garante que uma ocorrência corretamente prefixada nunca
    # aparece como o nome original sozinho nesta extração.
    local achado=() arquivo matches match
    while IFS= read -r arquivo; do
      [ -n "$arquivo" ] || continue

      if ! matches="$(extrai_literais "$arquivo" "$regex_alternado")"; then
        recusa "item 10 ($slug): $arquivo não pôde ser analisado pelo tokenizador do PHP — pacote com PHP que não se analisa é pacote suspeito ($matches)"
        continue
      fi

      while IFS= read -r match; do
        [ -n "$match" ] || continue
        if [ "$match" = "$original_simples" ] || [ "$match" = "$original_escapada" ]; then
          achado+=("$arquivo")
          break
        fi
      done <<<"$matches"
    done <<<"$candidatos"

    if [ "${#achado[@]}" -gt 0 ]; then
      recusa "item 10 ($slug, texto não prefixado): o nome $classe_original aparece dentro de um literal de texto fora das árvores de origem, em: ${achado[*]}"
    fi
  done
}

# ---------------------------------------------------------------------------
# Item 20 — versão embutida de biblioteca prefixada (V3RCore-Code#44)
#
# O guard das itens 6–10 confere que a biblioteca CHEGOU ao pacote — nunca
# QUAL versão chegou. Um composer.lock desatualizado (de outra máquina, de
# uma sincronização) faz o empacotamento embutir uma versão antiga em
# silêncio: os itens 6–10 continuam passando, porque a árvore prefixada
# existe e resolve — só que é a árvore de uma versão mais velha do que a
# publicação pretende.
#
# Cada entrada de RELEASE_LIBRARY_VERSION_FILES aponta, DENTRO do diretório
# prefixado já declarado em RELEASE_PREFIXED_LIBS (mesmo slug), o arquivo e a
# regex que expõem a versão da biblioteca em tempo de execução. O valor
# esperado NUNCA vem daqui — vem de --expected-lib-version, passado por quem
# monta o build (tipicamente lido do composer.lock um instante antes de
# empacotar): falha fechada, mesma lógica do item 2 com --expected-version.
# ---------------------------------------------------------------------------

check_item_20_versao_biblioteca_prefixada() {
  local entrada slug resto arquivo_rel regex
  for entrada in "${RELEASE_LIBRARY_VERSION_FILES[@]:-}"; do
    [ -n "$entrada" ] || continue
    slug="${entrada%%|*}"
    resto="${entrada#*|}"
    arquivo_rel="${resto%%|*}"
    regex="${resto#*|}"

    # Acha o diretório prefixado já declarado para este slug em
    # RELEASE_PREFIXED_LIBS — não duplica a informação, só referencia pelo
    # mesmo identificador (slug|dir_cru|dir_prefixado|classe_original|classe_prefixada).
    local dir_prefixado="" pl_entrada pl_slug pl_resto
    for pl_entrada in "${RELEASE_PREFIXED_LIBS[@]:-}"; do
      pl_slug="${pl_entrada%%|*}"
      if [ "$pl_slug" = "$slug" ]; then
        pl_resto="${pl_entrada#*|}"   # dir_cru|dir_prefixado|classe_original|classe_prefixada
        pl_resto="${pl_resto#*|}"     # dir_prefixado|classe_original|classe_prefixada
        dir_prefixado="${pl_resto%%|*}"
        break
      fi
    done
    if [ -z "$dir_prefixado" ]; then
      recusa "item 20 (versão da biblioteca $slug): RELEASE_LIBRARY_VERSION_FILES cita '$slug', mas não há entrada correspondente em RELEASE_PREFIXED_LIBS"
      continue
    fi

    local alvo="$PKG_ROOT/$dir_prefixado/$arquivo_rel"
    if [ ! -f "$alvo" ]; then
      recusa "item 20 (versão da biblioteca $slug): $dir_prefixado/$arquivo_rel não existe no pacote"
      continue
    fi

    local versao_embutida
    versao_embutida="$(extrai_versao "$alvo" "$regex")"
    if [ -z "$versao_embutida" ]; then
      recusa "item 20 (versão da biblioteca $slug): não achei versão legível em $dir_prefixado/$arquivo_rel com a regex declarada"
      continue
    fi

    if [ -z "${EXPECTED_LIB_VERSIONS[$slug]+_}" ]; then
      recusa "item 20 (versão da biblioteca $slug): a declaração pede conferência, mas --expected-lib-version $slug=<versão> não foi passado (falha fechada)"
      continue
    fi

    local esperada="${EXPECTED_LIB_VERSIONS[$slug]}"
    if [ "$versao_embutida" != "$esperada" ]; then
      recusa "item 20 (versão da biblioteca $slug): o pacote traz $versao_embutida, mas o build esperava $esperada"
    fi
  done
}

# ---------------------------------------------------------------------------
# Item 11 — arquivos de dados lidos em runtime
# ---------------------------------------------------------------------------

check_item_11_dados_runtime() {
  local caminho
  for caminho in "${RELEASE_RUNTIME_DATA_FILES[@]:-}"; do
    [ -n "$caminho" ] || continue
    if [ ! -f "$PKG_ROOT/$caminho" ]; then
      recusa "item 11 (arquivo de dados em runtime): $caminho não viajou no pacote"
    fi
  done
}

# ---------------------------------------------------------------------------
# Item 12 — caminhos obrigatórios
# ---------------------------------------------------------------------------

check_item_12_caminhos_obrigatorios() {
  local caminho
  for caminho in "${RELEASE_REQUIRED_PATHS[@]:-}"; do
    [ -n "$caminho" ] || continue
    if [ ! -e "$PKG_ROOT/$caminho" ]; then
      recusa "item 12 (caminho obrigatório): $caminho não está no pacote"
    fi
  done
}

# ---------------------------------------------------------------------------
# Item 13 — pasta raiz do pacote
# ---------------------------------------------------------------------------

check_item_13_pasta_raiz() {
  if [ "$PKG_ROOT_NAME" != "$RELEASE_PRODUCT_SLUG" ]; then
    recusa "item 13 (pasta raiz): o pacote traz a pasta '$PKG_ROOT_NAME', mas o identificador do produto é '$RELEASE_PRODUCT_SLUG' — o servidor de licenças recusaria o envio"
  fi
}

# ---------------------------------------------------------------------------
# Item 14 — fonte de desenvolvimento dentro do pacote
# ---------------------------------------------------------------------------

check_item_14_fonte_dev() {
  local caminho
  for caminho in "${RELEASE_FORBIDDEN_DEV_PATHS[@]:-}"; do
    [ -n "$caminho" ] || continue
    if [ -e "$PKG_ROOT/$caminho" ]; then
      recusa "item 14 (fonte de desenvolvimento): $caminho não deveria estar no pacote"
    fi
  done
}

# ---------------------------------------------------------------------------
# Item 15 — diretório sem permissão de travessia
# ---------------------------------------------------------------------------

check_item_15_permissao_travessia() {
  local sem_permissao
  sem_permissao="$(find "$PKG_ROOT" -type d ! -perm -o+x 2>/dev/null)" || true
  if [ -n "$sem_permissao" ]; then
    while IFS= read -r dir; do
      [ -n "$dir" ] || continue
      recusa "item 15 (permissão de travessia): ${dir#"$PKG_ROOT"/} não tem bit de execução para 'outros' — o servidor web não consegue entrar"
    done <<<"$sem_permissao"
  fi
}

# ---------------------------------------------------------------------------
# §6 — convenções que o produto pode exigir (padrão de fábrica: exige)
# ---------------------------------------------------------------------------

check_secao_6_desinstalacao() {
  [ "$RELEASE_REQUIRE_UNINSTALL" = "true" ] || return 0
  if [ ! -f "$PKG_ROOT/$RELEASE_UNINSTALL_FILE" ]; then
    recusa "§6 (arquivo de desinstalação): $RELEASE_UNINSTALL_FILE exigido pela declaração, mas ausente do pacote"
  fi
}

check_secao_6_changelog() {
  [ "$RELEASE_REQUIRE_CHANGELOG_UPTODATE" = "true" ] || return 0

  local header_path="$PKG_ROOT/$RELEASE_VERSION_HEADER_FILE"
  local versao_cabecalho
  versao_cabecalho="$(extrai_versao "$header_path" "$RELEASE_VERSION_HEADER_REGEX")"
  [ -n "$versao_cabecalho" ] || return 0  # já recusado pelo item 1

  local changelog_path="$PKG_ROOT/$RELEASE_CHANGELOG_FILE"
  if [ ! -f "$changelog_path" ]; then
    recusa "§6 (changelog em dia): $RELEASE_CHANGELOG_FILE exigido pela declaração, mas ausente do pacote"
    return
  fi

  if [ -z "$RELEASE_CHANGELOG_VERSION_REGEX" ]; then
    recusa "§6 (changelog em dia): RELEASE_CHANGELOG_VERSION_REGEX não foi declarada, não dá para conferir"
    return
  fi

  if ! grep -qP -m1 -- "$RELEASE_CHANGELOG_VERSION_REGEX" "$changelog_path" 2>/dev/null; then
    recusa "§6 (changelog em dia): $RELEASE_CHANGELOG_FILE não tem nenhuma versão reconhecível pela regex declarada"
    return
  fi

  local primeira_versao
  primeira_versao="$(extrai_versao "$changelog_path" "$RELEASE_CHANGELOG_VERSION_REGEX")"
  if [ "$primeira_versao" != "$versao_cabecalho" ]; then
    recusa "§6 (changelog em dia): a primeira entrada do changelog é $primeira_versao, mas a versão publicada é $versao_cabecalho"
  fi
}

# ---------------------------------------------------------------------------
# Ordem de execução
# ---------------------------------------------------------------------------

check_versao_da_peca
check_item_1_2_versao_cabecalho
check_item_3_versao_extra
check_item_4_artefatos_front
check_item_5_front_enfileirado
check_itens_6_a_10_bibliotecas_prefixadas
check_item_20_versao_biblioteca_prefixada
check_item_11_dados_runtime
check_item_12_caminhos_obrigatorios
check_item_13_pasta_raiz
check_item_14_fonte_dev
check_item_15_permissao_travessia
check_secao_6_desinstalacao
check_secao_6_changelog

if [ "${#FAILURES[@]}" -gt 0 ]; then
  echo "" >&2
  echo "${#FAILURES[@]} conferência(s) recusada(s)." >&2
  exit 1
fi

echo "Pacote conforme: todas as conferências passaram."
exit 0

#!/usr/bin/env bash
# shellcheck disable=SC2034
# (arquivo de declaração puro: toda variável é consumida por quem faz
# `source` deste arquivo — bin/verify-package.sh — não por ele mesmo.)
#
# release.config.sh — exemplo de declaração de um produto para o v3r-release.
#
# Este arquivo mora no repositório de CÓDIGO do produto (nunca no de gestão —
# o robô do GitHub não clona o de gestão). É `source`-ado por
# `bin/verify-package.sh`; portanto é shell puro, sem processo externo, sem
# efeito colateral, só atribuição de variáveis e arrays.
#
# Convenção dos arrays com múltiplos campos por entrada: os campos são
# separados por "|" (pipe), porque nenhum caminho de arquivo do WordPress usa
# esse caractere. Não use "|" em nome de arquivo.
#
# Todo caminho declarado aqui é RELATIVO À RAIZ DO PACOTE (o diretório que tem
# o mesmo nome do produto, dentro do zip) — nunca à raiz do repositório.
#
# Toda regex de versão é PCRE (grep -P) e usa "\K" para marcar onde o texto
# da versão COMEÇA — sem grupo de captura. Ex.: "Version: *\K[0-9.]+" casa a
# linha inteira mas devolve só o que vem depois de "\K".

set -u

# ---------------------------------------------------------------------------
# Identidade do produto e versão desta peça
# ---------------------------------------------------------------------------

# O identificador do produto — é também o nome esperado da pasta raiz do
# pacote (item 13 do §5: pasta raiz diferente do identificador é recusada,
# porque o servidor de licenças recusa o envio).
RELEASE_PRODUCT_SLUG="v3r-example"

# A versão do v3r-release que ESTE produto espera (§3 do contrato). Se a
# cópia local da peça (arquivo VERSION na raiz do v3r-release) for outra, o
# script recusa e manda atualizar — nunca roda com receita divergente da que
# o robô do GitHub vai usar.
RELEASE_TOOLING_VERSION="0.1.0"

# ---------------------------------------------------------------------------
# Cabeçalho de versão (itens 1 e 2 do §5)
# ---------------------------------------------------------------------------

# Arquivo, dentro do pacote, onde mora o cabeçalho de versão do plugin
# (o comentário `Version: x.y.z` que o WordPress lê).
RELEASE_VERSION_HEADER_FILE="v3r-example.php"

# Regex PCRE (grep -P) com "\K" antes do texto da versão. Aplicada ao
# arquivo inteiro (multi-linha), primeira ocorrência.
RELEASE_VERSION_HEADER_REGEX="^ \\* Version: *\\K[0-9][^[:space:]]*"

# Item 2 (versão do cabeçalho diferente da versão que se pretende publicar):
# o v3r-release compara a versão do cabeçalho com o valor recebido em
# --expected-version, argumento OBRIGATÓRIO de linha de comando (sem ele o
# script recusa rodar). Não há campo aqui para isso, e não é o nome do
# arquivo .zip: não existe convenção de nome entre os produtos da casa, e
# deduzir do nome seria circular (quem nomeia o zip é a mesma receita que
# confere).

# ---------------------------------------------------------------------------
# Outros pontos onde a versão precisa concordar (item 3 do §5)
# ---------------------------------------------------------------------------

# Cada entrada: "caminho|regex PCRE com \K". Mesmo esquema do cabeçalho, um
# arquivo por entrada.
RELEASE_VERSION_EXTRA_FILES=(
  "readme.txt|Stable tag: *\\K[0-9][^[:space:]]*"
  "package.json|\"version\": *\"\\K[^\"]+"
)

# ---------------------------------------------------------------------------
# Front: artefatos compilados (item 4 do §5)
# ---------------------------------------------------------------------------

# Cada entrada: "diretório do artefato|arquivo de manifesto dentro dele".
# Recusa se o diretório não existir, estiver vazio, ou o manifesto faltar.
RELEASE_FRONT_ARTIFACTS=(
  "assets/build|assets/build/manifest.json"
)

# ---------------------------------------------------------------------------
# Front: arquivos que o PHP enfileira (item 5 do §5)
# ---------------------------------------------------------------------------

# Caminhos, dentro do pacote, que o PHP do produto passa para
# wp_enqueue_script/wp_enqueue_style (ou equivalente). Se o PHP referencia um
# arquivo que não está no pacote, a tela fica em branco sem erro nenhum.
RELEASE_FRONT_ENQUEUED_FILES=(
  "assets/build/app.js"
  "assets/build/app.css"
)

# ---------------------------------------------------------------------------
# Bibliotecas de terceiro prefixadas (itens 6, 7, 8, 9 e 10 do §5)
# ---------------------------------------------------------------------------

# Cada entrada tem 5 campos:
#   slug|diretório_cru|diretório_prefixado|classe_original|classe_prefixada
#
# - diretório_cru: onde a biblioteca ficaria SEM prefixar (ex.: vendor/...).
#   A ferramenta de prefixação (Strauss) deixa esse diretório VAZIO para
#   trás — por isso o item 8 confere CONTEÚDO, nunca só a existência do
#   diretório: um diretório vazio ali é o comportamento correto.
# - diretório_prefixado: onde a cópia prefixada precisa estar de fato.
# - classe_original / classe_prefixada: nomes totalmente qualificados
#   (com namespace), usados para resolver via autoload (item 7: a
#   prefixada tem que resolver, a original NÃO pode resolver).
RELEASE_PREFIXED_LIBS=(
  "guzzle|vendor/guzzlehttp/guzzle|vendor-prefixed/guzzlehttp/guzzle|GuzzleHttp\\Client|V3RExample\\GuzzleHttp\\Client"
)

# Arquivo de autoload do pacote, usado para resolver as classes acima
# (itens 7 e 9). É o mesmo autoload que o WordPress carrega em produção.
RELEASE_AUTOLOAD_FILE="vendor/autoload.php"

# Arquivos de classmap (gerados pelo Composer/Strauss) usados para o item 9:
# cada entrada do mapa (classe => caminho de arquivo) precisa resolver para
# um arquivo que exista de fato dentro do pacote.
RELEASE_CLASSMAP_FILES=(
  "vendor/composer/autoload_classmap.php"
)

# ---------------------------------------------------------------------------
# Arquivos de dados lidos em runtime pelas bibliotecas prefixadas (item 11)
# ---------------------------------------------------------------------------

# Caminho, dentro do pacote, de todo arquivo que uma biblioteca prefixada lê
# do disco em tempo de execução (fontes de PDF, dicionários, certificados
# etc.) — coisa que o autoload não carrega e por isso passa despercebida.
RELEASE_RUNTIME_DATA_FILES=(
  # "vendor-prefixed/algum/pacote/dados/tabela.json"
)

# ---------------------------------------------------------------------------
# Caminhos que o pacote PRECISA conter (item 12 do §5)
# ---------------------------------------------------------------------------

# A lista que cada produto usa para dizer "sem isto eu não funciono".
RELEASE_REQUIRED_PATHS=(
  "readme.txt"
  "v3r-example.php"
)

# ---------------------------------------------------------------------------
# Fonte de desenvolvimento que NUNCA pode ir no pacote (item 14 do §5)
# ---------------------------------------------------------------------------

# Caminhos (arquivo ou diretório), relativos à raiz do pacote, cuja simples
# presença indica que o pacote levou fonte de desenvolvimento — sinal de que
# provavelmente foi montado sem o compilado correspondente.
RELEASE_FORBIDDEN_DEV_PATHS=(
  "src"
  "node_modules"
  "tests"
  ".git"
  "package-lock.json"
)

# ---------------------------------------------------------------------------
# Comandos de teste e análise (item 16 e 17 do §5)
# ---------------------------------------------------------------------------

# NÃO rodados por `verify-package.sh` nesta fatia (dependem da árvore de
# trabalho, não do pacote montado, e rodam num passo anterior do §8). Ficam
# declarados aqui porque são parte do que o produto expõe, para a fatia que
# vier a rodá-los.
RELEASE_TEST_CMD="composer test"
RELEASE_LINT_CMD="composer check"

# ---------------------------------------------------------------------------
# Convenções que este produto exige (§6) — padrão de fábrica: exige as duas
# ---------------------------------------------------------------------------

# Arquivo de desinstalação presente no pacote.
RELEASE_REQUIRE_UNINSTALL=true
RELEASE_UNINSTALL_FILE="uninstall.php"

# Changelog em dia com a versão publicada: a versão do cabeçalho precisa
# aparecer como entrada no changelog declarado abaixo.
RELEASE_REQUIRE_CHANGELOG_UPTODATE=true
RELEASE_CHANGELOG_FILE="CHANGELOG.md"
RELEASE_CHANGELOG_VERSION_REGEX="^##+ *\\[?\\K[0-9]+\\.[0-9]+\\.[0-9]+"

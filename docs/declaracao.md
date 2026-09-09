# A declaração do produto — `release.config.sh`

Formato do que o §4 do [contrato](contrato.md) chama de "o que o produto
declara". É um arquivo shell (`source`-ável tanto por script de shell quanto
pela ação composta do GitHub), sem processo externo, sem efeito colateral —
só atribuição de variáveis e arrays.

**Onde mora:** no repositório de CÓDIGO do produto, nunca no de gestão — é o
motivo desta peça existir (§1 do contrato). Nome do arquivo: `release.config.sh`,
na raiz do repositório do produto.

Um exemplo comentado, campo a campo, está em [`examples/release.config.sh`](../examples/release.config.sh).
Este documento explica o *porquê* de cada campo; o exemplo mostra a sintaxe.

## Convenções gerais

- **Caminhos são relativos à raiz do pacote** — o diretório que tem o mesmo
  nome do produto dentro do zip — nunca à raiz do repositório de código.
- **Arrays com múltiplos campos por entrada usam `|` (pipe) como separador.**
  Nenhum caminho de arquivo do WordPress usa esse caractere; não o use em
  nome de arquivo declarado aqui.
- **Regex de versão são PCRE** (`grep -P`), usando `\K` para marcar onde o
  texto da versão **começa** — sem grupo de captura. Ex.:
  `Version: *\K[0-9.]+` casa a linha inteira, mas o que a conferência extrai
  é só o trecho depois de `\K`.

## Campos

### Identidade e versão da peça

| Campo | Descrição |
|---|---|
| `RELEASE_PRODUCT_SLUG` | Identificador do produto. É também o nome que a pasta raiz do pacote precisa ter (item 13 do §5). |
| `RELEASE_TOOLING_VERSION` | Versão do próprio `v3r-release` que este produto espera (§3 do contrato). Cópia local divergente do arquivo `VERSION` faz o script recusar. |

### Cabeçalho de versão (itens 1 e 2 do §5)

| Campo | Descrição |
|---|---|
| `RELEASE_VERSION_HEADER_FILE` | Arquivo, dentro do pacote, com o cabeçalho `Version:` que o WordPress lê. |
| `RELEASE_VERSION_HEADER_REGEX` | Regex PCRE com `\K` para extrair a versão desse arquivo. |

O item 2 (versão do cabeçalho contra a versão que se pretende publicar) não
tem campo próprio: o `verify-package.sh` compara a versão do cabeçalho com o
valor recebido em `--expected-version <versão>`, argumento de linha de
comando **obrigatório** (sem ele o script recusa rodar — falha fechada). Não
há convenção de nome de arquivo `.zip` entre os produtos da casa — um nomeia
`<slug>-<versão>.zip`, outro `<slug>-v<versão>.zip` — e deduzir do nome de
qualquer forma seria circular: quem nomeia o zip é a mesma receita que
confere. `--expected-version` é o único lugar por onde a intenção de publicar
aquela versão entra na conferência; a tag do git só existe depois, quando o
robô publica.

### Outros pontos de versão (item 3 do §5)

| Campo | Descrição |
|---|---|
| `RELEASE_VERSION_EXTRA_FILES` | Array de `"caminho\|regex"` (regex PCRE com `\K`). Cada arquivo tem sua versão extraída e comparada com a do cabeçalho. |

### Front — artefatos compilados (item 4 do §5)

| Campo | Descrição |
|---|---|
| `RELEASE_FRONT_ARTIFACTS` | Array de `"diretório\|manifesto"`. Recusa se o diretório faltar, estiver vazio, ou o manifesto não existir. |

### Front — arquivos enfileirados pelo PHP (item 5 do §5)

| Campo | Descrição |
|---|---|
| `RELEASE_FRONT_ENQUEUED_FILES` | Caminhos que o PHP do produto passa para `wp_enqueue_script`/`wp_enqueue_style`. Ausência é tela em branco sem erro. |

### Bibliotecas de terceiro prefixadas (itens 6, 7, 8, 9 e 10 do §5)

| Campo | Descrição |
|---|---|
| `RELEASE_PREFIXED_LIBS` | Array de `"slug\|dir_cru\|dir_prefixado\|classe_original\|classe_prefixada"`, uma entrada por biblioteca. |
| `RELEASE_AUTOLOAD_FILE` | Autoload do pacote, usado para resolver as classes acima (itens 7 e 9). |
| `RELEASE_CLASSMAP_FILES` | Arquivos de classmap do Composer/Strauss; cada classe mapeada precisa resolver para um arquivo existente (item 9). |

⚠️ **O item 8 é a armadilha central desta peça.** A ferramenta de prefixação
(Strauss) deixa o `dir_cru` **vazio** para trás — não o remove. Um pacote
correto tem esse diretório presente e vazio; conferir só a *existência* do
diretório reprovaria todo pacote correto. A conferência precisa olhar
**conteúdo** (há algum arquivo dentro?), nunca a existência do diretório em
si.

⚠️ **O item 7 tem duas pontas.** Não basta a classe prefixada resolver — a
classe original **também não pode** resolver. Um autoload que carrega os
dois nomes (prefixação pela metade) tem que ser recusado; testar só a ponta
positiva aprovaria exatamente o defeito que o item existe para pegar.

⚠️ **O item 10 tem a armadilha oposta ao item 8: o nome PREFIXADO CONTÉM o
nome ORIGINAL como sufixo.** `use Rit360Solidario\Vendor\V3R\Core\Bootstrap`
contém literalmente o texto `V3R\Core\Bootstrap` — buscar por substring, sem
mais, recusa todo pacote CORRETAMENTE prefixado. A conferência só flagra uma
ocorrência do nome original quando ela **não** está precedida do prefixo
completo, e cobre as duas grafias que aparecem em código PHP: a simples
(`V3R\Core\Bootstrap`) e a escapada (`V3R\\Core\\Bootstrap`, como o texto
aparece dentro de uma string entre aspas). Os arquivos do `RELEASE_AUTOLOAD_FILE`
e de `RELEASE_CLASSMAP_FILES` ficam de fora desta checagem — são arquivo
GERADO, não código do produto, e legitimamente contêm o nome original como
sufixo do nome prefixado (a garantia de que resolvem para arquivo existente
já é o item 9).

### Versão embutida de biblioteca prefixada (item 20 do §5)

| Campo | Descrição |
|---|---|
| `RELEASE_LIBRARY_VERSION_FILES` | Array de `"slug\|arquivo_relativo_ao_dir_prefixado\|regex"`. O `slug` precisa ser o MESMO já usado numa entrada de `RELEASE_PREFIXED_LIBS` — é dali que o item 20 pega o diretório prefixado, sem duplicar a informação. |

Os itens 6–10 provam que a biblioteca **chegou** ao pacote; não provam **qual
versão** chegou. Um `composer.lock` desatualizado (de outra máquina, de uma
sincronização) faz o empacotamento embutir uma versão antiga em silêncio —
os itens 6–10 continuam passando, porque a árvore prefixada existe e
resolve; só é a árvore de uma versão mais velha do que a publicação pretende
(V3RCore-Code#44).

O valor **esperado** não tem campo aqui — nunca é número mantido à mão neste
arquivo, que descolaria na primeira distração. Vem de `--expected-lib-version
<slug>=<versão>` (repetível, uma vez por slug declarado), argumento passado
por quem monta o build — tipicamente lido do `composer.lock` um instante
antes de empacotar. Slug declarado em `RELEASE_LIBRARY_VERSION_FILES` sem o
`--expected-lib-version` correspondente é recusa (falha fechada, mesma
lógica do item 2 com `--expected-version`).

Exemplo, para a `v3r-core` (que expõe `V3R\Core\Version::CURRENT`, uma
constante de CLASSE — não `define()`, que colidiria entre dois plugins
embutindo versões diferentes no mesmo WordPress):

```bash
RELEASE_LIBRARY_VERSION_FILES=(
  "v3r-core|src/Version.php|const CURRENT = '\\K[0-9]+\\.[0-9]+\\.[0-9]+"
)
```

```bash
bin/verify-package.sh --expected-version 1.2.3 \
  --expected-lib-version v3r-core=0.22.1 \
  dist/meuplugin-1.2.3.zip release.config.sh
```

### Arquivos de dados lidos em runtime (item 11 do §5)

| Campo | Descrição |
|---|---|
| `RELEASE_RUNTIME_DATA_FILES` | Caminhos que uma biblioteca prefixada lê do disco em tempo de execução (não passam pelo autoload, por isso passam despercebidos). |

### Caminhos obrigatórios (item 12 do §5)

| Campo | Descrição |
|---|---|
| `RELEASE_REQUIRED_PATHS` | A lista que o produto usa para dizer "sem isto eu não funciono". |

### Fonte de desenvolvimento proibida (item 14 do §5)

| Campo | Descrição |
|---|---|
| `RELEASE_FORBIDDEN_DEV_PATHS` | Caminhos cuja simples presença no pacote indica fonte de desenvolvimento levada por engano. |

### Teste e análise (itens 16 e 17 do §5)

| Campo | Descrição |
|---|---|
| `RELEASE_TEST_CMD` | Comando de suíte de testes do produto. |
| `RELEASE_LINT_CMD` | Comando de análise estática/estilo do produto. |

Declarados aqui, mas **não executados** por `verify-package.sh` nesta fatia —
rodam sobre a árvore de trabalho, num passo anterior do §8, e ficam para a
fatia que tratar do empacotamento fim-a-fim.

### Convenções do §6 — opt-out, nunca opt-in

| Campo | Descrição |
|---|---|
| `RELEASE_REQUIRE_UNINSTALL` | `true`/`false`. Padrão de fábrica: `true`. |
| `RELEASE_UNINSTALL_FILE` | Caminho do arquivo de desinstalação, quando exigido. |
| `RELEASE_REQUIRE_CHANGELOG_UPTODATE` | `true`/`false`. Padrão de fábrica: `true`. |
| `RELEASE_CHANGELOG_FILE` | Changelog a conferir. |
| `RELEASE_CHANGELOG_VERSION_REGEX` | Regex PCRE com `\K` para achar as versões registradas no changelog. |

O padrão de fábrica das duas é **exigir** (§6 do contrato): um produto que
ainda não cumpre declara explicitamente que não exige, e essa declaração é a
lista do que falta — visível, com dono.

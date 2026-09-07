# v3r-release

A receita única de empacotar, conferir e publicar os plugins WordPress da
família V3RTECH/RIT. Ver [`docs/contrato.md`](docs/contrato.md) para o
porquê e a régua completa do que se confere.

Esta fatia entrega a **conferência de um pacote já montado** e o **formato de
declaração** que cada produto usa para dizer o que é seu.

## O que tem aqui

- **`bin/verify-package.sh`** — recebe um pacote `.zip` já montado e a
  declaração do produto, desempacota num diretório temporário e roda as
  conferências do §5 do contrato que se fazem sobre o conteúdo do pacote
  (itens 1 a 15, mais §3 e §6). Ver `--help`.
- **`examples/release.config.sh`** — exemplo comentado do formato de
  declaração (§4 do contrato). É esse arquivo, com o nome `release.config.sh`
  na raiz do repositório de CÓDIGO do produto, que cada plugin escreve.
- **`examples/reais/`** — declarações de produtos de verdade da casa (RIT360
  Solidário, V3REvent, RIT360 Flow), usadas por
  `tests/run-tests-reais.sh` para conferir contra o `.zip` publicado de
  cada um, quando ele existe na máquina.
- **`docs/declaracao.md`** — o que cada campo da declaração significa e por
  quê.
- **`docs/contrato.md`** — a decisão de projeto; não se implementa nada aqui
  sem reler esse documento primeiro.
- **`VERSION`** — a versão desta peça (§3 do contrato).

## Requisitos

- `bash` (testado em 5.x)
- `unzip`, `find`, `grep` (GNU grep, com suporte a `-P`), `zip` — utilitários
  padrão de qualquer distribuição Linux
- `php` (cli) — usado para resolver classes via autoload e ler os arquivos
  de classmap (itens 7 e 9 do §5)

Nenhuma dependência de rede, nenhum pacote adicional a instalar.

## Como usar

```
bin/verify-package.sh [--all] --expected-version <versão> <pacote.zip> <release.config.sh>
```

`--expected-version` é **obrigatório** — sem ele o script recusa rodar
(falha fechada). É a versão que se PRETENDE publicar com este pacote; o
item 2 confere o cabeçalho contra ela, nunca contra o nome do arquivo
`.zip` — não há convenção de nome entre os produtos da casa, e deduzir do
nome seria circular (quem nomeia o zip é a mesma receita que confere).

Sai com código diferente de zero na primeira recusa (padrão), imprimindo em
uma linha qual conferência recusou e o que encontrou. Com `--all`, roda todas
as conferências e lista todas as recusas em vez de parar na primeira.

## Rodando a suíte de testes

```
tests/run-tests.sh
```

Bash puro, sem rede, sem instalar nada. Cada teste monta seu próprio
pacote-fixture (uma cópia mutada da linha de base, definida em
`tests/lib/fixture.sh`) em diretório temporário, empacota, roda
`bin/verify-package.sh` sobre ele e confere o resultado — inclusive a
armadilha do item 8 (diretório cru vazio é correto; com conteúdo, não) e a
armadilha do item 10 (nome prefixado contém o original como sufixo; buscar
por substring recusaria todo pacote correto).

## Conferindo contra pacotes reais

```
tests/run-tests-reais.sh
```

Roda `bin/verify-package.sh` contra o `.zip` publicado de cada produto
listado em `examples/reais/`, usando a declaração real de cada um. Pula com
aviso — nunca falha — o produto cujo `.zip` não existir na máquina corrente:
a suíte principal (`tests/run-tests.sh`) não pode depender de artefato local
para ficar verde, mas esta é a prova de que a conferência não só passa nos
fixtures artificiais, passa no que a casa de fato publica.

## Lint

Este projeto é conferido com [ShellCheck](https://www.shellcheck.net/). Se
não houver `shellcheck` instalado:

- **Arch Linux:** `sudo pacman -S shellcheck`
- **Debian/Ubuntu:** `sudo apt install shellcheck`
- **Fedora:** `sudo dnf install ShellCheck`
- **Windows:** `winget install koalaman.shellcheck` (ou via WSL, seguindo a
  distribuição escolhida)

```
shellcheck bin/verify-package.sh examples/release.config.sh tests/run-tests.sh tests/lib/fixture.sh
```

## O que esta fatia NÃO faz

Não empacota (`build-zip`), não publica, não é a ação composta do GitHub, não
roda suíte de testes nem análise estática do produto (itens 16 e 17 do §5,
que rodam sobre a árvore de trabalho antes de empacotar) e não confere envio
ao servidor de licenças (itens 18 e 19, que dependem de rede). Fica para a
próxima fatia.

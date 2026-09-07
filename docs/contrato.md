# O contrato do `v3r-release`

> Decisão de projeto de 07/09/2026 (`V3RCore-Code#14` e `#34`). Este documento
> vem antes do código, como o `navegacao-do-painel.md` veio antes da camada de
> navegação: é ele que decide o que a peça faz, e é contra ele que o código se
> confere.

## 1. O problema que esta peça resolve

A receita de empacotar e conferir um plugin da casa existia **nove vezes** — e,
em sete dos nove produtos, **duas vezes dentro do mesmo produto**: uma no
script que se roda na máquina, outra reescrita dentro do robô que publica.

⚠️ **A causa não era desleixo: era onde o script morava.** Nos sete que
reescreviam, o script de montagem ficava no repositório de **gestão**, que o
robô do GitHub não clona. Quem escreveu o robô não tinha como chamá-lo.

As duas escritas então se separavam em silêncio, e a separação só aparecia na
release publicada — o momento em que o código entra no site do cliente sem
ninguém olhando. Foi assim que o checkout de quatro sites parou: o robô
compilava um dos dois artefatos de front, e as exclusões do empacotamento
cobriam só o primeiro; o pacote saiu com o fonte de um e sem o compilado do
outro. Sem erro de PHP, sem erro de JavaScript — o bloco carregava para
sempre.

**Esta peça é a receita, uma vez só.** O robô e a máquina chamam a mesma.

## 2. Por que ela mora num repositório público

Porque publicar não pode passar a depender de uma chave a mais.

A alternativa era guardá-la junto das ferramentas internas, que são privadas —
e aí cada um dos nove produtos precisaria de uma chave de leitura cadastrada,
com nove lugares para expirar. Uma peça **pública e sem segredo dentro** é
clonada pelo robô sem chave nenhuma, do mesmo jeito que o pacote de tela da
família já é instalado.

⚠️ **Consequência que não se negocia: aqui não entra segredo, nem endereço de
site de cliente, nem inventário de instalação.** O que é do produto — inclusive
a lista de caminhos que o pacote dele precisa ter — é declarado **no
repositório do produto**, não aqui. Esta peça sabe *como* conferir; o *que*
conferir vem de fora.

## 3. Como cada lado consome

**Uma fonte, dois caminhos, a mesma versão fixada.**

- **O robô** usa a ação composta deste repositório, presa a uma tag
  (`uses: V3RTECH-DF/v3r-release@v1.2.3`). Sem chave, porque o repositório é
  público.
- **A máquina** usa a cópia local desta peça, e o produto declara qual versão
  espera.

⚠️ **A cópia local que não for a versão declarada pelo produto faz o script
recusar e mandar atualizar** — nunca empacota com receita diferente da que o
robô vai usar. É a lição do `bump-version.sh`, que divergiu em dez cópias sem
ninguém ver: não basta corrigir onde se edita, é preciso alcançar onde se
executa.

## 4. O que o produto declara

Um arquivo no repositório do **código** do produto (nunca no de gestão — o
robô não o clona). Ele diz o que é próprio daquele produto:

- o identificador do produto e onde fica o cabeçalho da versão;
- os outros pontos onde a versão aparece e precisa concordar;
- as bibliotecas de terceiro que são prefixadas, e o prefixo;
- os arquivos de dados que cada uma dessas bibliotecas lê em disco em tempo de
  execução;
- os caminhos que o pacote **precisa** conter;
- os artefatos de front a compilar e o manifesto de cada um;
- os comandos de teste e de análise;
- as convenções que este produto exige (§6);
- a versão desta peça que o produto espera.

## 5. O que a conferência recusa — a régua única

Vale para os nove, sem exceção declarável. O critério de entrada nesta lista é
um só: **falhar aqui quebra o site do cliente, ou publica uma versão que não
se corrige depois.**

| # | O que recusa | Por que está aqui |
|---|---|---|
| 1 | versão do cabeçalho vazia ou ilegível | sem ela nada mais confere |
| 2 | versão do cabeçalho diferente da tag | publica-se uma coisa dizendo que é outra |
| 3 | versão do cabeçalho diferente dos outros pontos declarados | a atualização automática compara versões; discordância prende o cliente numa versão que não existe |
| 4 | artefato de front ausente, vazio ou sem manifesto | tela em branco, sem erro nenhum |
| 5 | arquivo de front enfileirado pelo PHP que não existe no pacote | mesma tela em branco, por outro caminho |
| 6 | biblioteca prefixada ausente do pacote | erro fatal na ativação |
| 7 | o nome prefixado não resolve, **ou** o nome original resolve | prefixação pela metade colide com outro plugin da casa no mesmo site |
| 8 | o mesmo componente presente nas duas árvores, a crua e a prefixada | ⚠️ conferir **conteúdo**, nunca existência de diretório: a ferramenta de prefixação deixa o diretório vazio para trás, e checar existência daria falso positivo em toda árvore correta |
| 9 | classe do mapa de classes que não resolve para arquivo existente | ativação quebra em silêncio |
| 10 | nome de classe montado em texto que escapou da prefixação | a ferramenta reescreve código, não dados — este é o furo que ela não fecha |
| 11 | arquivo de dados declarado que não viajou no pacote | a geração de documento falha só em produção, quando alguém emite |
| 12 | caminho declarado como obrigatório ausente do pacote | é a lista que cada produto usa para dizer "sem isto eu não funciono" |
| 13 | pasta raiz do pacote diferente do identificador do produto | o servidor de licenças recusa o envio |
| 14 | fonte de desenvolvimento dentro do pacote | pacote que leva fonte costuma estar sem o compilado |
| 15 | diretório sem permissão de travessia | o servidor web não lê, e o plugin morre no arranque |
| 16 | suíte de testes vermelha | — |
| 17 | análise estática ou estilo reprovados | ⚠️ só onde o produto declara os comandos; hoje quatro produtos têm as duas ferramentas configuradas e não as rodam ao publicar |
| 18 | envio ao servidor de licenças que não devolveu sucesso | — |
| 19 | resumo do pacote diferente do que o servidor registrou | prova que chegou inteiro o que saiu |

⚠️ **Tudo isto se confere sobre o PACOTE MONTADO, nunca sobre a árvore de
trabalho.** Conferir a árvore prova o que *vai* para o pacote; não prova o que
o pacote tem. Onde couber, a conferência roda também cedo, na árvore — mas
como aviso adiantado, não como a prova.

## 6. O que o produto declara e a peça não impõe

Convenção da casa não trava publicação de quem ainda não a cumpre. Cada
produto declara se exige:

- **arquivo de desinstalação** presente no pacote — hoje quatro exigem, cinco
  não;
- **changelog em dia** com a versão publicada — hoje três conferem.

⚠️ **O padrão de fábrica das duas é "exige".** Produto que não cumpre declara
que não exige, e essa declaração é a lista do que falta — visível, com dono,
em vez de uma ausência que ninguém enxerga.

## 7. O que esta peça NÃO faz

Não decide versão, não cria tag, não commita, não envia nada para as máquinas
da casa e não conhece site de cliente. Subir versão é uma coisa; publicar é
decisão separada e deliberada, e continua sendo de quem empurra a tag.

## 8. A ordem, e por que ela é essa

1. conferir versão (§5, 1–3) — falha barata, antes de compilar qualquer coisa;
2. rodar teste e análise (§5, 16–17);
3. compilar os artefatos de front (§5, 4–5);
4. montar a árvore de distribuição e prefixar;
5. **empacotar**;
6. conferir o pacote (§5, 6–15) — desempacotando o pacote de verdade;
7. enviar e conferir o resumo (§5, 18–19).

⚠️ **O passo 6 abre o pacote final.** Conferir o diretório que estava prestes a
virar pacote não prova que o empacotamento não mudou nada — e hoje quatro
produtos param nessa meia prova.

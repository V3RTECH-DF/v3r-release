#!/usr/bin/env bash
# run-tests-reais.sh — roda bin/verify-package.sh contra o .zip PUBLICADO de
# produtos reais da casa, um por produto listado em examples/reais/.
#
# ⚠️ Isto é além, não em vez, de tests/run-tests.sh: os fixtures artificiais
# provam que cada conferência DISCRIMINA (o defeito certo recusa, o correto
# passa); este script prova que a conferência não tropeça no que a casa de
# fato publica — código real tem forma que fixture nenhum antecipa.
#
# Pula com AVISO — nunca falha — o produto cujo repositório ou .zip não
# existir na máquina corrente: a suíte principal não pode depender de
# artefato local para ficar verde, e esta tampouco.
#
# Uso: tests/run-tests-reais.sh

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd -P)"
VERIFY="$REPO_ROOT/bin/verify-package.sh"
REAIS_DIR="$REPO_ROOT/examples/reais"

# Cada entrada: "config|glob-do-zip-publicado". O glob pega o zip mais
# recente (ordenação por versão) quando houver mais de um em dist/.
PRODUTOS=(
  "$REAIS_DIR/rit360-solidario.release.config.sh|/mnt/trabalho/Projetos/RIT/RIT360/Solidario/Code/dist/rit360-solidario-*.zip"
  "$REAIS_DIR/v3revent.release.config.sh|/mnt/trabalho/Projetos/V3RTECH/V3REvent/Code/dist/v3revent-v*.zip"
  "$REAIS_DIR/rit360-flow.release.config.sh|/mnt/trabalho/Projetos/RIT/RIT360/Flow/Code/dist/rit360-flow-v*.zip"
)

# extrai_versao_do_nome <basename-sem-.zip> — pega o último trecho depois do
# último "-" e tira o "v" opcional na frente. Vale só para este script de
# conferência (que confere pacote JÁ publicado, portanto o próprio nome
# reflete a versão de fato publicada) — nunca para o verify-package.sh em
# si, que recebe --expected-version explícito e não deduz nada do nome.
extrai_versao_do_nome() {
  local base="$1"
  base="${base##*-}"
  base="${base#v}"
  printf '%s' "$base"
}

TESTS_RUN=0
TESTS_FAILED=0
TESTS_PULADOS=0

for entrada in "${PRODUTOS[@]}"; do
  cfg="${entrada%%|*}"
  glob="${entrada#*|}"

  # O padrão precisa ser expandido pelo shell (daí sem aspas), e a ordenação
  # é por versão — `sort -V` põe 2.26.10 depois de 2.26.9, o alfabético não.
  # shellcheck disable=SC2086
  zip="$(printf '%s\n' $glob 2>/dev/null | sort -V | tail -1)" || true
  [ -f "$zip" ] || zip=""

  nome="$(basename -- "$cfg" .release.config.sh)"

  if [ ! -f "$cfg" ]; then
    echo "PULADO — $nome: declaração não encontrada ($cfg)"
    TESTS_PULADOS=$((TESTS_PULADOS + 1))
    continue
  fi
  if [ -z "$zip" ] || [ ! -f "$zip" ]; then
    echo "PULADO — $nome: nenhum .zip publicado encontrado em '$glob' nesta máquina"
    TESTS_PULADOS=$((TESTS_PULADOS + 1))
    continue
  fi

  versao="$(extrai_versao_do_nome "$(basename -- "$zip" .zip)")"

  TESTS_RUN=$((TESTS_RUN + 1))
  echo "=== $nome — $(basename -- "$zip") (versão $versao) ==="
  if OUT="$("$VERIFY" --all --expected-version "$versao" "$zip" "$cfg" 2>&1)"; then
    echo "ok — $nome"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FALHOU — $nome:"
    echo "$OUT"
  fi
  echo ""
done

echo "$TESTS_RUN produto(s) conferido(s), $TESTS_FAILED falha(s), $TESTS_PULADOS pulado(s) (sem .zip nesta máquina)."
[ "$TESTS_FAILED" -eq 0 ]

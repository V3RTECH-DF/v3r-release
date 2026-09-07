#!/usr/bin/env bash
# Declaração REAL do V3REvent — repositório
# /mnt/trabalho/Projetos/V3RTECH/V3REvent/Code, gerada a partir de
# bin/build-zip.sh. Usada por tests/run-tests-reais.sh contra o .zip
# publicado em Code/dist/, quando ele existir na máquina.
set -u

RELEASE_PRODUCT_SLUG="v3revent"
RELEASE_TOOLING_VERSION="0.1.0"

RELEASE_VERSION_HEADER_FILE="v3revent.php"
RELEASE_VERSION_HEADER_REGEX="^ \\* Version: *\\K[0-9][^[:space:]]*"
RELEASE_VERSION_EXTRA_FILES=()

# Sem manifesto de build (o Vite deste plugin não gera um) — os artefatos
# de front são conferidos pelo item 5 (arquivos que o PHP enfileira), não
# pelo item 4.
RELEASE_FRONT_ARTIFACTS=()
RELEASE_FRONT_ENQUEUED_FILES=(
  "admin/dist/assets/admin.js"
  "admin/dist/assets/admin.css"
  "admin/dist/assets/front.js"
  "admin/dist/assets/front.css"
)

# v3r-core, plugin-update-checker, mpdf, phpspreadsheet e php-qrcode são
# require-dev: vendor/<pacote> nunca existe no pacote final (o
# `composer install --no-dev` não os reinstala) — por isso dir_cru aponta
# para um caminho que o item 8 nunca vai encontrar, o que é o comportamento
# correto (dir_cru inexistente não é recusado, só dir_cru COM conteúdo).
RELEASE_PREFIXED_LIBS=(
  "v3r-core|vendor/v3rtech/v3r-core|vendor-prefixed/v3rtech/v3r-core|V3R\\Core\\Bootstrap|V3RTECH\\V3REvent\\Vendor\\V3R\\Core\\Bootstrap"
  "plugin-update-checker|vendor/yahnis-elsts/plugin-update-checker|vendor-prefixed/yahnis-elsts/plugin-update-checker|YahnisElsts\\PluginUpdateChecker\\v5\\PucFactory|V3RTECH\\V3REvent\\Vendor\\YahnisElsts\\PluginUpdateChecker\\v5\\PucFactory"
  "mpdf|vendor/mpdf/mpdf|vendor-prefixed/mpdf/mpdf|Mpdf\\Mpdf|V3RTECH\\V3REvent\\Vendor\\Mpdf\\Mpdf"
  "phpspreadsheet|vendor/phpoffice/phpspreadsheet|vendor-prefixed/phpoffice/phpspreadsheet|PhpOffice\\PhpSpreadsheet\\Spreadsheet|V3RTECH\\V3REvent\\Vendor\\PhpOffice\\PhpSpreadsheet\\Spreadsheet"
  "qrcode|vendor/chillerlan/php-qrcode|vendor-prefixed/chillerlan/php-qrcode|chillerlan\\QRCode\\QRCode|V3RTECH\\V3REvent\\Vendor\\chillerlan\\QRCode\\QRCode"
)
RELEASE_AUTOLOAD_FILE="vendor/autoload.php"
RELEASE_CLASSMAP_FILES=(
  "vendor/composer/autoload_classmap.php"
)

RELEASE_RUNTIME_DATA_FILES=(
  "vendor-prefixed/mpdf/mpdf/data/upperCase.php"
  "vendor-prefixed/mpdf/mpdf/ttfonts/DejaVuSansCondensed.ttf"
)

RELEASE_REQUIRED_PATHS=(
  "v3revent.php"
  "uninstall.php"
  "includes/Core"
  "vendor/autoload.php"
  "vendor-prefixed/v3rtech/v3r-core/src/Bootstrap.php"
  "admin/dist/assets/admin.js"
  "admin/dist/assets/front.js"
)

RELEASE_FORBIDDEN_DEV_PATHS=(
  "admin/src"
  "admin/node_modules"
  "admin/package.json"
  "admin/vite.config.ts"
  "tests"
  ".git"
  "package-lock.json"
)

RELEASE_TEST_CMD="composer test"
RELEASE_LINT_CMD="composer check"

# Sem readme.txt/CHANGELOG.md no pacote (não são copiados pelo build-zip.sh
# deste produto) — as duas convenções do §6 ainda não se aplicam aqui.
RELEASE_REQUIRE_UNINSTALL=true
RELEASE_UNINSTALL_FILE="uninstall.php"
RELEASE_REQUIRE_CHANGELOG_UPTODATE=false
RELEASE_CHANGELOG_FILE="CHANGELOG.md"
RELEASE_CHANGELOG_VERSION_REGEX="^##+ *\\[?\\K[0-9]+\\.[0-9]+\\.[0-9]+"

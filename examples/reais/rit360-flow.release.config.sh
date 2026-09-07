#!/usr/bin/env bash
# Declaração REAL do RIT360 Flow — repositório
# /mnt/trabalho/Projetos/RIT/RIT360/Flow/Code, gerada a partir de
# bin/build-zip.sh e bin/guard-prefixacao.php. Usada por
# tests/run-tests-reais.sh contra o .zip publicado em Code/dist/, quando ele
# existir na máquina.
set -u

RELEASE_PRODUCT_SLUG="rit360-flow"
RELEASE_TOOLING_VERSION="0.1.0"

RELEASE_VERSION_HEADER_FILE="rit360-flow.php"
RELEASE_VERSION_HEADER_REGEX="^ \\* Version: *\\K[0-9][^[:space:]]*"
# A constante V3RFLOW_VERSION é o segundo ponto onde a versão precisa
# concordar — o build-zip.sh já aborta se ela divergir do cabeçalho, mas a
# declaração confere de novo sobre o PACOTE montado (§5 do contrato: nunca
# sobre a árvore de trabalho).
RELEASE_VERSION_EXTRA_FILES=(
  "rit360-flow.php|define\\( 'V3RFLOW_VERSION', *'\\K[0-9][^']*"
)

# Sem manifesto de build — o item 5 (arquivos que o PHP enfileira) é quem
# confere os artefatos do SPA admin.
RELEASE_FRONT_ARTIFACTS=()
RELEASE_FRONT_ENQUEUED_FILES=(
  "admin/dist/assets/admin.js"
  "admin/dist/assets/admin.css"
)

# v3r-core, plugin-update-checker e php-qrcode (+ php-settings-container,
# transitiva) são require-dev: vendor/<pacote> nunca existe no pacote final,
# por isso dir_cru aponta para um caminho que o item 8 nunca encontra — o
# que é o comportamento correto (dir_cru inexistente não é recusado).
RELEASE_PREFIXED_LIBS=(
  "v3r-core|vendor/v3rtech/v3r-core|vendor-prefixed/v3rtech/v3r-core|V3R\\Core\\Bootstrap|V3R\\Flow\\Vendor\\V3R\\Core\\Bootstrap"
  "plugin-update-checker|vendor/yahnis-elsts/plugin-update-checker|vendor-prefixed/yahnis-elsts/plugin-update-checker|YahnisElsts\\PluginUpdateChecker\\v5\\PucFactory|V3R\\Flow\\Vendor\\YahnisElsts\\PluginUpdateChecker\\v5\\PucFactory"
  "qrcode|vendor/chillerlan/php-qrcode|vendor-prefixed/chillerlan/php-qrcode|chillerlan\\QRCode\\QRCode|V3R\\Flow\\Vendor\\chillerlan\\QRCode\\QRCode"
  "php-settings-container|vendor/chillerlan/php-settings-container|vendor-prefixed/chillerlan/php-settings-container|chillerlan\\Settings\\SettingsContainerAbstract|V3R\\Flow\\Vendor\\chillerlan\\Settings\\SettingsContainerAbstract"
)
RELEASE_AUTOLOAD_FILE="vendor/autoload.php"
RELEASE_CLASSMAP_FILES=(
  "vendor/composer/autoload_classmap.php"
)

RELEASE_RUNTIME_DATA_FILES=()

RELEASE_REQUIRED_PATHS=(
  "rit360-flow.php"
  "includes/Core/Activator.php"
  "vendor/autoload.php"
  "vendor-prefixed/v3rtech/v3r-core/src/Bootstrap.php"
  "admin/dist/index.html"
  "admin/dist/assets/admin.js"
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

# Sem uninstall.php nem CHANGELOG.md no pacote hoje — as duas convenções do
# §6 ainda não se aplicam a este produto.
RELEASE_REQUIRE_UNINSTALL=false
RELEASE_UNINSTALL_FILE="uninstall.php"
RELEASE_REQUIRE_CHANGELOG_UPTODATE=false
RELEASE_CHANGELOG_FILE="CHANGELOG.md"
RELEASE_CHANGELOG_VERSION_REGEX="^##+ *\\[?\\K[0-9]+\\.[0-9]+\\.[0-9]+"

#!/usr/bin/env bash
# Declaração REAL do RIT360 Solidário — repositório
# /mnt/trabalho/Projetos/RIT/RIT360/Solidario/Code, gerada a partir de
# bin/build-zip.sh. Usada por tests/run-tests-reais.sh contra o .zip
# publicado em Code/dist/, quando ele existir na máquina.
set -u
RELEASE_PRODUCT_SLUG="rit360-solidario"
RELEASE_TOOLING_VERSION="0.1.0"
RELEASE_VERSION_HEADER_FILE="rit360-solidario.php"
RELEASE_VERSION_HEADER_REGEX="^ \\* Version: *\\K[0-9][^[:space:]]*"
RELEASE_VERSION_EXTRA_FILES=()
RELEASE_FRONT_ARTIFACTS=(
  "assets/app/dist|assets/app/dist/.vite/manifest.json"
  "assets/blocks/checkout-extension/build|assets/blocks/checkout-extension/build/index.asset.php"
)
RELEASE_FRONT_ENQUEUED_FILES=()
RELEASE_PREFIXED_LIBS=(
  "v3r-core|vendor/v3rtech/v3r-core|vendor-prefixed/v3rtech/v3r-core|V3R\\Core\\Bootstrap|Rit360Solidario\\Vendor\\V3R\\Core\\Bootstrap"
  "plugin-update-checker|vendor/yahnis-elsts/plugin-update-checker|vendor-prefixed/yahnis-elsts/plugin-update-checker|YahnisElsts\\PluginUpdateChecker\\v5\\PucFactory|Rit360Solidario\\Vendor\\YahnisElsts\\PluginUpdateChecker\\v5\\PucFactory"
  "mpdf|vendor/mpdf/mpdf|vendor-prefixed/mpdf/mpdf|Mpdf\\Mpdf|Rit360Solidario\\Vendor\\Mpdf\\Mpdf"
)
RELEASE_AUTOLOAD_FILE="vendor-prefixed/autoload.php"
RELEASE_CLASSMAP_FILES=(
  "vendor-prefixed/autoload-classmap.php"
)
RELEASE_RUNTIME_DATA_FILES=(
  "vendor-prefixed/mpdf/mpdf/data/mpdf.css"
)
RELEASE_REQUIRED_PATHS=(
  "rit360-solidario.php"
  "includes/Core/Plugin.php"
  "includes/Core/Activator.php"
  "vendor-prefixed/autoload.php"
  "vendor-prefixed/autoload-classmap.php"
  "vendor-prefixed/mpdf/mpdf/src/Mpdf.php"
  "vendor-prefixed/setasign/fpdi/src/Fpdi.php"
  "vendor-prefixed/v3rtech/v3r-core/src/Bootstrap.php"
  "assets/app/dist/.vite/manifest.json"
  "assets/blocks/checkout-extension/build/index.js"
)
RELEASE_FORBIDDEN_DEV_PATHS=(
  "assets/blocks/checkout-extension/src"
  "assets/blocks/checkout-extension/package.json"
  "assets/blocks/checkout-extension/webpack.config.js"
  "assets/app/src"
  "assets/app/package.json"
  "assets/app/vite.config.ts"
)
RELEASE_TEST_CMD="composer test"
RELEASE_LINT_CMD="composer lint"
RELEASE_REQUIRE_UNINSTALL=false
RELEASE_UNINSTALL_FILE="uninstall.php"
RELEASE_REQUIRE_CHANGELOG_UPTODATE=false
RELEASE_CHANGELOG_FILE="CHANGELOG.md"
RELEASE_CHANGELOG_VERSION_REGEX="^##+ *\\[?\\K[0-9]+\\.[0-9]+\\.[0-9]+"

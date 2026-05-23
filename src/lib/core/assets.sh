#!/bin/bash

if [[ -n "${_LIB_CORE_ASSETS_LOADED:-}" ]]; then
    return
fi
readonly _LIB_CORE_ASSETS_LOADED=1

ASSETS_TMP_DIR=""

assets::source_path() {
    local asset_path="$1"

    printf '%s/src/conf/%s\n' "$BUILD_PROJECT_ROOT" "$asset_path"
}

assets::has_embedded() {
    local asset_path="$1"

    declare -F assets::write_embedded >/dev/null || return 1
    assets::write_embedded "$asset_path" /dev/null >/dev/null 2>&1
}

assets::write() {
    local asset_path="$1"
    local target_path="$2"
    local source_path=""

    log::assert_not_empty "$asset_path" "asset path"
    log::assert_not_empty "$target_path" "target path"

    mkdir -p "$(dirname "$target_path")"

    if declare -F assets::write_embedded >/dev/null && assets::write_embedded "$asset_path" "$target_path"; then
        return 0
    fi

    source_path="$(assets::source_path "$asset_path")"
    [[ -f "$source_path" ]] || log::die "Build asset is missing: $asset_path"
    cp "$source_path" "$target_path"
}

assets::materialize() {
    local asset_path="$1"
    local target_path=""

    log::assert_not_empty "$asset_path" "asset path"

    if [[ -z "$ASSETS_TMP_DIR" ]]; then
        ASSETS_TMP_DIR="$(mktemp -d)"
    fi

    target_path="$ASSETS_TMP_DIR/$asset_path"
    assets::write "$asset_path" "$target_path"
    printf '%s\n' "$target_path"
}

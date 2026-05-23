#!/bin/bash

if [[ -n "${_LIB_CORE_CONFIG_LOADED:-}" ]]; then
    return
fi
readonly _LIB_CORE_CONFIG_LOADED=1

config::load() {
    local config_path="$1"

    log::assert_not_empty "$config_path" "config path"
    [[ -f "$config_path" ]] || log::die "Config file not found: $config_path"

    # shellcheck disable=SC1090
    source "$config_path"
}

config::load_default() {
    local config_path="$1"

    log::assert_not_empty "$config_path" "config path"

    if declare -F config::load_embedded_default >/dev/null; then
        config::load_embedded_default
        return 0
    fi

    config::load "$config_path"
}

config::validate() {
    local required_values=(
        "$BUILD_IMAGE_PATH"
        "$BUILD_IMAGE_SIZE"
        "$BUILD_MOUNT_ROOT"
        "$BUILD_MOUNT_BOOT"
        "$BUILD_USER_NAME"
        "$BUILD_USER_PASSWORD"
        "$BUILD_SSH_USER"
        "$BUILD_ROOT_PASSWORD"
        "$BUILD_TIMEZONE"
        "$BUILD_MKINITCPIO_HOOKS"
    )
    local value=""

    for value in "${required_values[@]}"; do
        [[ -n "$value" ]] || log::die "Required build config value is empty"
    done

    if [[ ! -f "${BUILD_PACMAN_CONF:-}" ]] && ! assets::has_embedded "pacman/pacman-arm.conf"; then
        log::die "Required pacman config is missing"
    fi

    ((${#BUILD_MODULES[@]} > 0)) || log::die "BUILD_MODULES must not be empty"
    ((${#BUILD_PACKAGES[@]} > 0)) || log::die "BUILD_PACKAGES must not be empty"
}

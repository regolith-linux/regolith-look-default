#! /bin/bash

# This script updates the desktop UI configuration based on Xresources
set -eE -u -o pipefail

load_look() {
    # Set GNOME interface options from Xresources values if specifed by Xresources
    GTK_THEME=$(xrescat gtk.theme_name || true)
    if [[ -n ${GTK_THEME:-} ]]; then
        gsettings set org.gnome.desktop.interface gtk-theme "${GTK_THEME}"
    fi

    ICON_THEME=$(xrescat gtk.icon_theme_name || true)
    if [[ -n ${ICON_THEME:-} ]]; then
        gsettings set org.gnome.desktop.interface icon-theme "${ICON_THEME}"
    fi

    WM_FONT=$(xrescat gtk.font_name || true)
    if [[ -n ${WM_FONT:-} ]]; then
        gsettings set org.gnome.desktop.interface font-name "${WM_FONT}"
    fi

    DOC_FONT=$(xrescat gtk.document_font_name || true)
    if [[ -n ${DOC_FONT:-} ]]; then
        gsettings set org.gnome.desktop.interface document-font-name "${DOC_FONT}"
    fi

    MONO_FONT=$(xrescat gtk.monospace_font_name || true)
    if [[ -n ${MONO_FONT:-} ]]; then
        gsettings set org.gnome.desktop.interface monospace-font-name "${MONO_FONT}"
    fi
    
    # Set the wallpaper
    WALLPAPER_FILE_PRE_RESOLVED=$(xrescat regolith.wallpaper.file || true)
    WALLPAPER_FILE=$(realpath -e "${WALLPAPER_FILE_PRE_RESOLVED}" || true)
    WALLPAPER_FILE_OPTIONS=$(xrescat regolith.wallpaper.options || true)
    WALLPAPER_PRIMARY_COLOR=$(xrescat regolith.wallpaper.color.primary || true)

    if [[ -f ${WALLPAPER_FILE:-} ]]; then
        gsettings set org.gnome.desktop.background picture-uri "file://${WALLPAPER_FILE})"
        gsettings set org.gnome.desktop.background picture-options "${WALLPAPER_FILE_OPTIONS:-wallpaper}"
    elif [[ -n ${WALLPAPER_FILE_PRE_RESOLVED} ]]; then
        printf 'Path to wallpaper file ('%s') is invalid"' "${WALLPAPER_FILE_PRE_RESOLVED}" >&2
    elif [[ -n ${WALLPAPER_PRIMARY_COLOR:-} ]]; then
        gsettings set org.gnome.desktop.background picture-options none
        gsettings set org.gnome.desktop.background picture-uri none        
        gsettings set org.gnome.desktop.background primary-color "${WALLPAPER_PRIMARY_COLOR}"

        WALLPAPER_SECONDARY_COLOR=$(xrescat regolith.wallpaper.color.secondary || true)
        WALLPAPER_COLOR_SHADE_TYPE=$(xrescat regolith.wallpaper.color.shading.type || true)

        if [[ -n ${WALLPAPER_SECONDARY_COLOR:-} ]] && [[ -n ${WALLPAPER_COLOR_SHADE_TYPE} ]]; then
            gsettings set org.gnome.desktop.background secondary-color "${WALLPAPER_SECONDARY_COLOR}"
            gsettings set org.gnome.desktop.background color-shading-type "${WALLPAPER_COLOR_SHADE_TYPE}"
        else
            gsettings set org.gnome.desktop.background color-shading-type 'solid'
        fi
    fi

    # Configure the gnome-terminal profile
    if command -v gnome-terminal &>/dev/null; then # check if gnome-terminal is in ${PATH}
        UPDATE_TERM_FLAG=$(xrescat gnome.terminal.update || true)
        if [[ "${UPDATE_TERM_FLAG:-}" == 'true' ]] && \
           [[ -f '/usr/share/regolith-ftue/regolith-init-term-profile' ]] ; then
            /usr/share/regolith-ftue/regolith-init-term-profile
        fi
    fi
}

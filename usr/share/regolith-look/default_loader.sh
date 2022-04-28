#!/bin/bash

# This script updates the desktop UI configuration based on Xresources
set -Eeu -o pipefail

load_look() {
    # Set GNOME interface options from Xresources values if specifed by Xresources
    GTK_THEME="$(xrescat gtk.theme_name)"
    if [ -n  "$GTK_THEME" ]; then
        gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME"
    fi

    ICON_THEME="$(xrescat gtk.icon_theme_name)"
    if [ -n  "$ICON_THEME" ]; then
        gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME"
    fi

    WM_FONT="$(xrescat gtk.font_name)"
    if [ -n  "$WM_FONT" ]; then
        gsettings set org.gnome.desktop.interface font-name "$WM_FONT"
    fi

    DOC_FONT="$(xrescat gtk.document_font_name)"
    if [ -n  "$DOC_FONT" ]; then
        gsettings set org.gnome.desktop.interface document-font-name "$DOC_FONT"
    fi

    MONO_FONT="$(xrescat gtk.monospace_font_name)"
    if [ -n  "$MONO_FONT" ]; then
        gsettings set org.gnome.desktop.interface monospace-font-name "$MONO_FONT"
    fi
    
    # Set the wallpaper
    WALLPAPER_FILE=$(xrescat regolith.wallpaper.file)
    WALLPAPER_PRIMARY_COLOR=$(xrescat regolith.wallpaper.color.primary)
    if [[ -f "$WALLPAPER_FILE" ]]; then
        gsettings set org.gnome.desktop.background picture-uri "file://$(eval echo $WALLPAPER_FILE)"
    elif [[ -n "$WALLPAPER_PRIMARY_COLOR" ]]; then
        gsettings set org.gnome.desktop.background picture-uri none        
        gsettings set org.gnome.desktop.background primary-color "$WALLPAPER_PRIMARY_COLOR"

        WALLPAPER_SECONDARY_COLOR=$(xrescat regolith.wallpaper.color.secondary)
        WALLPAPER_COLOR_SHADE_TYPE=$(xrescat regolith.wallpaper.color.shading.type)

        if [[ -n "$WALLPAPER_SECONDARY_COLOR" ]] && [[ -n "$WALLPAPER_COLOR_SHADE_TYPE" ]]; then
          gsettings set org.gnome.desktop.background secondary-color "$WALLPAPER_SECONDARY_COLOR"
          gsettings set org.gnome.desktop.background color-shading-type "$WALLPAPER_COLOR_SHADE_TYPE"
        else
            gsettings set org.gnome.desktop.background color-shading-type 'solid'
        fi
    fi

    # Configure the gnome-terminal profile
    if hash gnome-terminal 2>/dev/null; then # Check if gnome-terminal is on the path
        UPDATE_TERM_FLAG=$(xrescat gnome.terminal.update true)
        if [[ "$UPDATE_TERM_FLAG" == "true" && -f "/usr/share/regolith-ftue/regolith-init-term-profile" ]] ; then
            /usr/share/regolith-ftue/regolith-init-term-profile
        fi
    fi
}
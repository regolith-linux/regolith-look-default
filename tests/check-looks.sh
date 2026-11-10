#!/bin/sh
# Static checks over every look shipped by this source package.
# Run from the top of the source tree (debian/rules runs it at build time).
set -eu

LOOK_ROOT=usr/share/regolith-look
status=0
count=0
# Nerd Fonts 3 dropped the legacy Material Design range (nf-mdi-*,
# U+F500-U+FD46): its code points render as tofu or as another icon.
# This matches their UTF-8 encoding, EF 94 80 to EF B5 86.
LEGACY_MDI=$(printf '\357[\224-\264][\200-\277]|\357\265[\200-\206]')

for dir in "$LOOK_ROOT"/*/; do
    look=$(basename "$dir")
    root="$dir/root"
    count=$((count + 1))

    if [ ! -f "$root" ]; then
        echo "FAIL $look: missing root" >&2
        status=1
        continue
    fi

    # GTK4/libadwaita apps only follow org.gnome.desktop.interface color-scheme,
    # which the look loader sets from gtk.color_scheme.
    scheme=$(sed -n 's/^gtk\.color_scheme:[[:space:]]*\([^[:space:]]*\)[[:space:]]*$/\1/p' "$root")
    case "$scheme" in
        default|prefer-dark|prefer-light) echo "ok   $look: gtk.color_scheme $scheme" ;;
        "") echo "FAIL $look: gtk.color_scheme is not set" >&2; status=1 ;;
        *) echo "FAIL $look: invalid gtk.color_scheme '$scheme'" >&2; status=1 ;;
    esac

    # Glyphs must use the Nerd Fonts 3 code points (nf-md-* is U+F0001 and up).
    legacy=$(LC_ALL=C grep -rnI -E "$LEGACY_MDI" "$dir" || true)
    if [ -n "$legacy" ]; then
        echo "FAIL $look: legacy Nerd Fonts Material Design code points (U+F500-U+FD46):" >&2
        printf '%s\n' "$legacy" >&2
        status=1
    else
        echo "ok   $look: no legacy Nerd Fonts Material Design code points"
    fi
done

if [ "$count" -eq 0 ]; then
    echo "FAIL no looks found under $LOOK_ROOT" >&2
    exit 1
fi

exit "$status"

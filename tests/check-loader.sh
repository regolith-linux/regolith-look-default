#!/bin/bash
# Run load_look() from default_loader.sh against stand-ins for xrescat and
# gsettings, and check the org.gnome.desktop.background keys it writes.
# Run from the top of the source tree (debian/rules runs it at build time).
set -eu

LOADER=$PWD/usr/share/regolith-look/default_loader.sh
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
status=0

mkdir -p "$WORK/bin"
touch "$WORK/wall.png"

# xrescat <key> [default]: print the value from $WORK/resources
cat > "$WORK/bin/xrescat" <<'EOF'
#!/bin/sh
value=$(sed -n "s/^$1:[[:space:]]*//p" "$STUB_RESOURCES" | tail -n 1)
if [ -n "$value" ]; then printf '%s\n' "$value"; elif [ -n "${2-}" ]; then printf '%s\n' "$2"; fi
EOF

# gsettings list-keys <schema> | set <schema> <key> <value>
cat > "$WORK/bin/gsettings" <<'EOF'
#!/bin/sh
case "$1" in
    list-keys)
        if [ "$2" = org.gnome.desktop.background ]; then
            printf '%s\n' $STUB_BACKGROUND_KEYS
        else
            printf '%s\n' color-scheme gtk-theme
        fi ;;
    set) printf '%s %s %s\n' "$2" "$3" "$4" >> "$STUB_LOG" ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$WORK/bin/xrescat" "$WORK/bin/gsettings"

export STUB_RESOURCES=$WORK/resources STUB_LOG=$WORK/log
ALL_KEYS="picture-uri picture-uri-dark picture-options primary-color secondary-color color-shading-type"

# run_loader <background keys> <resources...>: run load_look in a fresh shell
run_loader() {
    keys=$1; shift
    printf '%s\n' "$@" 'gnome.terminal.update: false' > "$STUB_RESOURCES"
    : > "$STUB_LOG"
    STUB_BACKGROUND_KEYS=$keys XDG_SESSION_TYPE=x11 PATH="$WORK/bin:$PATH" \
        bash -c 'source "$1"; load_look' loader "$LOADER"
}

# expect <description> <line>: the log has this line
expect() {
    if grep -qxF "$2" "$STUB_LOG"; then
        echo "ok   $1"
    else
        echo "FAIL $1: no '$2' in:" >&2
        sed 's/^/       /' "$STUB_LOG" >&2
        status=1
    fi
}

# expect_none <description> <key>: the key is never written
expect_none() {
    if grep -q "^org.gnome.desktop.background $2 " "$STUB_LOG"; then
        echo "FAIL $1: $2 written" >&2
        status=1
    else
        echo "ok   $1"
    fi
}

run_loader "$ALL_KEYS" "regolith.wallpaper.file: $WORK/wall.png" 'regolith.wallpaper.options: zoom'
expect 'wallpaper: picture-uri' "org.gnome.desktop.background picture-uri file://$WORK/wall.png"
expect 'wallpaper: picture-uri-dark (dark style)' "org.gnome.desktop.background picture-uri-dark file://$WORK/wall.png"
expect 'wallpaper: picture-options' 'org.gnome.desktop.background picture-options zoom'

run_loader "${ALL_KEYS/picture-uri-dark /}" "regolith.wallpaper.file: $WORK/wall.png"
expect 'wallpaper, no picture-uri-dark key: picture-uri' "org.gnome.desktop.background picture-uri file://$WORK/wall.png"
expect_none 'wallpaper, no picture-uri-dark key: not written' picture-uri-dark

run_loader "$ALL_KEYS" 'regolith.wallpaper.color.primary: #102030'
expect 'color: picture-uri' 'org.gnome.desktop.background picture-uri none'
expect 'color: picture-options (no picture in either style)' 'org.gnome.desktop.background picture-options none'
expect 'color: primary-color' 'org.gnome.desktop.background primary-color #102030'

run_loader "$ALL_KEYS" 'regolith.wallpaper.file: /nonexistent/wall.png' 2> /dev/null
expect_none 'missing wallpaper file: picture-uri not written' picture-uri
expect_none 'missing wallpaper file: picture-uri-dark not written' picture-uri-dark

exit "$status"

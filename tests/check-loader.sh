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
# Names that are not valid in a URI as they stand
touch "$WORK/wall%20paper.png" "$WORK/wall#paper.png" "$WORK/wall?paper.png" \
      "$WORK/wall paper.png" "$WORK/wallé.png"

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

# run_loader <background keys> <resources...>: run load_look in a fresh shell,
# with the terminals left alone
run_loader() {
    keys=$1; shift
    printf '%s\n' "$@" 'gnome.terminal.update: false' 'ptyxis.terminal.update: false' \
        'foot.terminal.update: false' > "$STUB_RESOURCES"
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

# Each invalid path is reported with its own name, one message per line
run_loader "$ALL_KEYS" 'regolith.wallpaper.file: /missing/desktop.png' \
    'regolith.lockscreen.wallpaper.file: /missing/lock.png' 2> "$WORK/stderr"
for line in 'Path to wallpaper file (/missing/desktop.png) is invalid' \
            'Path to lockscreen wallpaper file (/missing/lock.png) is invalid'; do
    if grep -qxF "$line" "$WORK/stderr"; then
        echo "ok   invalid path diagnostic: $line"
    else
        echo "FAIL invalid path diagnostic: no '$line' in:" >&2
        sed 's/^/       /' "$WORK/stderr" >&2
        status=1
    fi
done

# A file name must reach GNOME percent-encoded, otherwise the URI names
# another file ('%20' decodes to a space) or is cut at '#' or '?'
for name in 'wall%20paper.png:wall%2520paper.png' 'wall#paper.png:wall%23paper.png' \
            'wall?paper.png:wall%3Fpaper.png' 'wall paper.png:wall%20paper.png' \
            'wallé.png:wall%C3%A9.png'; do
    file=${name%%:*} encoded=${name#*:}
    run_loader "$ALL_KEYS" "regolith.wallpaper.file: $WORK/$file" \
        "regolith.lockscreen.wallpaper.file: $WORK/$file"
    expect "wallpaper '$file': picture-uri" "org.gnome.desktop.background picture-uri file://$WORK/$encoded"
    expect "wallpaper '$file': picture-uri-dark" "org.gnome.desktop.background picture-uri-dark file://$WORK/$encoded"
    expect "lockscreen wallpaper '$file': picture-uri" "org.gnome.desktop.screensaver picture-uri file://$WORK/$encoded"
done

# The terminal loader with Ptyxis left alone: foot's look file, and the
# include line in foot.ini. gnome.terminal.font stays unset.
TERMINAL_LOADER=$PWD/usr/share/regolith-look/terminal_loader.sh
FOOT_DIR=$WORK/config/foot
FOOT_LOOK=$FOOT_DIR/regolith-look.ini
PALETTE=('gnome.terminal.color0: #abc' 'gnome.terminal.color1: #123456789'
         'gnome.terminal.color2: #FFFF0000FFFF' 'gnome.terminal.color3: #c0ffee ')
for i in 4 5 6 7 8 9 10 11 12 13 14 15; do
    PALETTE+=("gnome.terminal.color$i: #0000$((i + 10))")
done

# run_terminals <resources...>: run the terminal loader in a fresh shell
run_terminals() {
    printf '%s\n' "$@" 'ptyxis.terminal.update: false' > "$STUB_RESOURCES"
    XDG_SESSION_TYPE=x11 XDG_CONFIG_HOME=$WORK/config PATH="$WORK/bin:$PATH" \
        bash "$TERMINAL_LOADER"
}

# expect_in <description> <file> <line>: the file has this line
expect_in() {
    if grep -qxF -- "$3" "$2" 2>/dev/null; then
        echo "ok   $1"
    else
        echo "FAIL $1: no '$3' in $2" >&2
        status=1
    fi
}

run_terminals "${PALETTE[@]}" 'gnome.terminal.background-color: banana' \
    'gnome.terminal.use-transparent-background: true' \
    'gnome.terminal.background-transparency-percent: 20'
expect_in 'foot: #RGB colour' "$FOOT_LOOK" 'regular0=AABBCC'
expect_in 'foot: #RRRGGGBBB colour' "$FOOT_LOOK" 'regular1=124578'
expect_in 'foot: #RRRRGGGGBBBB colour' "$FOOT_LOOK" 'regular2=FF00FF'
expect_in 'foot: blanks around a colour' "$FOOT_LOOK" 'regular3=C0FFEE'
expect_in 'foot: bright colours' "$FOOT_LOOK" 'bright7=000025'
expect_in 'foot: unusable background-color falls back to color0' "$FOOT_LOOK" 'background=AABBCC'
expect_in 'foot: foreground defaults to color7' "$FOOT_LOOK" 'foreground=000017'
expect_in 'foot: cursor' "$FOOT_LOOK" 'cursor=124578 000018'
expect_in 'foot: transparency' "$FOOT_LOOK" 'alpha=0.8'
expect_in 'foot: new foot.ini includes the look' "$FOOT_DIR/foot.ini" "include=$FOOT_LOOK"

run_terminals "${PALETTE[@]}" 'gnome.terminal.use-transparent-background: true' \
    'gnome.terminal.background-transparency-percent: '
expect_in 'foot: blank transparency percent means 4' "$FOOT_LOOK" 'alpha=0.96'

# The user's foot.ini follows the include line byte for byte, keeps its
# mode, and gets the line once
printf 'font=Hack 12\n[colors]\nregular1=112233' > "$FOOT_DIR/foot.ini"
chmod 600 "$FOOT_DIR/foot.ini"
run_terminals "${PALETTE[@]}"
run_terminals "${PALETTE[@]}"
expected=$(printf 'include=%s\nfont=Hack 12\n[colors]\nregular1=112233' "$FOOT_LOOK"; echo .)
actual=$(cat "$FOOT_DIR/foot.ini"; echo .)
if [ "$actual" = "$expected" ] && [ "$(stat -c %a "$FOOT_DIR/foot.ini")" = 600 ]; then
    echo "ok   foot: user foot.ini includes the look first"
else
    echo "FAIL foot: user foot.ini changed otherwise:" >&2
    sed 's/^/       /' "$FOOT_DIR/foot.ini" >&2
    status=1
fi

# A palette entry that is missing changes nothing, and is named
rm -rf "$WORK/config"
if run_terminals "${PALETTE[@]:1}" 2> "$WORK/stderr" || ! grep -q 'gnome\.terminal\.color0\b' "$WORK/stderr" ||
   [ -e "$FOOT_DIR" ]; then
    echo "FAIL foot: missing color0 not reported, or files written:" >&2
    sed 's/^/       /' "$WORK/stderr" >&2
    status=1
else
    echo "ok   foot: missing color0 changes nothing"
fi

exit "$status"

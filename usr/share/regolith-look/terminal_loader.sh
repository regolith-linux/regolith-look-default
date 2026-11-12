#! /bin/bash

# Theme Ptyxis and foot from the active look. load_look runs this script on
# every look change and at the first login of each session.
#
# The colours and the font are the look's gnome.terminal.* resources, which
# regolith-ftue also gives GNOME Terminal: color0 to color15, background-color
# (else color0), foreground-color (else color7), font,
# use-transparent-background and background-transparency-percent. Setting
# ptyxis.terminal.update or foot.terminal.update to anything but true leaves
# that terminal alone.
#
# Problems are reported on stderr. The look never fails because of them.
set -u -o pipefail

RESOURCE_GETTER="xrescat"
if [[ ${XDG_SESSION_TYPE-} == "wayland" ]]; then
    RESOURCE_GETTER="trawlcat"
fi

PTYXIS_PALETTE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/org.gnome.Ptyxis/palettes"
# The value this script last gave each Ptyxis setting it manages, and the
# palette file it wrote, one name=value line each
PTYXIS_STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/regolith/ptyxis-look"
# Seconds a running Ptyxis gets to load a new palette file before the profile
# names it. Ptyxis notices new palette files asynchronously, and a window
# whose profile names a palette it hasn't loaded falls back to the default
# palette and stays there.
PTYXIS_PALETTE_LOAD_DELAY=0.5

FOOT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/foot"
FOOT_LOOK_FILE="$FOOT_DIR/regolith-look.ini"

# The mode the umask gives a new file
FILE_MODE=$(printf '%04o' $(( 0666 & ~$(umask) )))

# The look, set by read_look: COLOURS holds color0 to color15, all colours
# as RRGGBB, and OPACITY is a number from 0 to 1
COLOURS=()
BACKGROUND=
FOREGROUND=
OPACITY=
FONT=
MONO_FONT=

declare -A PTYXIS_STATE=()
PTYXIS_STORED=

# resource <name> [<default>]: print a resource without blanks around it, or
# the default when it is missing or blank. trawlcat reports an empty value as
# missing, and xrescat must give the same result.
resource() {
    local value
    value=$("$RESOURCE_GETTER" "$1") || value=
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    printf '%s' "${value:-${2-}}"
}

# hex_colour <variable> <text>: set the variable to the RRGGBB of a #RGB,
# #RRGGBB, #RRRGGGBBB or #RRRRGGGGBBBB colour, read as Pango reads it: the
# digits of a channel repeat to fill 16 bits, of which the top 8 count.
# Anything else fails.
hex_colour() {
    local digits=${2#\#} width i channel rgb=
    [[ $2 == \#* && $digits =~ ^[0-9A-Fa-f]+$ ]] || return 1
    case ${#digits} in
        3|6|9|12) width=$(( ${#digits} / 3 )) ;;
        *) return 1 ;;
    esac
    for (( i = 0; i < 3; i++ )); do
        channel=${digits:i*width:width}
        channel=$channel$channel
        rgb+=${channel:0:2}
    done
    printf -v "$1" '%s' "${rgb^^}"
}

# read_look: read the look's terminal resources. A palette entry that is
# missing or not a colour is reported, and fails it.
read_look() {
    local i name value status=0
    for (( i = 0; i < 16; i++ )); do
        name=gnome.terminal.color$i
        value=$(resource "$name")
        if [[ -z $value ]]; then
            printf 'Not theming Ptyxis and foot: %s is not set\n' "$name" >&2
            status=1
        elif ! hex_colour "COLOURS[$i]" "$value"; then
            printf "Not theming Ptyxis and foot: %s is not a colour: '%s'\n" "$name" "$value" >&2
            status=1
        fi
    done
    (( status == 0 )) || return 1

    hex_colour BACKGROUND "$(resource gnome.terminal.background-color)" || BACKGROUND=${COLOURS[0]}
    hex_colour FOREGROUND "$(resource gnome.terminal.foreground-color)" || FOREGROUND=${COLOURS[7]}

    # GNOME Terminal's transparency: N percent, 4 when not set
    OPACITY=1.0
    if [[ $(resource gnome.terminal.use-transparent-background) == true ]]; then
        value=$(resource gnome.terminal.background-transparency-percent 4)
        if [[ $value =~ ^0*([0-9]{1,3})$ ]] && (( 10#${BASH_REMATCH[1]} <= 100 )); then
            value=$(( 100 - 10#${BASH_REMATCH[1]} ))
            if (( value < 100 )); then
                printf -v OPACITY '0.%02d' "$value"
                OPACITY=${OPACITY%0}
            fi
        fi
    fi

    FONT=$(resource gnome.terminal.font)
    MONO_FONT=$(resource gtk.monospace_font_name)
}

# write_file <path> <text>: make the file hold the text and a final newline.
# It is replaced in one step, and only when it holds something else.
write_file() {
    local path=$1 text=$2$'\n' current='' tmp
    if [[ -f $path && -r $path ]]; then
        IFS= read -r -d '' current < "$path"
        [[ $current == "$text" ]] && return 0
    fi
    tmp=$(mktemp -- "${path%/*}/.${path##*/}.XXXXXX") || return 1
    if printf '%s' "$text" > "$tmp" && chmod -- "$FILE_MODE" "$tmp" &&
       mv -f -- "$tmp" "$path"; then
        return 0
    fi
    rm -f -- "$tmp"
    return 1
}

# gvariant_string <text>: print the text as a GVariant string
gvariant_string() {
    local text=${1//\\/\\\\}
    printf "'%s'" "${text//\'/\\\'}"
}

# gvariant_strings <array> <text>: set the array to the items of a GVariant
# string array as gsettings prints it, such as "['a', 'b']" or "@as []"
gvariant_strings() {
    local -n items=$1
    local rest=${2#@as }
    items=()
    [[ $rest == \[*\] ]] || return 1
    rest=${rest:1:-1}
    while [[ $rest =~ ^[[:space:]]*\'([^\'\\]*)\'[[:space:]]*(,|$) ]]; do
        items+=("${BASH_REMATCH[1]}")
        rest=${rest:${#BASH_REMATCH[0]}}
    done
    [[ -z ${rest//[[:space:]]/} ]]
}

# ---------------------------------------------------------------------------
# Ptyxis
# ---------------------------------------------------------------------------

# Whether GSettings knows Ptyxis's schema
ptyxis_installed() {
    gsettings list-keys org.gnome.Ptyxis &>/dev/null
}

# Whether Ptyxis runs on this session bus. Only the bus is asked: a call to
# Ptyxis itself would start it.
ptyxis_running() {
    local reply
    reply=$(gdbus call --session --dest org.freedesktop.DBus \
        --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.NameHasOwner org.gnome.Ptyxis 2>/dev/null) || return 0
    [[ $reply != '(false,)' ]]
}

read_ptyxis_state() {
    local line
    [[ -f $PTYXIS_STATE_FILE ]] || return 0
    while IFS= read -r line; do
        if [[ $line =~ ^([a-z-]+)=(.*)$ ]]; then
            PTYXIS_STATE[${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}
        fi
    done < "$PTYXIS_STATE_FILE"
}

write_ptyxis_state() {
    local name text=
    for name in profile palette opacity font-name use-system-font palette-file; do
        if [[ -n ${PTYXIS_STATE[$name]-} ]]; then
            text+="$name=${PTYXIS_STATE[$name]}"$'\n'
        fi
    done
    mkdir -p -- "${PTYXIS_STATE_FILE%/*}" && write_file "$PTYXIS_STATE_FILE" "${text%$'\n'}"
}

# ptyxis_owns <name> <dconf key>: whether a setting is the loader's to change:
# it has no value stored for the user, or still holds the value the loader
# last gave it. Any other value is the user's choice. Leaves the stored
# value, if any, in PTYXIS_STORED.
ptyxis_owns() {
    PTYXIS_STORED=$(dconf read "$2") || return 1
    [[ -z $PTYXIS_STORED || $PTYXIS_STORED == "${PTYXIS_STATE[$1]-}" ]]
}

# ptyxis_give <name> <schema> <dconf key> <key> <GVariant value>: set a
# setting, and remember the value it now holds
ptyxis_give() {
    local given
    gsettings set "$2" "$4" "$5" && given=$(dconf read "$3") || return 1
    PTYXIS_STATE[$1]=$given
}

# find_ptyxis_profile: print the look's profile, the first one labelled
# Regolith. Without one, a new profile is added at the end of the list and
# becomes the default.
find_ptyxis_profile() {
    local list ids id label
    list=$(gsettings get org.gnome.Ptyxis profile-uuids) || return 1
    if ! gvariant_strings ids "$list"; then
        printf 'Not theming Ptyxis: cannot read its profile list %s\n' "$list" >&2
        return 1
    fi
    for id in "${ids[@]}"; do
        label=$(gsettings get "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$id/" label 2>/dev/null) || continue
        if [[ $label == "'Regolith'" ]]; then
            printf '%s\n' "$id"
            return 0
        fi
    done

    id=$(uuidgen) || return 1
    id=${id//-/}
    id=${id,,}
    [[ $id =~ ^[0-9a-f]{32}$ ]] || return 1
    ids+=("$id")
    printf -v list "'%s', " "${ids[@]}"
    gsettings set "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$id/" label "'Regolith'" &&
        gsettings set org.gnome.Ptyxis profile-uuids "[${list%, }]" &&
        gsettings set org.gnome.Ptyxis default-profile-uuid "'$id'" || return 1
    printf '%s\n' "$id"
}

ptyxis_palette() {
    local i
    printf '[Palette]\nName=Regolith\n'
    printf 'Background=#%s\nForeground=#%s\n' "$BACKGROUND" "$FOREGROUND"
    for (( i = 0; i < 16; i++ )); do
        printf 'Color%d=#%s\n' "$i" "${COLOURS[i]}"
    done
    printf 'CursorBackground=#%s\nCursorForeground=#%s' "${COLOURS[8]}" "${COLOURS[1]}"
}

# Give the look's profile the look's palette, opacity and font. The palette
# file is named after its content, so an open window sees a new name, and so
# a change, whenever the colours change.
theme_ptyxis() {
    local palette id old profile path schema status=0
    read_ptyxis_state

    palette=$(ptyxis_palette)
    id=$(printf '%s\n' "$palette" | sha256sum) || return 1
    id=regolith-look-${id:0:16}
    if ! mkdir -p -- "$PTYXIS_PALETTE_DIR" || ! write_file "$PTYXIS_PALETTE_DIR/$id.palette" "$palette"; then
        printf 'Not theming Ptyxis: cannot write %s\n' "$PTYXIS_PALETTE_DIR/$id.palette" >&2
        return 1
    fi

    profile=$(find_ptyxis_profile) || return 1
    path=/org/gnome/Ptyxis/Profiles/$profile/
    schema=org.gnome.Ptyxis.Profile:$path
    if [[ ${PTYXIS_STATE[profile]-} != "$profile" ]]; then
        unset 'PTYXIS_STATE[palette]' 'PTYXIS_STATE[opacity]'
        PTYXIS_STATE[profile]=$profile
    fi

    if ptyxis_owns palette "${path}palette" && [[ $PTYXIS_STORED != "'$id'" ]]; then
        if ptyxis_running; then
            sleep "$PTYXIS_PALETTE_LOAD_DELAY"
        fi
        ptyxis_give palette "$schema" "${path}palette" palette "'$id'" || status=1
    fi
    if ptyxis_owns opacity "${path}opacity"; then
        ptyxis_give opacity "$schema" "${path}opacity" opacity "$OPACITY" || status=1
    fi

    # Ptyxis follows the desktop's monospace font, which the loader sets,
    # unless the look gives the terminal another one
    if [[ -n $FONT && $FONT != "$MONO_FONT" ]]; then
        if ptyxis_owns font-name /org/gnome/Ptyxis/font-name; then
            ptyxis_give font-name org.gnome.Ptyxis /org/gnome/Ptyxis/font-name font-name \
                "$(gvariant_string "$FONT")" || status=1
        fi
        if ptyxis_owns use-system-font /org/gnome/Ptyxis/use-system-font; then
            ptyxis_give use-system-font org.gnome.Ptyxis /org/gnome/Ptyxis/use-system-font \
                use-system-font false || status=1
        fi
    elif ptyxis_owns use-system-font /org/gnome/Ptyxis/use-system-font; then
        ptyxis_give use-system-font org.gnome.Ptyxis /org/gnome/Ptyxis/use-system-font \
            use-system-font true || status=1
    fi

    # The palettes directory keeps one file of the loader's: this look's
    old=${PTYXIS_STATE[palette-file]-}
    if [[ $old != "$id" && $old =~ ^regolith-look-[0-9a-f]+$ ]]; then
        rm -f -- "$PTYXIS_PALETTE_DIR/$old.palette"
    fi
    PTYXIS_STATE[palette-file]=$id
    if ! write_ptyxis_state; then
        printf 'Cannot write %s: Ptyxis settings may be taken for your own\n' "$PTYXIS_STATE_FILE" >&2
        status=1
    fi
    return "$status"
}

# ---------------------------------------------------------------------------
# foot
# ---------------------------------------------------------------------------

# foot_font <Pango font description>: print the font as foot's fontconfig
# patterns: one per family, each with the description's weight, slant, width
# and size
foot_font() {
    python3 -I - "$1" <<'EOF'
import re
import sys

import gi

gi.require_version("Pango", "1.0")
from gi.repository import Pango

# fontconfig's FcWeightFromOpenType(): (OpenType weight, fontconfig weight)
WEIGHTS = ((0, 0), (100, 0), (200, 40), (300, 50), (350, 55), (380, 75), (400, 80),
           (500, 100), (600, 180), (700, 200), (800, 205), (900, 210), (1000, 215))
SLANTS = {Pango.Style.NORMAL: 0, Pango.Style.OBLIQUE: 110, Pango.Style.ITALIC: 100}
WIDTHS = (50, 63, 75, 87, 100, 113, 125, 150, 200)


def fc_weight(weight):
    weight = min(weight, WEIGHTS[-1][0])
    for (ot_low, fc_low), (ot_high, fc_high) in zip(WEIGHTS, WEIGHTS[1:]):
        if weight <= ot_high:
            fc = fc_low + (weight - ot_low) * (fc_high - fc_low) / (ot_high - ot_low)
            return int(fc + 0.5)


def number(value):
    text = repr(value)
    return text[:-2] if text.endswith(".0") else text


desc = Pango.FontDescription.from_string(sys.argv[1])
style = ":weight=%d:slant=%d:width=%d" % (
    fc_weight(int(desc.get_weight())),
    SLANTS.get(desc.get_style(), 0),
    WIDTHS[int(desc.get_stretch())],
)
if desc.get_set_fields() & Pango.FontMask.SIZE and desc.get_size() > 0:
    kind = "pixelsize" if desc.get_size_is_absolute() else "size"
    style += ":%s=%s" % (kind, number(desc.get_size() / Pango.SCALE))
families = [family.strip() for family in (desc.get_family() or "").split(",")]
families = [family for family in families if family] or ["monospace"]
print(",".join(re.sub(r"([\\:,-])", r"\\\1", family) + style for family in families))
EOF
}

foot_look() {
    local i font
    printf '# foot settings from the active Regolith look, which the look loader\n'
    printf '# writes on every look change. Put your own settings in foot.ini.\n'
    if [[ -n $FONT ]]; then
        if font=$(foot_font "$FONT") && [[ -n $font ]]; then
            printf '\n[main]\nfont=%s\n' "$font"
        else
            printf "Not giving foot the terminal font: cannot read '%s'\n" "$FONT" >&2
        fi
    fi
    printf '\n[colors]\nbackground=%s\nforeground=%s\n' "$BACKGROUND" "$FOREGROUND"
    for (( i = 0; i < 8; i++ )); do
        printf 'regular%d=%s\n' "$i" "${COLOURS[i]}"
    done
    for (( i = 0; i < 8; i++ )); do
        printf 'bright%d=%s\n' "$i" "${COLOURS[i + 8]}"
    done
    printf 'cursor=%s %s\n' "${COLOURS[1]}" "${COLOURS[8]}"
    printf 'selection-foreground=%s\nselection-background=%s\n' "${COLOURS[0]}" "${COLOURS[8]}"
    printf 'alpha=%s' "$OPACITY"
}

# foot_ini_includes_look <file>: whether the file's main section, the part
# before its first section header, includes the look file
foot_ini_includes_look() {
    local line home_form=
    if [[ $FOOT_LOOK_FILE == "$HOME"/* ]]; then
        home_form=\~/${FOOT_LOOK_FILE#"$HOME"/}
    fi
    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line =~ ^[[:space:]]*\[ ]]; then
            return 1
        fi
        if [[ $line =~ ^[[:space:]]*include[[:space:]]*=[[:space:]]*(.*[^[:space:]]) ]] &&
           [[ ${BASH_REMATCH[1]} == "$FOOT_LOOK_FILE" || ${BASH_REMATCH[1]} == "$home_form" ]]; then
            return 0
        fi
    done < "$1"
    return 1
}

# include_foot_look <foot.ini>: make foot.ini include the look file. The line
# goes first, so the user's own settings, which follow it, win. The file a
# symlink points to is the one edited.
include_foot_look() {
    local ini=$1 target tmp
    if ! target=$(readlink -f -- "$ini"); then
        printf 'Cannot resolve %s, so foot does not follow the look\n' "$ini" >&2
        return 1
    fi
    if [[ ! -e $target ]]; then
        write_file "$target" "include=$FOOT_LOOK_FILE" && return 0
        printf 'Cannot write %s, so foot does not follow the look\n' "$ini" >&2
        return 1
    fi
    if [[ ! -f $target || ! -r $target || ! -w $target ]]; then
        printf 'Cannot read and write %s, so foot does not follow the look\n' "$ini" >&2
        return 1
    fi
    foot_ini_includes_look "$target" && return 0

    if tmp=$(mktemp -- "${target%/*}/.${target##*/}.XXXXXX"); then
        if { printf 'include=%s\n' "$FOOT_LOOK_FILE" && cat -- "$target"; } > "$tmp" &&
           chmod --reference="$target" -- "$tmp" && mv -f -- "$tmp" "$target"; then
            return 0
        fi
        rm -f -- "$tmp"
    fi
    printf 'Cannot write %s, so foot does not follow the look\n' "$ini" >&2
    return 1
}

# Write the look file, and include it from foot.ini, which foot reads when it
# starts. Open foot windows keep their colours.
theme_foot() {
    local look
    look=$(foot_look)
    if ! mkdir -p -- "$FOOT_DIR" || ! write_file "$FOOT_LOOK_FILE" "$look"; then
        printf 'Not theming foot: cannot write %s\n' "$FOOT_LOOK_FILE" >&2
        return 1
    fi
    include_foot_look "$FOOT_DIR/foot.ini"
}

main() {
    local ptyxis=false foot=false status=0
    if [[ $(resource ptyxis.terminal.update true) == true ]] && ptyxis_installed; then
        ptyxis=true
    fi
    if [[ $(resource foot.terminal.update true) == true ]]; then
        foot=true
    fi
    if [[ $ptyxis == false && $foot == false ]]; then
        return 0
    fi

    # A look with an incomplete palette changes neither terminal
    read_look || return 1
    if [[ $ptyxis == true ]]; then
        theme_ptyxis || status=1
    fi
    if [[ $foot == true ]]; then
        theme_foot || status=1
    fi
    return "$status"
}

main "$@"

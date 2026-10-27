#!/bin/bash
# omarchy-all-backgrounds installer.
#
#   install.sh                     install the command to ~/.local/bin
#   install.sh bind [keys] [dir]   add a keybinding (default: SUPER + CTRL + ALT + SPACE)
#   install.sh menu                add "All Backgrounds" to Omarchy menu → Style
#   install.sh labels              readable labels: clone the image picker and patch it
#   install.sh uninstall           remove everything above

set -euo pipefail

name=omarchy-all-backgrounds
raw=${OMARCHY_ALL_BACKGROUNDS_RAW:-https://raw.githubusercontent.com/priard/omarchy-all-backgrounds/main}
bin_dir=$HOME/.local/bin
bindings=$HOME/.config/hypr/bindings.lua
menu=$HOME/.config/omarchy/extensions/omarchy-menu.jsonc
plugins=$HOME/.config/omarchy/plugins
src_dir=$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)

die() { echo "$name: $*" >&2; exit 1; }

# Use files next to this script (a git checkout), otherwise download them.
fetch() {
  if [[ -f $src_dir/$1 && -f $src_dir/install.sh ]]; then
    cat "$src_dir/$1"
  else
    curl -fsSL "$raw/$1"
  fi
}

install_cmd() {
  command -v omarchy-menu-images >/dev/null || die "omarchy-menu-images not found; this needs Omarchy 4.x"
  mkdir -p "$bin_dir"
  fetch "$name" >"$bin_dir/$name.tmp"
  chmod +x "$bin_dir/$name.tmp"
  mv -f "$bin_dir/$name.tmp" "$bin_dir/$name"
  echo "Installed $bin_dir/$name"
  [[ :$PATH: == *":$bin_dir:"* ]] || echo "Note: $bin_dir is not on your PATH"
}

remove_block() {
  [[ -f $1 ]] && sed -i "/^-- BEGIN $name\$/,/^-- END $name\$/d" "$1"
  return 0
}

bind() {
  local keys=${1:-SUPER + CTRL + ALT + SPACE} dir=${2:-}
  [[ -x $bin_dir/$name ]] || install_cmd
  [[ -f $bindings ]] || die "$bindings not found"
  local cmd=$name
  [[ -n $dir ]] && cmd+=" $(printf '%q' "$dir")"
  remove_block "$bindings"
  printf '%s\n' "-- BEGIN $name" \
    "o.bind(\"$keys\", \"All backgrounds\", \"$cmd\")" \
    "-- END $name" >>"$bindings"
  hyprctl reload >/dev/null 2>&1 || true
  if errors=$(hyprctl configerrors 2>/dev/null) && [[ -n $errors && $errors != *"no errors"* ]]; then
    echo "$errors" >&2
  fi
  echo "Bound $keys → $cmd (in $bindings)"
  echo "Check that the combo was free: omarchy menu keybindings --print | grep -i space"
}

add_menu() {
  [[ -x $bin_dir/$name ]] || install_cmd
  local entry="  \"style.background-all\": {\"icon\":\"󰋩\",\"label\":\"All Backgrounds\",\"aliases\":[\"all-backgrounds\"],\"description\":\"Backgrounds from every theme\",\"action\":\"$name\"},"
  mkdir -p "$(dirname "$menu")"
  [[ -f $menu ]] || printf '{\n}\n' >"$menu"
  sed -i '/"style.background-all"/d' "$menu"
  # Insert right after the opening brace; the menu parser accepts trailing commas.
  awk -v entry="$entry" '!done && /^[[:space:]]*\{/ { print; print entry; done = 1; next } { print }' "$menu" >"$menu.tmp"
  mv -f "$menu.tmp" "$menu"
  omarchy menu refresh >/dev/null 2>&1 || true
  echo "Added Style → All Backgrounds to $menu"
}

picker_clone() {
  local manifest
  for manifest in "$plugins"/*/manifest.json; do
    [[ -f $manifest ]] || continue
    [[ $(jq -r '.omarchy.clonedFrom // empty' "$manifest") == omarchy.image-picker ]] && { dirname "$manifest"; return; }
  done
  return 0
}

labels() {
  local dir fresh=false
  command -v patch >/dev/null || die "needs patch: omarchy pkg add patch"
  dir=$(picker_clone)
  if [[ -z $dir ]]; then
    omarchy plugin clone omarchy.image-picker >/dev/null
    dir=$(picker_clone)
    fresh=true
  fi
  [[ -n $dir ]] || die "could not clone omarchy.image-picker"
  if grep -q "$name" "$dir/ImagePicker.qml"; then
    echo "Labels patch already applied in $dir"
    return
  fi
  if ! fetch image-picker-labels.patch | patch -d "$dir" -p1 --forward --no-backup-if-mismatch -s; then
    $fresh && omarchy plugin remove "$(basename "$dir")" --yes >/dev/null
    die "patch did not apply to this Omarchy version; the stock picker is unchanged"
  fi
  omarchy restart shell >/dev/null 2>&1 || true
  echo "Patched $dir (readable labels)"
}

uninstall() {
  rm -f "$bin_dir/$name"
  rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/$name" "${XDG_CACHE_HOME:-$HOME/.cache}/$name.list"
  rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/$name"
  remove_block "$bindings"
  [[ -f $menu ]] && sed -i '/"style.background-all"/d' "$menu"
  hyprctl reload >/dev/null 2>&1 || true
  local dir
  dir=$(picker_clone)
  if [[ -n $dir ]] && grep -q "$name" "$dir/ImagePicker.qml"; then
    omarchy plugin remove "$(basename "$dir")" --yes
  fi
  echo "Uninstalled $name"
}

case ${1:-install} in
  install) install_cmd ;;
  bind) shift; bind "$@" ;;
  menu) add_menu ;;
  labels) labels ;;
  uninstall) uninstall ;;
  *) sed -n '2,8p' "$0" 2>/dev/null || true; exit 1 ;;
esac

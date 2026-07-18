#!/bin/bash

# Copyright (C) 2026 Alex Frick <alex313031@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# pack_release.sh - flatten the GitHub Actions release artifacts.
#
# actions/upload-artifact always re-zips its payload and gives no control over
# the zip flags, so it can't preserve the toolchains' symlinks. We work around
# that by having each build's --package step make the real zip itself (with
# `zip -y`, storing symlinks as symlinks), then upload-artifact wraps THAT in a
# second zip. A downloaded artifact is therefore double-nested:
#
#     mingw_gcc_linux_i586.zip   (outer, added by upload-artifact)
#     +-- i586.zip               (inner, our --package zip, symlinks preserved)
#         +-- i586/...           (the toolchain)
#
# This script "double-extracts" each artifact and re-zips the inner toolchain
# directory directly -- again with `zip -y` so the symlinks stay symlinks --
# under the SAME outer name, giving a normal single-extract archive:
#
#     mingw_gcc_linux_i586.zip
#     +-- i586/...
#
# The originals are never modified; results land in the output directory.

SCRIPTNAME=$(basename "$0")
SCRIPTVER="2.3.5"

# Colors
YEL='\033[1;33m' # Yellow
CYA='\033[1;96m' # Cyan
RED='\033[1;31m' # Red
GRE='\033[1;32m' # Green
c0='\033[0;00m'  # Reset Text

OUT_DIR=""

show_help() {
  cat <<EOF
Usage:
  $SCRIPTNAME [options] [INPUT ...]

Flattens double-nested GitHub release artifacts (outer.zip -> arch.zip -> arch/)
into single-extract archives (outer.zip -> arch/), preserving symlinks.

INPUT  One or more directories (each *.zip inside is processed) and/or
       individual .zip files. Default: Release

Options:
  -o, --output DIR   Where to write the flattened zips. (default: <input>/packed)
  -h, --help         Show this help.
  --version          Show script version.
EOF
}

die() { printf "${RED}%s${c0}\n" "$1" >&2; exit 1; }

# Resolve a possibly-relative path to an absolute one (the dir must exist).
abspath() { ( cd "$1" && pwd ); }

command -v zip   >/dev/null 2>&1 || die "zip is not installed (need Info-ZIP zip)."
command -v unzip >/dev/null 2>&1 || die "unzip is not installed."

INPUTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    show_help; exit 0 ;;
    --version)    printf "\n %s Version %s \n\n" "$SCRIPTNAME" "$SCRIPTVER"; exit 0 ;;
    -o|--output)  OUT_DIR="$2"; shift 2 ;;
    -o=*|--output=*) OUT_DIR="${1#*=}"; shift ;;
    -*)           die "Unknown option '$1', see --help." ;;
    *)            INPUTS+=("$1"); shift ;;
  esac
done

[ ${#INPUTS[@]} -gt 0 ] || INPUTS=("Release")

# Expand the inputs (dirs -> their *.zip, files -> themselves) into a zip list.
ZIPS=()
for in in "${INPUTS[@]}"; do
  if [ -d "$in" ]; then
    shopt -s nullglob
    for z in "$in"/*.zip; do ZIPS+=("$z"); done
    shopt -u nullglob
  elif [ -f "$in" ]; then
    ZIPS+=("$in")
  else
    die "Input '$in' is neither a directory nor a file."
  fi
done
[ ${#ZIPS[@]} -gt 0 ] || die "No .zip files found in: ${INPUTS[*]}"

# Default output dir: a 'packed' subfolder beside the first input.
if [ -z "$OUT_DIR" ]; then
  first="${INPUTS[0]}"
  [ -d "$first" ] || first=$(dirname "$first")
  OUT_DIR="$first/packed"
fi
mkdir -p "$OUT_DIR" || die "Cannot create output dir '$OUT_DIR'."
OUT_DIR=$(abspath "$OUT_DIR")

# Per-process scratch on the SAME filesystem as the output (these toolchains are
# large, so avoid blowing up a small tmpfs /tmp). Cleaned on exit/interrupt.
WORK=$(mktemp -d "$OUT_DIR/.pack.XXXXXX") || die "Cannot create scratch dir."
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

# Flatten a single artifact. Returns non-zero on any failure (caller continues).
pack_one() {
  local outer="$1"
  local name; name=$(basename "$outer")
  printf "${CYA}==> %s${c0}\n" "$name"

  local stage="$WORK/$name.d"
  rm -rf "$stage"; mkdir -p "$stage/outer" "$stage/inner"

  unzip -q "$outer" -d "$stage/outer" || { printf "${RED}    ! failed to extract outer zip${c0}\n"; return 1; }

  # Find the single inner toolchain zip.
  local inner
  inner=$(find "$stage/outer" -type f -name '*.zip' | head -1)
  if [ -z "$inner" ]; then
    # No nested zip: maybe it's already flattened (contains the dir directly).
    if find "$stage/outer" -mindepth 1 -maxdepth 1 -type d | read -r _; then
      printf "${YEL}    already flat (no inner .zip); copying through${c0}\n"
      cp -a "$outer" "$OUT_DIR/$name"
      return 0
    fi
    printf "${RED}    ! no inner .zip and no top-level dir found${c0}\n"
    return 1
  fi

  unzip -q "$inner" -d "$stage/inner" || { printf "${RED}    ! failed to extract inner zip${c0}\n"; return 1; }

  # Count what we expect to preserve (for verification).
  local src_links src_files
  src_links=$(find "$stage/inner" -type l | wc -l)
  src_files=$(find "$stage/inner" -type f | wc -l)

  # Re-zip the toolchain dir(s) directly. -y keeps symlinks as symlinks (no-op
  # for the Windows builds, which have none). $out is absolute so the subshell's
  # cd doesn't misplace it.
  local out="$OUT_DIR/$name"
  rm -f "$out"
  ( cd "$stage/inner" && zip -r -q -y "$out" ./* ) \
    || { printf "${RED}    ! failed to create flattened zip${c0}\n"; return 1; }

  # Verify the symlink count round-tripped.
  local new_links
  new_links=$(unzip -Z "$out" 2>/dev/null | grep -c '^l')
  local topdirs
  topdirs=$(cd "$stage/inner" && ls -1 | paste -sd, -)

  if [ "$new_links" -ne "$src_links" ]; then
    printf "${RED}    ! symlink mismatch: source has %s, new zip has %s${c0}\n" "$src_links" "$new_links"
    return 1
  fi
  printf "${GRE}    ok${c0} -> %s/  (%s files, %s symlinks)\n" "$topdirs" "$src_files" "$src_links"

  rm -rf "$stage"
  return 0
}

printf "${YEL}Flattening %d artifact(s) into %s${c0}\n\n" "${#ZIPS[@]}" "$OUT_DIR"
ok=0; fail=0
for z in "${ZIPS[@]}"; do
  if pack_one "$z"; then ok=$((ok+1)); else fail=$((fail+1)); fi
done

echo
if [ "$fail" -eq 0 ]; then
  printf "${GRE}Done: %d/%d flattened into %s${c0}\n" "$ok" "${#ZIPS[@]}" "$OUT_DIR"
else
  printf "${RED}Done with errors: %d ok, %d failed (of %d). Output: %s${c0}\n" "$ok" "$fail" "${#ZIPS[@]}" "$OUT_DIR"
  exit 1
fi

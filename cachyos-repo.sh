#!/bin/bash
# Copyright (C) 2022-2024 CachyOS team
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

set -e

if [[ $1 == "--help" ]]; then
cat<<EOF
Usage: cachyos-repo.sh [options]
Options:
  --help                   Display this information.
  --install                Install repo.
  --remove                 Remove repo.
EOF
exit 0
fi

if [ "$EUID" -ne 0 ]; then
  echo "Please, run script with sudo"
  exit 1
fi

if [ ! -f /etc/pacman.conf ]; then
  echo "File [/etc/pacman.conf] not found!"
  exit 1
fi

_install=true
_remove=false
for i in "$@"; do
  case $i in
    --install)
      _install=true
      _remove=false
      shift # past argument=value
      ;;
    --remove)
      _install=false
      _remove=true
      shift # past argument=value
      ;;
    *)
      # unknown option
      echo "Unknown argument: '$i'!"
      exit 1
      ;;
  esac
done

export LC_MESSAGES=C
export LANG=C

disable_colors() {
    unset ALL_OFF BOLD BLUE GREEN RED YELLOW
}

enable_colors() {
    # prefer terminal safe colored and bold text when tput is supported
    if tput setaf 0 &>/dev/null; then
        ALL_OFF="$(tput sgr0)"
        BOLD="$(tput bold)"
        RED="${BOLD}$(tput setaf 1)"
        GREEN="${BOLD}$(tput setaf 2)"
        YELLOW="${BOLD}$(tput setaf 3)"
        BLUE="${BOLD}$(tput setaf 4)"
    else
        ALL_OFF="\e[0m"
        BOLD="\e[1m"
        RED="${BOLD}\e[31m"
        GREEN="${BOLD}\e[32m"
        YELLOW="${BOLD}\e[33m"
        BLUE="${BOLD}\e[34m"
    fi
    readonly ALL_OFF BOLD BLUE GREEN RED YELLOW
}

if [[ -t 2 ]]; then
    enable_colors
else
    disable_colors
fi

msg() {
    local mesg=$1; shift
    printf "${GREEN}==>${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

info() {
    local mesg=$1; shift
    printf "${YELLOW} -->${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

check_supported_isa_level() {
    /lib/ld-linux-x86-64.so.2 --help | grep "$1 (supported, searched)" > /dev/null
    echo $?
}

check_supported_znver45() {
    gcc -march=native -Q --help=target 2>&1 | grep 'march' | grep -E '(znver4|znver5)' > /dev/null
    echo $?
}

check_if_repo_was_added() {
    cat /etc/pacman.conf | grep "(cachyos\|cachyos-v3\|cachyos-core-v3\|cachyos-extra-v3\|cachyos-testing-v3\|cachyos-v4\|cachyos-core-v4\|cachyos-extra-v4\|cachyos-znver4\|cachyos-core-znver4\|cachyos-extra-znver4)" > /dev/null
    echo $?
}

check_if_repo_was_commented() {
    cat /etc/pacman.conf | grep "cachyos\|cachyos-v3\|cachyos-core-v3\|cachyos-extra-v3\|cachyos-testing-v3\|cachyos-v4\|cachyos-core-v4\|cachyos-extra-v4\|cachyos-znver4\|cachyos-core-znver4\|cachyos-extra-znver4" | grep -v "#\[" | grep "\[" > /dev/null
    echo $?
}

add_specific_repo() {
    local isa_level="$1"
    local gawk_script="$2"
    local repo_name="$3"
    local cmd_check="check_supported_isa_level ${isa_level}"

    local pacman_conf="/etc/pacman.conf"
    local pacman_conf_cachyos="./pacman.conf"
    local pacman_conf_path_backup="/etc/pacman.conf.bak"

    local is_isa_supported="$(eval ${cmd_check})"
    if [ $is_isa_supported -eq 0 ]; then
        info "${isa_level} is supported"

        cp $pacman_conf $pacman_conf_cachyos
        gawk -i inplace -f $gawk_script $pacman_conf_cachyos || true

        info "Backup old config"
        mv $pacman_conf $pacman_conf_path_backup

        info "CachyOS ${repo_name} Repo changed"
        mv $pacman_conf_cachyos $pacman_conf
    else
        info "${isa_level} is not supported"
    fi
}

run_install() {
    msg "Installing CachyOS repo.."

    pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
    pacman-key --lsign-key F3B607488DB35A47

    local mirror_url="https://mirror.cachyos.org/repo/x86_64/cachyos"

    pacman -U "${mirror_url}/cachyos-keyring-20240331-1-any.pkg.tar.zst" \
              "${mirror_url}/cachyos-mirrorlist-22-1-any.pkg.tar.zst"    \
              "${mirror_url}/cachyos-v3-mirrorlist-22-1-any.pkg.tar.zst" \
              "${mirror_url}/cachyos-v4-mirrorlist-22-1-any.pkg.tar.zst"  \
              "${mirror_url}/pacman-7.1.0.r9.g54d9411-2-x86_64.pkg.tar.zst"

    local is_repo_added="$(check_if_repo_was_added)"
    local is_repo_commented="$(check_if_repo_was_commented)"
    local is_isa_v4_supported="$(check_supported_isa_level x86-64-v4)"
    local is_znver_supported="$(check_supported_znver45)"
    if [ $is_repo_added -ne 0 ] || [ $is_repo_commented -ne 0 ]; then
        if [ $is_znver_supported -eq 0 ]; then
            add_specific_repo x86-64-v4 ./install-znver4-repo.awk cachyos-znver4
        elif [ $is_isa_v4_supported -eq 0 ]; then
            add_specific_repo x86-64-v4 ./install-v4-repo.awk cachyos-v4
        else
            add_specific_repo x86-64-v3 ./install-repo.awk cachyos-v3
        fi
    else
        info "Repo is already added!"
    fi

    msg "Done installing CachyOS repo."
}

run_remove() {
    msg "Removing CachyOS repo.."

    local pacman_conf="/etc/pacman.conf"
    local pacman_conf_cachyos="./pacman.conf"
    local pacman_conf_path_backup="/etc/pacman.conf.bak"

    local is_repo_added="$(check_if_repo_was_added)"
    local is_repo_commented="$(check_if_repo_was_commented)"
    if [ $is_repo_added -eq 0 ] || [ $is_repo_commented -eq 0 ]; then
        cp $pacman_conf $pacman_conf_cachyos
        gawk -i inplace -f ./remove-repo.awk $pacman_conf_cachyos || true

        info "Backup old config"
        mv $pacman_conf $pacman_conf_path_backup

        info "CachyOS repo removed"
        mv $pacman_conf_cachyos $pacman_conf

        pacman -Suuy
        pacman -S core/pacman
        pacman -Qqn | pacman -S -

        pacman -R "cachyos-keyring"       \
                  "cachyos-mirrorlist"    \
                  "cachyos-v3-mirrorlist" \
                  "cachyos-v4-mirrorlist"

        pacman-key --delete F3B607488DB35A47 || true
    else
        info "Repo is not added!"
    fi

    msg "Done removing CachyOS repo."
}

run() {
    if $_install; then
        run_install
    elif $_remove; then
        run_remove
    fi
    pacman -Syu
}

run

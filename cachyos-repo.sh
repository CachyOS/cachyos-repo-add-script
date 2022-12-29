#!/bin/bash
# Copyright (C) 2022 CachyOS team
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

check_v3_support() {
    /lib/ld-linux-x86-64.so.2 --help | grep "x86-64-v3 (supported, searched)" > /dev/null
    echo $?
}

check_v4_support() {
    /lib/ld-linux-x86-64.so.2 --help | grep "x86-64-v4 (supported, searched)" > /dev/null
    echo $?
}

run_install() {
    msg "Installing CachyOS repo.."

    local pacman_conf="/etc/pacman.conf"
    local pacman_conf_cachyos="./pacman.conf"
    local pacman_conf_path_backup="/etc/pacman.conf.bak"
    local is_v4_supported="$(check_v4_support)"
    local is_v3_supported="$(check_v3_support)"

    sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key F3B607488DB35A47

    sudo pacman -U 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-2-1-any.pkg.tar.zst' 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-13-1-any.pkg.tar.zst' 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v4-mirrorlist-1-1-any.pkg.tar.zst' 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v3-mirrorlist-13-1-any.pkg.tar.zst'

    if [ $is_v3_supported -eq 0 ]; then
        info "x86-64-v3 is supported"

        cp $pacman_conf $pacman_conf_cachyos
        gawk -i inplace -f ./install-repo.awk $pacman_conf_cachyos || true

        info "Backup old config"
        sudo mv $pacman_conf $pacman_conf_path_backup

        info "CachyOS -v3 Repo changed"
        sudo mv $pacman_conf_cachyos $pacman_conf
    else
        info "x86-64-v3 is not supported"
        info "Backup old config"
        sudo mv $pacman_conf $pacman_conf_path_backup

        info "CachyOS Repo changed"
        sudo mv $pacman_conf_cachyos $pacman_conf
    fi

    if [ $is_v4_supported -eq 0 ]; then
        info "x86-64-v4 is supported"

        cp $pacman_conf $pacman_conf_cachyos
        gawk -i inplace -f ./install-v4-repo.awk $pacman_conf_cachyos || true

        info "Backup old config"
        sudo mv $pacman_conf $pacman_conf_path_backup

        info "CachyOS -v4 Repo changed"
        sudo mv $pacman_conf_cachyos $pacman_conf
    else
        info "x86-64-v4 is not supported"
        info "Backup old config"
        sudo mv $pacman_conf $pacman_conf_path_backup

        info "CachyOS Repo changed"
        sudo mv $pacman_conf_cachyos $pacman_conf
    fi

    msg "Done installing CachyOS repo."
}

run_remove() {
    msg "Removing CachyOS repo.."

    local pacman_conf="/etc/pacman.conf"
    local pacman_conf_cachyos="./pacman.conf"
    local pacman_conf_path_backup="/etc/pacman.conf.bak"

    cp $pacman_conf $pacman_conf_cachyos
    gawk -i inplace -f ./remove-repo.awk $pacman_conf_cachyos || true

    info "Backup old config"
    sudo mv $pacman_conf $pacman_conf_path_backup

    info "CachyOS repo removed"
    sudo mv $pacman_conf_cachyos $pacman_conf

    msg "Done removing CachyOS repo."
}

run() {
    if $_install; then
        run_install
    elif $_remove; then
        run_remove
    fi

    yes | pacman -Sy
}

run

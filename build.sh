#!/usr/bin/env bash

set -eu

# Firefly's Linux SDK is very picky about Python versions
PYTHON2_VERSION=2.7.17
PYTHON3_VERSION=3.6.9

# Settings from the command line
DEBUG=0
DISABLE_ENVIRONMENT_CHECK=0

# Gets the path where this script is stored so we can refer to directories and other
# files with relative names in a reasonably safe way
THIS_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "${THIS_SCRIPT_DIR}/utils.sh"

# Displays the command line help and stops execution
function printHelpAndDie() {
    cat <<"EOT"
Usage: $0 [--disable-environment-check] [--debug]"

--disable-environment-check:
  Disables checking for the correct OpenSUSE version and installing tools with zypper. Set this to true if you want to
  run this script under a different environment and you have installed all required tools by yourself. Can also be used
  if calling zypper with sudo is not allowed in your environment.

--debug:
  Activates the DEBUG log level of this script.
EOT
    exit 1
}

# Installs the tools we need to execute all the weird things
function installHostTools() {
    logInfo "Ensuring all scripting and tool versions are at the required versions"
    sudo zypper --quiet install -y \
        git git-lfs coreutils pyenv \
        gcc make patch \
        bc bison dtc fakeroot flex kernel-default-devel
}

function preparePyEnv() {
    # Compile the specific Python versions demanded by the Firefly SDK
    eval "$(pyenv init --path)"

    pyenv install --skip-existing "${PYTHON2_VERSION}"
    pyenv install --skip-existing "${PYTHON3_VERSION}"
}

# Ensures that we are executing in the expected host environment:
# 1. openSUSE >=15 <16
# 2. Architecture x86_64 (because the Firefly Linux kit demands that)
# Feel free to disable this check if you know what you are doing, but don't complain to me :-)
function checkHostDistro() {
    logInfo "Checking if host distribution is OpenSuSE LEAP..."
    if [[ ! -f /etc/os-release ]]; then
        die "Cannot find /etc/os-release to identify the Linux distribution"
    fi
    grep -q 'ID="opensuse-leap"' /etc/os-release \
        || die "The host distribution is expected to be openSUSE Leap"
    local opensuse_version
    # shellcheck disable=SC2016
    opensuse_version="$(grep -P '^VERSION=' /etc/os-release | perl -npe 's#VERSION="([\d\.]+)"#$1#')" ||
        die "Could not find VERSION=\"\" in /etc/os-release"
    logDebug "Found openSUSE version: '${opensuse_version}'"
    version_lte "15" "${opensuse_version}" ||
        die "openSUSE version seems to be less than 15"
    version_lt "${opensuse_version}" "16" ||
        die "openSUSE version seems to be 16 or higher - this script cannot say if we are compatible."
    if [[ "$(uname -m)" != "x86_64" ]]; then
        die "Machine type '$(uname -m)' was found, but this script can only support x86_64. Very sorry."
    fi
}

function cloneFireflyRepos() {
    curl -Ss --fail --url 'https://gitlab.com/firefly-linux/git-repo/-/raw/default/repo?ref_type=heads' \
        --output ~/bin/repo
    chmod 755 ~/bin/repo
    echo "Cloning or updating the Firefly Linux SDK repositories..."
    pyenv global "${PYTHON2_VERSION}" "${PYTHON3_VERSION}"
    /usr/bin/env python -V
    /usr/bin/env python3 -V
    mkdir -p "$THIS_SCRIPT_DIR/work/firefly-linux-sdk"
    cd "$THIS_SCRIPT_DIR/work/firefly-linux-sdk"
    set -x

    # If a file from the last project is already present, assume the initial checkout was successful
    # and directly proceed to updating.

    if [[ ! -f external/rkwifibt/LICENSE ]]; then
        # The "y" is the answer to the question "Enable color display in this user account (y/N)?"
        # which seems to be unable to suppress.
        echo "y" | ~/bin/repo init --no-repo-verify --quiet --no-clone-bundle \
            --repo-url https://gitlab.com/firefly-linux/git-repo.git \
            -u https://gitlab.com/firefly-linux/manifests.git -b master -m rk3588_linux_release.xml
        .repo/repo/repo sync -c --no-tags --quiet
        .repo/repo/repo start firefly --all
    fi

    # Update
    .repo/repo/repo sync -c --no-tags --quiet
}

function read_parameters() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --disable-environment-check)
                DISABLE_ENVIRONMENT_CHECK=1
                ;;
            --debug)
                # shellcheck disable=SC2034
                DEBUG=1
                ;;
            *)
                printHelpAndDie
                ;;
        esac
        shift
    done
}

function compileFireflyRepos {
    cd "${THIS_SCRIPT_DIR}/work/firefly-linux-sdk"
    ln -rfs device/rockchip/rk3588/roc-rk3588-pc-ubuntu.mk device/rockchip/.BoardConfig.mk
    ./build.sh
}

echo "Building an image for running openSUSE Leap 15 on the Firefly ITX-3588 board"
echo "This script is (C) 2024 Andreas Buschka <kontakt@andreas-buschka.de> and licensed under GPL v2"
echo ""

if [[ "$DISABLE_ENVIRONMENT_CHECK" != "1" ]]; then
    checkHostDistro
    installHostTools
fi
preparePyEnv
cloneFireflyRepos
compileFireflyRepos

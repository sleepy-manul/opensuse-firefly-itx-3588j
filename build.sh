#!/usr/bin/env bash

set -eu

DEBUG=1
PYTHON2_VERSION=2.7.17
PYTHON3_VERSION=3.6.9

# Gets the path where this script is stored so we can refer to directories and other
# files with relative names in a reasonably safe way
THIS_SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}")"  &> /dev/null && pwd)
source "${THIS_SCRIPT_DIR}/utils.sh"

# Displays the command line help and stops execution
function printHelpAndDie() {
    cat << "EOT"
Usage: $0 [--disable-environment-check=true|false]"

--disable-environment-check=true|false:
  Disables checking for the correct OpenSUSE version and installing tools with zypper. Set this to true if you want to
  run this script under a different environment and you have installed all required tools by yourself.

--debug=true|false:
  Activates the DEBUG log level of this script.
EOT
    exit 1
}

# Installs the tools we need to execute all the weird things
function installHostTools() {
    logInfo "Ensuring all scripting and tool versions are at the required versions"
    sudo zypper --quiet install git coreutils dirmngr distribution-gpg-keys pyenv \
        gcc make patch

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
    grep 'ID="opensuse-leap"' /etc/os-release || die "The host distribution is expected to be openSUSE Leap"
    local opensuse_version
    # shellcheck disable=SC2016
    opensuse_version="$(grep -P '^VERSION='  /etc/os-release|perl -npe 's#VERSION="([\d\.]+)"#$1#')" || \
        die "Could not find VERSION=\"\" in /etc/os-release"
    logDebug "Found openSUSE version: '${opensuse_version}'"
    version_lte "15" "${opensuse_version}" || \
        die "openSUSE version seems to be less than 15"
    version_lt "${opensuse_version}" "16" || \
        die "openSUSE version seems to be 16 or higher - this script cannot say if we are compatible."
    if [[ "$(uname -m)" != "x86_64" ]]; then
        die "Machine type '$(uname -m)' was found, but this script can only support x86_64. Very sorry."
    fi
}

function cloneFireflyRepo() {
    curl --url 'https://gitlab.com/firefly-linux/git-repo/-/raw/default/repo?ref_type=heads' --output ~/bin/repo
    chmod 755 ~/bin/repo
    echo "Cloning or updating the Firefly Linux SDK repositories..."
    pyenv global "${PYTHON2_VERSION}" "${PYTHON3_VERSION}"
    /usr/bin/env python -V
    /usr/bin/env python3 -V
    mkdir -p "$THIS_SCRIPT_DIR/work/firefly-linux-sdk"
    cd "$THIS_SCRIPT_DIR/work/firefly-linux-sdk"
    set -x
    ~/bin/repo init --no-clone-bundle --repo-url https://gitlab.com/firefly-linux/git-repo.git \
        -u https://gitlab.com/firefly-linux/manifests.git -b master -m rk3588_linux_release.xml
    .repo/repo/repo sync -c --no-tags
    .repo/repo/repo start firefly --all

    # Updating
    .repo/repo/repo sync -c --no-tags
}

echo "Building an image for running openSUSE Leap 15 on the Firefly ITX-3588J-Board"
echo "This script is (C) 2024 Andreas Buschka <kontakt@andreas-buschka.de> and licensed under GPL v2"
echo ""

installHostTools
checkHostDistro
cloneFireflyRepo
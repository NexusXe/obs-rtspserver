#!/bin/bash

##############################################################################
# macOS libobs plugin package function
##############################################################################
#
# This script file can be included in build scripts for macOS or run directly
#
##############################################################################

# Halt on errors
set -eE

package_obs_plugin() {
    if [ "${CODESIGN}" ]; then
        read_codesign_ident
    fi

    status "Package OBS plugin ${PRODUCT_NAME}"
    trap "caught_error 'package_obs_plugin'" ERR

    ensure_dir "${CHECKOUT_DIR}"

    # if [ -d "${BUILD_DIR}/rundir/${PRODUCT_NAME}.plugin" ]; then
    #     rm -rf "${BUILD_DIR}/rundir/${PRODUCT_NAME}.plugin"
    # fi
    if [ -d "${CHECKOUT_DIR}/release" ]; then
        rm -rf "${CHECKOUT_DIR}/release"
    fi

    cmake --install "${BUILD_DIR}" --prefix "${CHECKOUT_DIR}/release"

    if ! type packagesbuild &>/dev/null; then
        status "Setting up dependency Packages.app"
        step "Download..."
        check_and_fetch "http://s.sudre.free.fr/Software/files/Packages.dmg" "6afdd25386295974dad8f078b8f1e41cabebd08e72d970bf92f707c7e48b16c9"
        step "Mount disk image..."
        hdiutil attach -noverify Packages.dmg

        step "Install Packages.app"
        PACKAGES_VOLUME=$(hdiutil info -plist | grep "/Volumes/Packages" | sed 's/<string>\/Volumes\/\([^<]*\)<\/string>/\1/' | sed -e 's/^[[:space:]]*//')
        sudo installer -pkg "/Volumes/${PACKAGES_VOLUME}/packages/Packages.pkg" -target /
        hdiutil detach "/Volumes/${PACKAGES_VOLUME}"
    fi

    step "Package ${PRODUCT_NAME}..."
    cp "${CHECKOUT_DIR}/LICENSE" "${CHECKOUT_DIR}/bundle/LICENSE.txt"
    packagesbuild ./bundle/installer-macos.generated.pkgproj

    ensure_dir "${CHECKOUT_DIR}/release"

    step "Creating zip archive..."
    zip -r9 "${CHECKOUT_DIR}/${BUILD_DIR}/${FILE_NAME}.zip" .
    ensure_dir "${CHECKOUT_DIR}"

    if [ "${CODESIGN}" ]; then
        step "Codesigning installer package..."
        read_codesign_ident_installer

        /usr/bin/productsign --sign "${CODESIGN_IDENT_INSTALLER}" "${BUILD_DIR}/${PRODUCT_NAME}.pkg" "${BUILD_DIR}/${FILE_NAME}.pkg"
    else
        mv "${BUILD_DIR}/${PRODUCT_NAME}.pkg" "${BUILD_DIR}/${FILE_NAME}.pkg"
    fi
}

notarize_obs_plugin() {
    status "Notarize ${PRODUCT_NAME}"
    trap "caught_error 'notarize_obs_plugin'" ERR

    if ! exists brew; then
        error "Homebrew not found - please install homebrew (https://brew.sh)"
        exit 1
    fi

    if ! exists xcnotary; then
        step "Install notarization dependency 'xcnotary'"
        brew install akeru-inc/tap/xcnotary
    fi

    ensure_dir "${CHECKOUT_DIR}"

    if [ -f "${FILE_NAME}" ]; then
        xcnotary precheck "${FILE_NAME}"
    else
        error "No notarization package installer ('${FILE_NAME}') found"
        return
    fi

    if [ "$?" -eq 0 ]; then
        read_codesign_ident_installer
        read_codesign_pass

        step "Run xcnotary with ${FILE_NAME}..."
        xcnotary notarize "${FILE_NAME}" --developer-account "${CODESIGN_IDENT_USER}" --developer-password-keychain-item "OBS-Codesign-Password" --provider "${CODESIGN_IDENT_SHORT}"
    fi
}

package-plugin-standalone() {
    CHECKOUT_DIR="$(/usr/bin/git rev-parse --show-toplevel)"
    if [ -f "${CHECKOUT_DIR}/CI/include/build_environment.sh" ]; then
        source "${CHECKOUT_DIR}/CI/include/build_environment.sh"
    fi
    PRODUCT_NAME="${PRODUCT_NAME:-obs-plugin}"
    source "${CHECKOUT_DIR}/CI/include/build_support.sh"
    source "${CHECKOUT_DIR}/CI/include/build_support_macos.sh"

    GIT_BRANCH=$(/usr/bin/git rev-parse --abbrev-ref HEAD)
    GIT_HASH=$(/usr/bin/git rev-parse --short HEAD)
    GIT_TAG=$(/usr/bin/git describe --tags --always --dirty='-dev')
    GIT_VERSION=$(echo ${GIT_TAG} | grep -Eos '[0-9]+.[0-9]+.[0-9]+(-[a-z0-9]+)*$')

    check_macos_version
    check_archs

    FILE_NAME="${PRODUCT_NAME}-${GIT_TAG:-${PRODUCT_VERSION}}-macos-${ARCH}"

    check_curl
    package_obs_plugin

    if [ "${NOTARIZE}" ]; then
        notarize_obs_plugin
    fi
}

print_usage() {
    echo -e "Usage: ${0}\n" \
            "-h, --help                     : Print this help\n" \
            "-q, --quiet                    : Suppress most build process output\n" \
            "-v, --verbose                  : Enable more verbose build process output\n" \
            "-a, --architecture             : Specify build architecture (default: x86_64, alternative: arm64)\n" \
            "-c, --codesign                 : Codesign OBS and all libraries (default: ad-hoc only)\n" \
            "-n, --notarize                 : Notarize OBS (default: off)\n" \
            "--build-dir                    : Specify alternative build directory (default: build)\n"
}

package-plugin-main() {
    if [ -z "${_RUN_OBS_BUILD_SCRIPT}" ]; then
        while true; do
            case "${1}" in
                -h | --help ) print_usage; exit 0 ;;
                -q | --quiet ) export QUIET=TRUE; shift ;;
                -v | --verbose ) export VERBOSE=TRUE; shift ;;
                -a | --architecture ) ARCH="${2}"; shift 2 ;;
                -c | --codesign ) CODESIGN=TRUE; shift ;;
                -n | --notarize ) NOTARIZE=TRUE; CODESIGN=TRUE; shift ;;
                -s | --standalone ) STANDALONE=TRUE; shift ;;
                --build-dir ) BUILD_DIR="${2}"; shift 2 ;;
                -- ) shift; break ;;
                * ) break ;;
            esac
        done

        package-plugin-standalone
    fi
}

package-plugin-main $*

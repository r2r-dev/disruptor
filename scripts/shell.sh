#!/usr/bin/env sh

# Assumption #1: non-GNU, non-BSD linux distros are out-of-scope
# Otherwise we at least need to get rid of 'local' keyword
# Assumption #2: coreutils are present in $PATH
# Assumption #3: there is internet access (assumption to be removed)

# '-o pipefail' is not POSIX compliant, will fail in some sh's
set -eu

realpath () {
  case "$(uname)" in
    Linux)
      readlink -f -- "$1"
    ;;
    Darwin)
      greadlink -f -- "$1"
    ;;
    *)
     # For esoteric uname returns
     # attempt to run anyways.
     readlink -f -- "$1" 
    ;;
  esac
}

# Find current script location
{
  # Double quoting breaks desired behaviour
  # shellcheck disable=SC2086
  __DIR__=$(dirname "$(realpath $0)")
} || {
  echo "Unable to determine current script location.."
  echo "Will assume '.'"
  __DIR__="."
}

fail() {
  echo "$0:" "$@" >&2
  exit 1
}

# Nicked from https://releases.nixos.org/nix/nix-2.5.1/install
require_util() {
  command -v "$1" > /dev/null 2>&1 ||
    fail "you do not have '$1' installed, which I need to $2"
}

readonly USER_HOME="${HOME:-"HOME variable has not been set"}"
readonly CACHE_ROOT="${__DIR__}/../.cache"
readonly NIX_USER_CHROOT_VERSION="1.2.2"
readonly NIX_USER_CHROOT_DIR="${CACHE_ROOT}/nix-user-chroot"
readonly NIX_USER_CHROOT_BIN="${NIX_USER_CHROOT_DIR}/nix-user-chroot"
readonly NIX_STORE="${CACHE_ROOT}/nix-store"
readonly NIX_VERSION="2.5.1"
readonly NIX_INSTALL_SCRIPT="${CACHE_ROOT}/nix-${NIX_VERSION}-install.sh"
readonly NIX_CONF_DIR="${__DIR__}"
readonly NIX_USER_CONF_FILES=''
readonly DIRENV_CONFIG="${CACHE_ROOT}"
readonly DIRENV_CONF_PATH="${DIRENV_CONFIG}/direnv.toml"
readonly NIX_PATH="nixpkgs=${__DIR__}/nixpkgs.nix"
readonly NIX_SHELL_RC="${CACHE_ROOT}/nix_shell.rc"

IS_NIX_INSTALLED=false
VANILLA_RUN=false

# Check if running on NixOS
if [ -e "/etc/os-release" ]; then
  case "$(cat /etc/os-release)" in 
    *NixOS*)
      readonly IS_NIXOS=true;
    ;;
    *)
      readonly IS_NIXOS=false;
    ;;
  esac
else
  readonly IS_NIXOS=false;
fi

preflightCheck() {
  require_util cat "print text"
  require_util curl "download dependencies"
  require_util getopt "sanatize input params"
  require_util tar "decompress nix installation package"
  case "$(uname)" in
    Darwin)
      require_util nix "make the magic happen. You are running on OSX, please make sure Nix is installed by running the following: sh <(curl -L https://nixos.org/nix/install)."
    ;;
    Linux)
      require_util unshare "verify kernel support for user namespaces"
    ;;
    *)
      echo "Platform not yet supported"
    ;;
  esac
}

printHelp() {
  cat << EOF
   Usage: nix-shell.sh [--vanilla] [--help] -- <PARAMS TO PASS TO NIX-SHELL>

   optional arguments:
     -h, --help           print this message and exit
     -v, --vanilla        drop user in to plain bash shell, with default nix setup
                          (global channel, impure).
EOF
}

setup_nix_user_chroot() {
  # Verify that user namespaces for unprivileged users are enabled
  local readonly are_user_ns_enabled
  are_user_ns_enabled="$(unshare\
   --user --pid echo -n YES \
  )"
  if [ "${are_user_ns_enabled}" != "YES" ]; then
    # TODO: Implement fallback to proot
    fail "Current kernel settings do not allow\
     running user namespaces for unprivileged users."
  fi

  local readonly arch
  arch=$(uname -m)
  case "${arch}" in
    "aarch64")
    local readonly download_url="https://github.com/nix-community\
/nix-user-chroot/releases/download/${NIX_USER_CHROOT_VERSION}\
/nix-user-chroot-bin-${NIX_USER_CHROOT_VERSION}-aarch64-unknown-linux-musl"
    ;;
    "x86_64")
    local readonly download_url="https://github.com/nix-community\
/nix-user-chroot/releases/download/${NIX_USER_CHROOT_VERSION}\
/nix-user-chroot-bin-${NIX_USER_CHROOT_VERSION}-x86_64-unknown-linux-musl"
    ;;
    *)
    fail "Arch '${arch}' is not supported at the moment."
    ;;
  esac

  mkdir -p "${NIX_USER_CHROOT_DIR}" || {
    fail "Unable to create '${NIX_USER_CHROOT_DIR}'"
  }
  curl -L -o "${NIX_USER_CHROOT_BIN}" "${download_url}" || {
    fail "Unable to download nix-user-chroot (url: ${download_url})"
  }
  chmod +x "${NIX_USER_CHROOT_BIN}"
}

setup_nix() {
  mkdir -p "${NIX_STORE}" || {
    fail "Unable to create '${NIX_STORE}'"
  }
  # shellcheck disable=SC2250
  $NIX_USER_CHROOT_BIN "${NIX_STORE}" sh -c\
   "curl -L https://releases.nixos.org/nix/nix-${NIX_VERSION}/install > ${NIX_INSTALL_SCRIPT} && sh ${NIX_INSTALL_SCRIPT}\
    --no-channel-add\
    --no-daemon\
    --no-modify-profile\
    --nix-extra-conf-file ${NIX_CONF_DIR}/nix.conf"
}

ensure_direnv_is_configured() {
  local readonly project_root
  project_root=$(dirname "$(realpath "${__DIR__}"/..)")
  mkdir -p "${CACHE_ROOT}"
  cat > "${DIRENV_CONF_PATH}" << EOF
[whitelist]
prefix = [ "${project_root}" ]
EOF
}

ensure_nix_is_present() {
  if ${IS_NIXOS}; then
    # On nixos, nix is installed by default
    return
  fi

  if command -v "nix" >/dev/null 2>&1; then
    IS_NIX_INSTALLED=true;
  else
    IS_NIX_INSTALLED=false;
  fi
  # We need to distinguish between single-user and multi-user installs.
  # This is difficult because there's no official way to do this.
  # Details: https://github.com/lilyball/nix-env.fish/blob/00c6cc762427efe08ac0bd0d1b1d12048d3ca727/conf.d/nix-env.fish

  # stat is not portable. Splitting the output of ls -nd is reliable on most platforms.
  if ${IS_NIX_INSTALLED}; then
    local readonly nix_store_owner
    # shellcheck disable=SC2012
    nix_store_owner=$(ls -nd /nix/store | cut -d' ' -f3)
    if [ "${nix_store_owner}" -eq 0 ]; then
      local readonly is_nix_multiuser_install=true;
    else
      local readonly is_nix_multiuser_install=false;
    fi
  else
    # shellcheck disable=SC2034
    local readonly is_nix_multiuser_install=false;
  fi

  # Global, single-user installation
  if ${IS_NIX_INSTALLED} && ! ${is_nix_multiuser_install}; then
    return
  fi

  if ${IS_NIX_INSTALLED} && ${is_nix_multiuser_install}; then
    # TODO: Find a solution
    fail "Daemon-based nix installation is not supported"
  fi

  if [ -d "${NIX_STORE}" ]; then
    # Nix has already been set up
    echo "Detected previous setup in ${CACHE_ROOT}. Will attempt to use it."
    return
  fi

  # No nix installed or nix is multi-user installation
  setup_nix_user_chroot
  setup_nix
}

ensure_nix_shell_rc_exists() {
  mkdir -p "${CACHE_ROOT}"
  cat > "${NIX_SHELL_RC}" << EOF

$(
  if ! ${IS_NIXOS} || ${IS_NIX_INSTALLED}; then
    echo ". ${USER_HOME}/.nix-profile/etc/profile.d/nix.sh";
    echo "export NIX_CONF_DIR=${NIX_CONF_DIR}";
    echo "export NIX_USER_CONF_FILES=${NIX_USER_CONF_FILES}";
  fi

  if ${VANILLA_RUN}; then
    echo "export NIX_PATH=\
nixpkgs=https://github.com/NixOS/nixpkgs/archive/refs/heads/nixos-21.11.tar.gz";
  else
    echo "export NIX_PATH=${NIX_PATH}";
  fi
)

EOF
}

preflightCheck

# Parse script input params
OPTS=$(getopt -o "hv" --long "help,vanilla" -n "$(basename "$0")" -- "$@")

# Store nix-shell input params
NIX_SHELL_ARGS=''

# shellcheck disable=SC2181
if [ $? != 0 ] ; then
  echo "Error in command line arguments." >&2
  exit 1
fi
eval set -- "${OPTS}"

while true; do
  case "$1" in
    -h | --help)
      printHelp
      exit
      ;;
    -v | --vanilla )
      VANILLA_RUN=true
      shift
      ;;
    -- )
      shift
      # Pass arguments to nix-shell preserving quotes
      # Do not rely on shell's builtin printf as it may lack some of directives
      NIX_SHELL_ARGS=$(/usr/bin/env printf '%q ' "$@")
      break
      ;;
    * )
      break
      ;;
  esac
done

ensure_nix_is_present
ensure_direnv_is_configured
ensure_nix_shell_rc_exists

if ${IS_NIXOS} || ${IS_NIX_INSTALLED}; then
  exec ${SHELL} --rcfile "${NIX_SHELL_RC}"\
    -ci "nix-shell --pure '${__DIR__}/shell.nix' ${NIX_SHELL_ARGS}"
else
  # shellcheck disable=SC2250
  exec $NIX_USER_CHROOT_BIN "${NIX_STORE}" bash --rcfile "${NIX_SHELL_RC}"\
    -ci "nix-shell --pure '${__DIR__}/shell.nix' ${NIX_SHELL_ARGS}"
fi


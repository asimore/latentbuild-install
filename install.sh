#!/usr/bin/env sh
set -eu

OWNER_REPO="asimore/latentbuild-install"
VERSION="1.1.0"
METHOD="auto"
REPO_ROOT=""
RUN_DOCTOR="1"
UPDATE_PATH="1"
EXPECTED_SHA256="f2e039fc4b7116c0cc78d746a0a979ec5ce3af0a1177812ac5e0ce0c70196203"

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Install the LatentBuild CLI from the public GitHub Release wheel.

Options:
  --version <version>      Version to install. Defaults to 1.1.0.
  --sha256 <digest>        Expected wheel SHA-256. Defaults to 1.1.0 digest.
  --method <auto|pipx|venv|pip-user>
                           Install method. Defaults to auto.
  --repo-root <path>       Run lb doctor against this repo after install.
  --no-doctor              Skip lb doctor after install.
  --no-path-update         Do not update shell startup files.
  -h, --help               Show this help.

Example:
  curl -fsSL https://raw.githubusercontent.com/asimore/latentbuild-install/main/install.sh | sh
  curl -fsSL https://raw.githubusercontent.com/asimore/latentbuild-install/main/install.sh | sh -s -- --repo-root "$PWD"
EOF
}

die() {
  printf '%s\n' "latentbuild-install: $*" >&2
  exit 1
}

need_value() {
  [ "${2:-}" ] || die "$1 requires a value"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      need_value "$1" "${2:-}"
      VERSION="$2"
      shift 2
      ;;
    --sha256)
      need_value "$1" "${2:-}"
      EXPECTED_SHA256="$2"
      shift 2
      ;;
    --method)
      need_value "$1" "${2:-}"
      METHOD="$2"
      shift 2
      ;;
    --repo-root)
      need_value "$1" "${2:-}"
      REPO_ROOT="$2"
      shift 2
      ;;
    --no-doctor)
      RUN_DOCTOR="0"
      shift
      ;;
    --no-path-update)
      UPDATE_PATH="0"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

case "$METHOD" in
  auto|pipx|venv|pip-user) ;;
  *) die "--method must be auto, pipx, venv, or pip-user" ;;
esac

PYTHON_BIN="${PYTHON_BIN:-}"
if [ -z "$PYTHON_BIN" ]; then
  if command -v python3.12 >/dev/null 2>&1; then
    PYTHON_BIN="python3.12"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    die "python3.12 or python3 is required"
  fi
fi

"$PYTHON_BIN" - <<'PY' || die "Python 3.12 or newer is required"
import sys
raise SystemExit(0 if sys.version_info >= (3, 12) else 1)
PY

WHEEL="latentbuild-${VERSION}-py3-none-any.whl"
URL="https://github.com/${OWNER_REPO}/releases/download/v${VERSION}/${WHEEL}"
TMPDIR="${TMPDIR:-/tmp}/latentbuild-install.$$"
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT INT TERM

printf '%s\n' "Downloading ${URL}"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$URL" -o "${TMPDIR}/${WHEEL}"
elif command -v wget >/dev/null 2>&1; then
  wget -q "$URL" -O "${TMPDIR}/${WHEEL}"
else
  die "curl or wget is required"
fi

ACTUAL_SHA256="$(
  "$PYTHON_BIN" - "${TMPDIR}/${WHEEL}" <<'PY'
import hashlib
import sys

path = sys.argv[1]
digest = hashlib.sha256()
with open(path, "rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
print(digest.hexdigest())
PY
)"

if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  die "wheel checksum mismatch: expected ${EXPECTED_SHA256}, got ${ACTUAL_SHA256}"
fi

if [ "$METHOD" = "auto" ]; then
  if command -v pipx >/dev/null 2>&1; then
    METHOD="pipx"
  else
    METHOD="venv"
  fi
fi

append_path_once() {
  profile="$1"
  bin_dir="$2"
  marker="LatentBuild CLI PATH"
  [ -n "$profile" ] || return 0
  [ -f "$profile" ] || : > "$profile"
  if grep -F "$marker" "$profile" >/dev/null 2>&1; then
    return 0
  fi
  cat >> "$profile" <<EOF

# ${marker}
case ":\$PATH:" in
  *":${bin_dir}:"*) ;;
  *) export PATH="${bin_dir}:\$PATH" ;;
esac
EOF
}

persist_path() {
  bin_dir="$1"
  [ "$UPDATE_PATH" = "1" ] || return 0
  [ -n "${HOME:-}" ] || return 0

  append_path_once "${HOME}/.profile" "$bin_dir"
  shell_name="$(basename "${SHELL:-}")"
  case "$shell_name" in
    zsh)
      append_path_once "${HOME}/.zprofile" "$bin_dir"
      append_path_once "${HOME}/.zshrc" "$bin_dir"
      ;;
    bash)
      append_path_once "${HOME}/.bash_profile" "$bin_dir"
      append_path_once "${HOME}/.bashrc" "$bin_dir"
      ;;
    *)
      append_path_once "${HOME}/.zprofile" "$bin_dir"
      append_path_once "${HOME}/.zshrc" "$bin_dir"
      append_path_once "${HOME}/.bash_profile" "$bin_dir"
      append_path_once "${HOME}/.bashrc" "$bin_dir"
      ;;
  esac
}

if [ "$METHOD" = "pipx" ]; then
  command -v pipx >/dev/null 2>&1 || die "pipx is not installed; rerun with --method venv"
  pipx install --force "${TMPDIR}/${WHEEL}"
  USER_BIN="${LATENTBUILD_USER_BIN:-${HOME}/.local/bin}"
  if [ -d "$USER_BIN" ]; then
    PATH="${USER_BIN}:${PATH}"
    export PATH
    persist_path "$USER_BIN"
  fi
elif [ "$METHOD" = "venv" ]; then
  INSTALL_HOME="${LATENTBUILD_HOME:-${HOME}/.latentbuild}"
  VENV_DIR="${INSTALL_HOME}/venv"
  USER_BIN="${LATENTBUILD_USER_BIN:-${HOME}/.local/bin}"
  "$PYTHON_BIN" -m venv "$VENV_DIR"
  "${VENV_DIR}/bin/python" -m pip install --upgrade pip >/dev/null
  "${VENV_DIR}/bin/python" -m pip install --upgrade "${TMPDIR}/${WHEEL}"
  mkdir -p "$USER_BIN"
  ln -sf "${VENV_DIR}/bin/lb" "${USER_BIN}/lb"
  ln -sf "${VENV_DIR}/bin/lb-enroll-local" "${USER_BIN}/lb-enroll-local"
  PATH="${USER_BIN}:${PATH}"
  export PATH
  persist_path "$USER_BIN"
else
  "$PYTHON_BIN" -m pip --version >/dev/null 2>&1 || "$PYTHON_BIN" -m ensurepip --user >/dev/null 2>&1 || die "pip is required"
  "$PYTHON_BIN" -m pip install --user --upgrade "${TMPDIR}/${WHEEL}"
  USER_BASE="$("$PYTHON_BIN" -m site --user-base)"
  PATH="${USER_BASE}/bin:${PATH}"
  export PATH
  persist_path "${USER_BASE}/bin"
fi

if ! command -v lb >/dev/null 2>&1; then
  cat >&2 <<EOF
latentbuild-install: installed package, but 'lb' is not on PATH.
Add the LatentBuild command directory to PATH, then retry:

  export PATH="${USER_BIN:-$("$PYTHON_BIN" -m site --user-base)/bin}:\$PATH"

EOF
  exit 1
fi

lb --help >/dev/null

if [ "$RUN_DOCTOR" = "1" ]; then
  if [ -n "$REPO_ROOT" ]; then
    lb doctor --repo-root "$REPO_ROOT" --json || true
  else
    lb doctor --repo-root . --json || true
  fi
fi

cat <<'EOF'
LatentBuild CLI installed.

Next step:
  open a new terminal, or run: export PATH="$HOME/.local/bin:$PATH"
  cd /path/to/customer-repo
  lb-enroll-local "$PWD" <repo-id>
EOF

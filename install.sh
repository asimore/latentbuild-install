#!/usr/bin/env sh
set -eu

OWNER_REPO="asimore/latentbuild-install"
VERSION="1.0.5"
METHOD="auto"
REPO_ROOT=""
RUN_DOCTOR="1"
EXPECTED_SHA256="25d7514870eddfcca09c15d0693c0dc4e85fca9338ab079612b94c5cb4be8dd7"

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Install the LatentBuild CLI from the public GitHub Release wheel.

Options:
  --version <version>      Version to install. Defaults to 1.0.5.
  --sha256 <digest>        Expected wheel SHA-256. Defaults to 1.0.5 digest.
  --method <auto|pipx|venv|pip-user>
                           Install method. Defaults to auto.
  --repo-root <path>       Run lb doctor against this repo after install.
  --no-doctor              Skip lb doctor after install.
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

if [ "$METHOD" = "pipx" ]; then
  command -v pipx >/dev/null 2>&1 || die "pipx is not installed; rerun with --method venv"
  pipx install --force "${TMPDIR}/${WHEEL}"
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
else
  "$PYTHON_BIN" -m pip --version >/dev/null 2>&1 || "$PYTHON_BIN" -m ensurepip --user >/dev/null 2>&1 || die "pip is required"
  "$PYTHON_BIN" -m pip install --user --upgrade "${TMPDIR}/${WHEEL}"
  USER_BASE="$("$PYTHON_BIN" -m site --user-base)"
  PATH="${USER_BASE}/bin:${PATH}"
  export PATH
fi

if ! command -v lb >/dev/null 2>&1; then
  cat >&2 <<EOF
latentbuild-install: installed package, but 'lb' is not on PATH.
Add Python's user bin directory to PATH, then retry:

  export PATH="\$(${PYTHON_BIN} -m site --user-base)/bin:\$PATH"

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
  cd /path/to/customer-repo
  lb-enroll-local "$PWD" <repo-id>
EOF

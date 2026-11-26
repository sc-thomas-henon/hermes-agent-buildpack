# bp_ensure_uv — installs uv into CACHE_DIR (kept between builds); sets UV_BIN
bp_ensure_uv() {
  export UV_INSTALL_DIR="${CACHE_DIR}/uv"
  export UV_CACHE_DIR="${CACHE_DIR}/uv-cache"
  if [ ! -x "${UV_INSTALL_DIR}/uv" ]; then
    status "Installing uv ${UV_VERSION} (cached)"
    curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh
  fi
  UV_BIN="${UV_INSTALL_DIR}/uv"
}

# bp_setup_python BUILD_DIR — creates BUILD_DIR/.venv with Python $PYTHON_VERSION; sets VENV_DIR
# scalingo-26 ships python3.14 in the base image; on older stacks we fall back
# to a uv-managed interpreter kept in CACHE_DIR so rebuilds stay fast.
bp_setup_python() {
  local build_dir="$1"
  VENV_DIR="${build_dir}/.venv"

  if command -v "python${PYTHON_VERSION}" >/dev/null 2>&1; then
    status "Using system python${PYTHON_VERSION}"
    "python${PYTHON_VERSION}" -m venv "$VENV_DIR"
  else
    bp_ensure_uv
    status "python${PYTHON_VERSION} not in the stack image, installing it with uv (cached)"
    "$UV_BIN" python install "${PYTHON_VERSION}"
    "$UV_BIN" venv --seed --python "${PYTHON_VERSION}" "$VENV_DIR"
  fi
}

# bp_install_hermes — installs hermes-agent from the pinned git tag.
# Hermes only supports source-checkout installs (its setup.py refuses to build
# wheels outside Nix, and wheels would miss bundled assets), so the checkout is
# copied into BUILD_DIR (it becomes /app at runtime) and installed editable
# into the venv with `uv sync --frozen`. Upstream's pyproject also relies on
# [tool.uv] override-dependencies (e.g. Pillow), which only apply when uv
# syncs the project itself: a plain `pip install git+...@tag` fails to resolve.
# The clone is cached in CACHE_DIR and only re-fetched when the tag changes.
bp_install_hermes() {
  bp_ensure_uv
  local src_cache="${CACHE_DIR}/hermes-src"
  if [ ! -d "${src_cache}/.git" ] || [ "$(cat "${src_cache}/.bp-tag" 2>/dev/null)" != "${HERMES_AGENT_VERSION}" ]; then
    status "Fetching hermes-agent ${HERMES_AGENT_VERSION}"
    rm -rf "$src_cache"
    git clone --depth 1 --branch "${HERMES_AGENT_VERSION}" "${HERMES_AGENT_REPO}" "$src_cache"
    printf '%s' "${HERMES_AGENT_VERSION}" > "${src_cache}/.bp-tag"
  fi
  status "Shipping hermes-agent source in the app (runtime layout)"
  rm -rf "${BUILD_DIR}/hermes-src"
  cp -a "$src_cache" "${BUILD_DIR}/hermes-src"
  rm -rf "${BUILD_DIR}/hermes-src/.git"
  status "Installing hermes-agent ${HERMES_AGENT_VERSION} (uv.lock, frozen, editable)"
  (cd "${BUILD_DIR}/hermes-src" && UV_PROJECT_ENVIRONMENT="${VENV_DIR}" "$UV_BIN" sync --frozen --python "${VENV_DIR}/bin/python")
}

# bp_install_app_requirements BUILD_DIR — installs the app's requirements.txt
# into the venv, excluding hermes-agent lines (the buildpack pins that version).
bp_install_app_requirements() {
  local build_dir="$1"
  [ -f "${build_dir}/requirements.txt" ] || return 0
  bp_ensure_uv
  status "Installing application requirements"
  grep -viE 'hermes[-_]agent' "${build_dir}/requirements.txt" > "${CACHE_DIR}/requirements.app.txt" || true
  if [ -s "${CACHE_DIR}/requirements.app.txt" ]; then
    "$UV_BIN" pip install --python "${VENV_DIR}/bin/python" -r "${CACHE_DIR}/requirements.app.txt"
  fi
}

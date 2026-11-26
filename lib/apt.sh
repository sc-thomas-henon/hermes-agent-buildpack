bp_install_system_packages() {
  local build_dir="$1"
  local aptfile_manifest
  aptfile_manifest="$(bp_env APT_FILE_MANIFEST "${build_dir}/Aptfile")"

  status "Installing system packages (apt)"
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends ${APT_PACKAGES}

  if [ -f "$aptfile_manifest" ]; then
    status "Installing packages from ${aptfile_manifest}"
    local pkgs
    pkgs="$(grep -vE '^\s*(#|$)' "$aptfile_manifest" | tr '\n' ' ')"
    if [ -n "$pkgs" ]; then
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends $pkgs
    fi
  fi
}

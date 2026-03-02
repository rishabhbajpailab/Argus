#!/usr/bin/env bash
# setup_deps.sh — Install all system, Elixir, and Rust dependencies for Argus.
#
# Supported package managers:
#   apt-get  — Debian, Ubuntu, and derivatives
#   dnf      — Fedora, RHEL 8+, CentOS Stream 8+, AlmaLinux, Rocky Linux
#   zypper   — openSUSE Leap / Tumbleweed
#   xbps     — Void Linux
#
# Usage:
#   bash setup_deps.sh
#
# The script must be run as root, or with a user that has sudo access.

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { printf '\e[1;34m[argus-setup]\e[0m  %s\n' "$*"; }
ok()    { printf '\e[1;32m[argus-setup]\e[0m  %s\n' "$*"; }
warn()  { printf '\e[1;33m[argus-setup]\e[0m  %s\n' "$*" >&2; }
die()   { printf '\e[1;31m[argus-setup]\e[0m  ERROR: %s\n' "$*" >&2; exit 1; }

# Run a command with sudo if we are not already root.
_sudo() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

# ---------------------------------------------------------------------------
# Detect OS and package manager
# ---------------------------------------------------------------------------

detect_pm() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
  else
    die "/etc/os-release not found — cannot detect OS"
  fi

  info "Detected OS: ${PRETTY_NAME:-${ID:-unknown}}"

  if command -v apt-get &>/dev/null; then
    PM="apt-get"
  elif command -v dnf &>/dev/null; then
    PM="dnf"
  elif command -v zypper &>/dev/null; then
    PM="zypper"
  elif command -v xbps-install &>/dev/null; then
    PM="xbps"
  else
    die "No supported package manager found (apt-get, dnf, zypper, xbps). " \
        "Install dependencies manually — see README.md."
  fi

  info "Using package manager: ${PM}"
}

# ---------------------------------------------------------------------------
# Install system packages
# ---------------------------------------------------------------------------

install_system_deps() {
  info "Installing system dependencies via ${PM}..."

  case "${PM}" in

    # -----------------------------------------------------------------------
    # Debian / Ubuntu
    # -----------------------------------------------------------------------
    apt-get)
      _sudo apt-get update -qq

      # Add the Erlang Solutions repository for a recent OTP + Elixir release.
      if ! dpkg -s erlang &>/dev/null 2>&1; then
        info "Adding Erlang Solutions apt repository..."
        curl -fsSL https://packages.erlang-solutions.com/ubuntu/erlang_solutions.pub \
          | _sudo gpg --dearmor -o /usr/share/keyrings/erlang-solutions.gpg
        echo "deb [signed-by=/usr/share/keyrings/erlang-solutions.gpg] \
https://packages.erlang-solutions.com/ubuntu $(lsb_release -cs 2>/dev/null || echo focal) contrib" \
          | _sudo tee /etc/apt/sources.list.d/erlang-solutions.list >/dev/null
        _sudo apt-get update -qq
      fi

      _sudo apt-get install -y --no-install-recommends \
        git \
        curl \
        ca-certificates \
        gnupg \
        lsb-release \
        build-essential \
        make \
        libssl-dev \
        pkg-config \
        erlang \
        elixir
      ;;

    # -----------------------------------------------------------------------
    # Fedora / RHEL / CentOS Stream / AlmaLinux / Rocky Linux
    # -----------------------------------------------------------------------
    dnf)
      _sudo dnf install -y \
        git \
        curl \
        ca-certificates \
        gcc \
        gcc-c++ \
        make \
        openssl-devel \
        pkg-config \
        erlang \
        elixir
      ;;

    # -----------------------------------------------------------------------
    # openSUSE Leap / Tumbleweed
    # -----------------------------------------------------------------------
    zypper)
      _sudo zypper --non-interactive refresh

      _sudo zypper --non-interactive install \
        git \
        curl \
        ca-certificates \
        gcc \
        gcc-c++ \
        make \
        libopenssl-devel \
        pkg-config \
        erlang \
        elixir
      ;;

    # -----------------------------------------------------------------------
    # Void Linux
    # -----------------------------------------------------------------------
    xbps)
      _sudo xbps-install -Sy \
        git \
        curl \
        ca-certificates \
        base-devel \
        make \
        openssl-devel \
        pkg-config \
        erlang \
        elixir
      ;;

  esac

  ok "System dependencies installed."
}

# ---------------------------------------------------------------------------
# Install Rust via rustup
# ---------------------------------------------------------------------------

install_rust() {
  if command -v rustup &>/dev/null; then
    info "rustup already installed — updating toolchain..."
    rustup update stable
  else
    info "Installing Rust (stable) via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --default-toolchain stable --no-modify-path
    # Make cargo/rustc available in the current shell session.
    # shellcheck source=/dev/null
    source "${HOME}/.cargo/env"
  fi

  ok "Rust $(rustc --version) ready."
}

# ---------------------------------------------------------------------------
# Pre-fetch Rust crate dependencies
# ---------------------------------------------------------------------------

fetch_rust_deps() {
  local crate_dir
  crate_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/crates/connector_host" && pwd)"

  if [[ ! -f "${crate_dir}/Cargo.toml" ]]; then
    warn "crates/connector_host/Cargo.toml not found — skipping cargo fetch."
    return
  fi

  info "Pre-fetching Rust crate dependencies (cargo fetch)..."
  # Ensure cargo is on PATH (may have just been installed by rustup).
  export PATH="${HOME}/.cargo/bin:${PATH}"
  cargo fetch --manifest-path "${crate_dir}/Cargo.toml"
  ok "Rust crates fetched."
}

# ---------------------------------------------------------------------------
# Fetch Elixir/Mix dependencies
# ---------------------------------------------------------------------------

fetch_elixir_deps() {
  local mix_dir
  mix_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/apps/router_core" && pwd)"

  if [[ ! -f "${mix_dir}/mix.exs" ]]; then
    warn "apps/router_core/mix.exs not found — skipping mix deps.get."
    return
  fi

  info "Fetching Elixir dependencies (mix deps.get)..."
  (cd "${mix_dir}" && mix local.hex --force && mix local.rebar --force && mix deps.get)
  ok "Elixir dependencies fetched."
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print_summary() {
  ok "------------------------------------------------------"
  ok " Argus dependency setup complete!"
  ok ""
  ok " Installed:"
  ok "   • System packages via ${PM}"
  ok "   • Rust stable toolchain (rustup)"
  ok "   • Rust crates (cargo fetch)"
  ok "   • Elixir packages (mix deps.get)"
  ok ""
  ok " Next steps:"
  ok "   Option A (Docker):  docker compose up --build -d"
  ok "   Option B (local):   see README.md — 'Running locally'"
  ok "------------------------------------------------------"
  if ! command -v cargo &>/dev/null; then
    warn "Rust was just installed. Run the following to activate it in this shell:"
    warn "  source \"\${HOME}/.cargo/env\""
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  detect_pm
  install_system_deps
  install_rust
  fetch_rust_deps
  fetch_elixir_deps
  print_summary
}

main "$@"

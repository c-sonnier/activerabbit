#!/bin/sh
# ActiveRabbit CLI Installer
# Usage: curl -fsSL https://activerabbit.ai/cli/install.sh | sh
#
# Installs the ActiveRabbit CLI and its dependency (jq).

set -e

# ─── Colors ───────────────────────────────────────────────────────────────────

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  DIM='\033[2m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' RESET=''
fi

info()  { printf "${BOLD}${GREEN}>>>${RESET} %s\n" "$1"; }
warn()  { printf "${BOLD}${YELLOW}>>>${RESET} %s\n" "$1"; }
error() { printf "${BOLD}${RED}>>>${RESET} %s\n" "$1"; }
dim()   { printf "${DIM}    %s${RESET}\n" "$1"; }

# ─── Platform Detection ──────────────────────────────────────────────────────

detect_platform() {
  OS="$(uname -s 2>/dev/null || echo 'Unknown')"
  ARCH="$(uname -m 2>/dev/null || echo 'Unknown')"

  case "$OS" in
    Linux*)   PLATFORM="linux" ;;
    Darwin*)  PLATFORM="macos" ;;
    MINGW*|MSYS*|CYGWIN*)
      error "Native Windows is not supported."
      printf "\n  Please install Windows Subsystem for Linux (WSL) and run this installer inside WSL.\n"
      printf "  Instructions: ${CYAN}https://learn.microsoft.com/en-us/windows/wsl/install${RESET}\n\n"
      exit 1
      ;;
    *)
      error "Unsupported operating system: $OS"
      exit 1
      ;;
  esac

  # Detect WSL
  if [ "$PLATFORM" = "linux" ] && grep -qi microsoft /proc/version 2>/dev/null; then
    info "Detected Windows Subsystem for Linux (WSL)"
  fi

  case "$ARCH" in
    x86_64|amd64)  ARCH="x86_64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *)
      warn "Unusual architecture: $ARCH (proceeding anyway)"
      ;;
  esac
}

# ─── Check HTTP Client ───────────────────────────────────────────────────────

check_http_client() {
  if command -v curl >/dev/null 2>&1; then
    HTTP_CLIENT="curl"
  elif command -v wget >/dev/null 2>&1; then
    HTTP_CLIENT="wget"
  else
    error "Neither curl nor wget found. Please install one and try again."
    exit 1
  fi
}

download() {
  url="$1"
  dest="$2"
  if [ "$HTTP_CLIENT" = "curl" ]; then
    curl -fsSL "$url" -o "$dest"
  else
    wget -q "$url" -O "$dest"
  fi
}

# ─── Install jq ──────────────────────────────────────────────────────────────

install_jq() {
  if command -v jq >/dev/null 2>&1; then
    dim "jq already installed ($(jq --version 2>/dev/null || echo 'ok'))"
    return 0
  fi

  info "Installing jq (JSON processor)..."

  if [ "$PLATFORM" = "macos" ]; then
    if command -v brew >/dev/null 2>&1; then
      brew install jq >/dev/null 2>&1 || {
        error "Failed to install jq via Homebrew."
        printf "  Install manually: ${CYAN}brew install jq${RESET}\n"
        exit 1
      }
    else
      error "Homebrew not found. Please install jq manually:"
      printf "  ${CYAN}brew install jq${RESET}  or  ${CYAN}https://jqlang.github.io/jq/download/${RESET}\n"
      exit 1
    fi
  elif [ "$PLATFORM" = "linux" ]; then
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -qq >/dev/null 2>&1 && sudo apt-get install -y -qq jq >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y -q jq >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
      sudo yum install -y -q jq >/dev/null 2>&1
    elif command -v apk >/dev/null 2>&1; then
      sudo apk add --quiet jq >/dev/null 2>&1
    elif command -v pacman >/dev/null 2>&1; then
      sudo pacman -S --noconfirm --quiet jq >/dev/null 2>&1
    else
      error "Could not detect package manager. Please install jq manually:"
      printf "  ${CYAN}https://jqlang.github.io/jq/download/${RESET}\n"
      exit 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
      error "jq installation failed. Please install manually."
      exit 1
    fi
  fi

  dim "jq installed successfully"
}

# ─── Determine Install Path ──────────────────────────────────────────────────

determine_install_path() {
  # Prefer /usr/local/bin
  if [ -w "/usr/local/bin" ]; then
    INSTALL_DIR="/usr/local/bin"
  elif command -v sudo >/dev/null 2>&1; then
    INSTALL_DIR="/usr/local/bin"
    USE_SUDO=1
  else
    # Fallback to ~/.local/bin
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"

    # Check if ~/.local/bin is in PATH
    case ":$PATH:" in
      *":$INSTALL_DIR:"*) ;;
      *)
        warn "$INSTALL_DIR is not in your PATH."
        printf "\n  Add it by running:\n"
        printf "  ${CYAN}export PATH=\"\$HOME/.local/bin:\$PATH\"${RESET}\n"
        printf "  ${DIM}(Add this to your ~/.bashrc or ~/.zshrc to make it permanent)${RESET}\n\n"
        ;;
    esac
  fi
}

# ─── Install CLI ─────────────────────────────────────────────────────────────

install_cli() {
  DOWNLOAD_URL="https://activerabbit.ai/cli/activerabbit"
  INSTALL_PATH="${INSTALL_DIR}/activerabbit"

  info "Downloading ActiveRabbit CLI..."

  tmp=$(mktemp)
  download "$DOWNLOAD_URL" "$tmp" || {
    error "Failed to download CLI script."
    rm -f "$tmp"
    exit 1
  }

  # Verify it looks like a shell script
  head_line=$(head -1 "$tmp" 2>/dev/null || true)
  case "$head_line" in
    "#!/bin/sh"*|"#!/usr/bin/env sh"*|"#!/bin/bash"*)
      ;;
    *)
      error "Downloaded file does not appear to be a valid script."
      rm -f "$tmp"
      exit 1
      ;;
  esac

  info "Installing to ${INSTALL_PATH}..."

  if [ "${USE_SUDO:-}" = "1" ]; then
    sudo mv "$tmp" "$INSTALL_PATH"
    sudo chmod +x "$INSTALL_PATH"
  else
    mv "$tmp" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
  printf "\n"
  printf "  ${BOLD}ActiveRabbit CLI Installer${RESET}\n"
  printf "  ${DIM}https://activerabbit.ai/cli${RESET}\n"
  printf "\n"

  detect_platform
  info "Detected: ${PLATFORM} (${ARCH})"

  check_http_client
  install_jq
  determine_install_path
  install_cli

  printf "\n"
  printf "${CYAN}${BOLD}"
  printf "       █████╗  ██████╗████████╗██╗██╗   ██╗███████╗\n"
  printf "      ██╔══██╗██╔════╝╚══██╔══╝██║██║   ██║██╔════╝\n"
  printf "      ███████║██║        ██║   ██║██║   ██║█████╗  \n"
  printf "      ██╔══██║██║        ██║   ██║╚██╗ ██╔╝██╔══╝  \n"
  printf "      ██║  ██║╚██████╗   ██║   ██║ ╚████╔╝ ███████╗\n"
  printf "      ╚═╝  ╚═╝ ╚═════╝   ╚═╝   ╚═╝  ╚═══╝  ╚══════╝\n"
  printf "${RESET}"
  printf "${GREEN}${BOLD}"
  printf "      ██████╗  █████╗ ██████╗ ██████╗ ██╗████████╗\n"
  printf "      ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██║╚══██╔══╝\n"
  printf "      ██████╔╝███████║██████╔╝██████╔╝██║   ██║   \n"
  printf "      ██╔══██╗██╔══██║██╔══██╗██╔══██╗██║   ██║   \n"
  printf "      ██║  ██║██║  ██║██████╔╝██████╔╝██║   ██║   \n"
  printf "      ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═════╝ ╚═╝   ╚═╝   \n"
  printf "${RESET}"
  printf "\n"
  printf "      ${DIM}AI-powered monitoring from your terminal${RESET}\n"
  printf "      ${DIM}https://activerabbit.ai/cli${RESET}\n"
  printf "\n"
  printf "  ${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
  printf "  ${GREEN}${BOLD}  ✓ Installed successfully!${RESET}  ${DIM}v${VERSION}${RESET}\n"
  printf "  ${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
  printf "\n"
  printf "  ${BOLD}Quick Start:${RESET}\n"
  printf "\n"
  printf "    ${CYAN}1.${RESET} Authenticate with your API key:\n"
  printf "       ${CYAN}$ activerabbit login${RESET}\n"
  printf "\n"
  printf "    ${CYAN}2.${RESET} Select your app:\n"
  printf "       ${CYAN}$ activerabbit apps${RESET}\n"
  printf "       ${CYAN}$ activerabbit use-app <slug>${RESET}\n"
  printf "\n"
  printf "    ${CYAN}3.${RESET} Start monitoring:\n"
  printf "       ${CYAN}$ activerabbit status${RESET}\n"
  printf "\n"
  printf "  ${DIM}Run ${CYAN}activerabbit help${DIM} to see all commands.${RESET}\n"
  printf "  ${DIM}Docs: ${CYAN}https://activerabbit.ai/cli${RESET}\n"
  printf "\n"
}

main

#!/usr/bin/env bash
#
# setup.sh
#
# Automates the "Pre Requisites" and "Setup for Demikernel" sections of
# https://github.com/microsoft/demikernel/blob/dev/doc/cloudlab.md

set -uo pipefail


REPO_URL="${REPO_URL:-https://github.com/MaryAyobami/demikernel.git}"
REPO_BRANCH="${REPO_BRANCH:-dev}"

WORKDIR="${WORKDIR:-/local/demikernel-setup}"
REPO_DIR="$WORKDIR/demikernel"
RUSTUP_HOME="$WORKDIR/.rustup"
CARGO_HOME="$WORKDIR/.cargo"
MARKER="$WORKDIR/.setup-complete"
FORCE="${FORCE:-0}"

OFED_VERSION="5.5-1.0.3.2"
OFED_TARBALL="MLNX_OFED_LINUX-${OFED_VERSION}-ubuntu20.04-x86_64.tgz"
OFED_URL="https://content.mellanox.com/ofed/MLNX_OFED-${OFED_VERSION}/${OFED_TARBALL}"
OFED_DIR="MLNX_OFED_LINUX-${OFED_VERSION}-ubuntu20.04-x86_64"

LOG_FILE="$WORKDIR/demikernel-setup.log"

# Helpers 
step() { echo -e "\n=== [$(date '+%H:%M:%S')] $* ===" | tee -a "$LOG_FILE"; }
fail() { echo "FAILED: $*  (see $LOG_FILE for the captured output)"; exit 1; }
run()  { echo "+ $*" >> "$LOG_FILE"; "$@" >>"$LOG_FILE" 2>&1 || fail "$*"; }
cd_or_fail() { cd "$1" 2>>"$LOG_FILE" || fail "cd $1"; }

# Ensure WORKDIR exists, then check completion marker 
mkdir -p "$WORKDIR" 2>/dev/null || { sudo mkdir -p "$WORKDIR" && sudo chmod 777 "$WORKDIR"; }
[[ -d "$WORKDIR" ]] || { echo "Could not create $WORKDIR"; exit 1; }

if [[ -f "$MARKER" && "$FORCE" != "1" ]]; then
  echo "Setup already completed on $(cat "$MARKER"); skipping (this run was"
  echo "triggered by a reboot). To force a full re-run: rm $MARKER, or set"
  echo "FORCE=1 before invoking this script."
  exit 0
fi

: > "$LOG_FILE"

# Sanity check: OS version 
step "Checking OS version"
# shellcheck disable=SC1091
. /etc/os-release
if [[ "${VERSION_ID:-}" != "20.04" ]]; then
  echo "WARNING: doc/cloudlab.md's MLNX_OFED ${OFED_VERSION} package is built"
  echo "for Ubuntu 20.04. Detected: ${PRETTY_NAME:-unknown}. Continuing anyway,"
  echo "but the OFED install step below may fail on a different OS version."
fi

# 1. Mellanox OFED (mlx5 driver) 
step "Installing Mellanox OFED ${OFED_VERSION} (--upstream-libs --dpdk)"
if command -v ofed_info >/dev/null 2>&1; then
  echo "OFED already installed ($(ofed_info -s 2>/dev/null | head -1)); skipping."
else
  cd_or_fail "$WORKDIR"
  if [[ ! -f "$OFED_TARBALL" ]]; then
    run wget "$OFED_URL" --no-check-certificate -O "$OFED_TARBALL"
  fi
  run tar -xzvf "$OFED_TARBALL"
  cd_or_fail "$WORKDIR/$OFED_DIR"
  run sudo ./mlnxofedinstall --upstream-libs --dpdk -q
fi

# Rust toolchain
step "Installing Rust toolchain"
export RUSTUP_HOME CARGO_HOME
if [[ -x "$CARGO_HOME/bin/cargo" ]]; then
  echo "Rust/cargo already installed ($("$CARGO_HOME/bin/cargo" --version)); skipping."
else
  run bash -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path"
fi
export PATH="$CARGO_HOME/bin:$PATH"

# Clone demikernel fork 
step "Cloning $REPO_URL ($REPO_BRANCH) into $REPO_DIR"
if [[ -d "$REPO_DIR/.git" ]]; then
  echo "$REPO_DIR already exists; fetching latest instead of re-cloning."
  cd_or_fail "$REPO_DIR"
  run git fetch origin
  run git checkout "$REPO_BRANCH"
  run git pull origin "$REPO_BRANCH"
  run git submodule update --init --recursive
else
  run git clone --recursive "$REPO_URL" "$REPO_DIR"
  cd_or_fail "$REPO_DIR"
  run git checkout "$REPO_BRANCH"
fi


cd_or_fail "$REPO_DIR"

step "Running scripts/install-dev-packages.sh"
run ./scripts/install-dev-packages.sh

step "Running scripts/build-install-dpdk.sh"
run ./scripts/build-install-dpdk.sh

step "Running scripts/setup-hugepages.sh"
run ./scripts/setup-hugepages.sh

step "Building (make all)"
run make all

#  Make cargo available to later interactive logins
step "Registering cargo on PATH for future SSH sessions"
sudo tee /etc/profile.d/99-demikernel-cargo.sh > /dev/null << EOF
export RUSTUP_HOME="$RUSTUP_HOME"
export CARGO_HOME="$CARGO_HOME"
export PATH="\$CARGO_HOME/bin:\$PATH"
EOF
sudo chmod 644 /etc/profile.d/99-demikernel-cargo.sh


date > "$MARKER"
step "Setup complete"
echo "Repo:     $REPO_DIR"
echo "Branch:   $REPO_BRANCH"
echo "Full log: $LOG_FILE"
echo
echo "Next: generate $REPO_DIR/scripts/config/cl_node_N.yaml"
echo "for this node using:"
echo "  sudo lshw -c network -businfo        # mlx5 interface name + PCI address"
echo "  sudo lshw | grep -i Mellanox -A 10    # link address (MAC)"
echo "  ifconfig <iface>                      # 10.10.1.x IP"

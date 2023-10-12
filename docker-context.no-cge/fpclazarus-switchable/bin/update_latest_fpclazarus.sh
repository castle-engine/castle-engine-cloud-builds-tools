#!/bin/bash
set -eu

# Use this to update FPC from trunk now.

FPC_GIT_HASH="$1"
LAZARUS_GIT_HASH="$2"
shift 2

# Configurable section -----------------------------------------------------------

# Change with new FPC version
FPC_TRUNK_VERSION='3.3.1'
FPC_STABLE_VERSION='3.2.2'
FPC_STABLE_BIN="/usr/local/fpclazarus/bootstrap/ppcx64-${FPC_STABLE_VERSION}"

# The architecture native to current host, name consistent with FPC tar.gz files
#FPC_HOST_CPU=i386
FPC_HOST_CPU=x86_64

# FPC GIT clone ---------------------------------------------------------------

FPC_SOURCE_DIR=/usr/local/fpclazarus/"${FPC_TRUNK_VERSION}"/fpc/src
FPC_SOURCE_DIR_PARENT="`dirname \"${FPC_SOURCE_DIR}\"`"
FPC_SOURCE_DIR_BASENAME="`basename \"${FPC_SOURCE_DIR}\"`"

echo 'FPC clone:'
mkdir -p "${FPC_SOURCE_DIR_PARENT}"
cd "${FPC_SOURCE_DIR_PARENT}"
# Note: using  --depth 1 would also speed this up, but then doing "git checkout" to historic revisions is not possible
git clone --single-branch --branch main https://gitlab.com/freepascal.org/fpc/source.git "${FPC_SOURCE_DIR_BASENAME}"

cd "${FPC_SOURCE_DIR_BASENAME}"
git checkout "${FPC_GIT_HASH}"

# Remove .git, to conserve Docker container size
rm -Rf "${FPC_SOURCE_DIR}"/.git/

patch -p0 < /usr/local/fpclazarus/fpc-trunk.patch
cd ../

# FPC Build and install ----------------------------------------------------------

FPC_INSTALL_DIR=/usr/local/fpclazarus/"${FPC_TRUNK_VERSION}"/fpc/
mkdir -p "${FPC_INSTALL_DIR}"

cd "${FPC_SOURCE_DIR}"
# build with last stable fpc
make clean all install \
  INSTALL_PREFIX="${FPC_INSTALL_DIR}" PP="${FPC_STABLE_BIN}"
make clean crossall crossinstall \
  OS_TARGET=win32 CPU_TARGET=i386 \
  INSTALL_PREFIX="${FPC_INSTALL_DIR}" PP="${FPC_STABLE_BIN}"
make clean crossall crossinstall \
  OS_TARGET=win64 CPU_TARGET=x86_64 \
  INSTALL_PREFIX="${FPC_INSTALL_DIR}" PP="${FPC_STABLE_BIN}"
make clean crossall crossinstall \
  OS_TARGET=android CPU_TARGET=arm CROSSOPT="-CfVFPV3" \
  INSTALL_PREFIX="${FPC_INSTALL_DIR}" PP="${FPC_STABLE_BIN}"
make clean crossall crossinstall \
  OS_TARGET=android CPU_TARGET=aarch64 \
  INSTALL_PREFIX="${FPC_INSTALL_DIR}" PP="${FPC_STABLE_BIN}"

# Set symlinks ---------------------------------------------------------------

cd "${FPC_INSTALL_DIR}"/bin

set_ppc_symlink ()
{
  TARGET_NAME="$1"
  TARGET="../lib/fpc/${FPC_TRUNK_VERSION}/${TARGET_NAME}"

  if [ -f "${TARGET}" ]; then
    rm -f "${TARGET_NAME}"
    ln -s "${TARGET}" .
  fi
}

set_ppc_symlink ppc386
set_ppc_symlink ppcx64
set_ppc_symlink ppcrossx64
set_ppc_symlink ppcross386
set_ppc_symlink ppcrossarm
set_ppc_symlink ppcrossa64 # aarch64

# Conserve disk space ------------------------------------------------------

# Remove FPC sources and docs --  useless in a container, to conserve Docker image size
rm -Rf /usr/local/fpclazarus/${FPC_TRUNK_VERSION}/fpc/src/ \
       /usr/local/fpclazarus/${FPC_TRUNK_VERSION}/fpc/man/ \
       /usr/local/fpclazarus/${FPC_TRUNK_VERSION}/fpc/share/doc/

# Fix permissions ------------------------------------------------------------

/usr/local/fpclazarus/bin/fix_permissions.sh

# Make sure /etc/fpc.cfg is OK, so that FPC can actually be used to build lazarus next

/usr/local/fpclazarus/bin/setup_fpc_etc.sh

# Test new compiler ----------------------------------------------------------

. /usr/local/fpclazarus/bin/setup.sh "${FPC_TRUNK_VERSION}"
echo 'New FPC version logo:'
set +e
fpc -l
fpc -Tlinux -P${FPC_HOST_CPU} -l | head -n 1
fpc -Twin32 -Pi386 -l | head -n 1
fpc -Twin64 -Px86_64 -l | head -n 1
fpc -Tandroid -Parm -l | head -n 1
set -e # ignore exit, "fpc .. -l" always makes error "No source file name in command line"

# ----------------------------------------------------------------------------
# After updating FPC, always update also Lazarus, to recompile it with latest FPC trunk

# We have already switched above to use the new compiler.

/usr/local/fpclazarus/bin/update_latest_lazarus.sh "${LAZARUS_GIT_HASH}"


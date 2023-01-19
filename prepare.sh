#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause

set -ex

echo "Install dependencies"
sudo add-apt-repository ppa:v-launchpad-jochen-sprickerhof-de/sbuild
sudo apt-get update
sudo apt-get install -y mmdebstrap distro-info debian-archive-keyring ccache curl sbuild

echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $DEB_DISTRO main" | sudo tee /etc/apt/sources.list.d/ros2-latest.list
curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
sudo apt-get update
sudo apt-get install -y python3-bloom python3-vcstool python3-rosdep python3-colcon-common-extensions

echo "Setup build environment"
mkdir -p ~/.cache/sbuild
mmdebstrap --variant=buildd --include=apt,ccache \
  --customize-hook='chroot "$1" update-ccache-symlinks' \
  --components=main,universe "$DEB_DISTRO" "$HOME/.cache/sbuild/$DEB_DISTRO-amd64.tar"

ccache --zero-stats --max-size=10.0G

# allow ccache access from sbuild
chmod a+rwX ~
chmod -R a+rwX ~/.cache/ccache

cat << "EOF" > ~/.sbuildrc
$build_environment = { 'CCACHE_DIR' => '/build/ccache' };
$path = '/usr/lib/ccache:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games';
$build_path = '/build/package/';
$dsc_dir = 'package';
$unshare_bind_mounts = [ { directory => '/home/runner/.cache/ccache', mountpoint => '/build/ccache' } ];
EOF
echo "$SBUILD_CONF" >> ~/.sbuildrc
echo "\$extra_packages = ['$GITHUB_WORKSPACE/dists/$DEB_DISTRO/universe/binary-amd64'];" >> ~/.sbuildrc

cat ~/.sbuildrc

# Only local file is supported unlike the original code.
echo "Import source repository"
mkdir src
vcs import src < "$REPOS_FILE"
python3 $GITHUB_ACTION_PATH/scripts/apply_repos_config.py "$REPOS_CONF"

# Switch to the target branch to use released packages.
if git show-ref --quiet --verify "refs/remotes/origin/$TARGET_BRANCH"; then
  echo "Checkout target branch"
  git checkout "$TARGET_BRANCH"
else
  echo "Create target branch"
  git checkout --orphan "$TARGET_BRANCH"
  git rm -rf .
fi

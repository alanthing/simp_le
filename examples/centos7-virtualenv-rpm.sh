#!/bin/bash

## About: Create RPM for simp_le in a virtualenv via mock, pypiserver, and fpm.
##        Post-install script will create the symlink /usr/bin/simp_le, and the
##        post-uninstall script will remove it.
## How-to:
##        - Set SIMPLE_COMMIT to the git commit hash
##        - SIMPLE_VERSION can be set to anything you will later increment
##          (change if https://github.com/kuba/simp_le/blob/master/setup.py#L9 is never not '0')
##        - SIMPLE_RELEASE can be changed if you need to repackage the RPM
## Requirements:
##        Install 'mock' and add your user to the mock group:
##        $ sudo yum -y install mock
##        $ sudo usermod --append --groups mock "$(whoami)"


# Stop with any errors
set -e ; set -o pipefail
# Set shell debug output
set -x


# git commit hash in https://github.com/kuba/simp_le.git
SIMPLE_COMMIT='3a103b7'
# simp_le has no versions; set desired version number
SIMPLE_VERSION='0.1.0'
# For RPM packaging, set a release. You should only change this if there's a non-code change
SIMPLE_RELEASE='1'


############
# CentOS 7 #
############

# Scrub
mock --scrub=all

mock --install ruby ruby-devel rubygems
mock --shell <<EOF
gem install --verbose --no-ri --no-rdoc fpm
EOF

mock --install git python-virtualenv libffi-devel openssl-devel
mock --shell <<EOF
virtualenv /tmp/venv-pypi
source /tmp/venv-pypi/bin/activate

pip install -U pip setuptools
pip install pypiserver

git clone https://github.com/kuba/simp_le.git /tmp/simp_le-code 
git --git-dir=/tmp/simp_le-code/.git --work-tree=/tmp/simp_le-code reset --hard $SIMPLE_COMMIT
sed -r -e "s/^(version[[:blank:]]*=[[:blank:]]*')0'/\1${SIMPLE_VERSION}'/" -i /tmp/simp_le-code/setup.py

pushd /tmp/simp_le-code
python setup.py sdist
popd

pypi-server -p 8080 -P . -a . /tmp/simp_le-code/dist &

pip install -U virtualenv-tools

cat > /tmp/after-install.sh <<END
if [[ \$(readlink /usr/bin/simp_le) != /usr/share/python-venvs/simp_le/bin/simp_le ]]; then ln -sf /usr/share/python-venvs/simp_le/bin/simp_le /usr/bin/simp_le; fi
END
cat > /tmp/before-remove.sh <<END
find /usr/share/python-venvs/simp_le/ -name *.pyc -delete
END
cat > /tmp/after-remove.sh <<END
if [[ \$(readlink /usr/bin/simp_le) = /usr/share/python-venvs/simp_le/bin/simp_le ]]; then rm -f /usr/bin/simp_le; fi
if ( find /usr/share/python-venvs/ -type d -empty | grep -q '' ); then rmdir /usr/share/python-venvs/; fi
END

/usr/local/bin/fpm \
  --verbose \
  -s virtualenv \
  -t rpm \
  --iteration "$SIMPLE_RELEASE.$SIMPLE_COMMIT" \
  --rpm-dist el7 \
  --package /tmp/ \
  --depends python \
  --license "GPLv3" \
  --url "https://github.com/kuba/simp_le" \
  --description "Simple Let's Encrypt Client" \
  --virtualenv-pypi http://localhost:8080/simple/ \
  --virtualenv-package-name-prefix virtualenv \
  --virtualenv-install-location /usr/share/python-venvs/ \
  --directories /usr/share/python-venvs/simp_le \
  --after-install /tmp/after-install.sh \
  --before-remove /tmp/before-remove.sh \
  --after-remove /tmp/after-remove.sh \
  simp_le==$SIMPLE_VERSION
EOF

# Copy completed file
cp -av /var/lib/mock/epel-7-x86_64/root/tmp/*.rpm .

# Scrub
mock --scrub=all

# Completed
exit 0

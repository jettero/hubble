#!/bin/bash

# use the global pyenv version
eval "$(pyenv init -)"

( set -x
# reset source to correct checkout and fix version files
# do this in a subshell so the path automatically returns
cd "$HUBBLE_SRC_PATH"
git checkout -B build
git reset --hard "$HUBBLE_CHECKOUT"
git clean -dfx

# build the version file
cat > hubblestack/__init__.py << EOF
__version__ = '$HUBBLE_VERSION'
__buildinfo__ = {'branch': '$HUBBLE_CHECKOUT',
    'last_commit': '$(git describe --long --dirty --always --tags)'}
EOF
)

# if ENTRYPOINT is given a CMD other than nothing
# abort here and do that other CMD
if [ $# -gt 0 ]
then exec "$@"
fi

# from now on, exit on error (rather than && every little thing)
set -x -e

cp -rf "$HUBBLE_SRC_PATH"/* /hubble_build/

# possibly replace the version file
if [ -f /data/hubble_buildinfo ]
then cp /data/hubble_buildinfo /hubble_build/hubblestack/__init__.py
fi

pyinstaller --onedir --noconfirm --log-level ${_BINARY_LOG_LEVEL} \
    --additional-hooks-dir=${_HOOK_DIR} \
    --runtime-hook=pkg/pyinstaller-runtimehooks/pathopthubble.py \
    hubble.py

mkdir -p /var/log/hubble_osquery/backuplogs

# hubble default configuration file
cp -rf /hubble_build/conf/hubble /etc/hubble/
cp -rf /hubble_build/conf/hubble-profile.sh /etc/profile.d/
cp -pr /hubble_build/dist/hubble /opt/hubble/hubble-libs
ln -s /opt/hubble/hubble-libs/hubble /opt/hubble/hubble

rm -rf /opt/hubble/hubble-libs/librpm*

# rpm pkg start
tar -cPvzf /data/hubblestack-${HUBBLE_VERSION}.tar.gz /etc/hubble \
    /opt/hubble /opt/osquery /etc/profile.d/hubble-profile.sh \
    /var/log/hubble_osquery/backuplogs

mkdir -p /hubble_build/debbuild/hubblestack-${HUBBLE_VERSION}
tar -xzvf /data/hubblestack-${HUBBLE_VERSION}.tar.gz -C \
    /hubble_build/debbuild/hubblestack-${HUBBLE_VERSION}

mkdir -p /hubble_build/debbuild/hubblestack-${HUBBLE_VERSION}/usr/lib/systemd/system
cp /hubble_build/pkg/hubble.service \
    /hubble_build/debbuild/hubblestack-${HUBBLE_VERSION}/usr/lib/systemd/system/
cp -f /hubble_build/conf/hubble \
    /hubble_build/debbuild/hubblestack-${HUBBLE_VERSION}/etc/hubble/

# during container run, if a configuration file exists in a /data copy it over
# the existing one so it would be possile to optionally include a custom one
# with the package
if [ -f /data/hubble ]
then cp /data/hubble /hubble_build/debbuild/hubblestack-${HUBBLE_VERSION}/etc/hubble/
fi

# also bring in anything from a /data/opt/ directory so we can bundle other executables if needed
if [ -d /data/opt ]
then cp -r /data/opt/* /hubble_build/debbuild/hubblestack-${HUBBLE_VERSION}/opt/
fi

# symlink to have hubble binary in path
cd /hubble_build/debbuild/hubblestack-${HUBBLE_VERSION}
mkdir -p usr/bin
ln -s /opt/hubble/hubble usr/bin/hubble

# fpm start
fpm -s dir -t rpm \
    -n hubblestack \
    -v ${HUBBLE_VERSION} \
    --iteration ${HUBBLE_ITERATION} \
    --url ${HUBBLE_URL} \
    --description "${HUBBLE_DESCRIPTION}" \
    --rpm-summary "${HUBBLE_SUMMARY}" \
    --after-install /hubble_build/conf/afterinstall-systemd.sh \
    --after-upgrade /hubble_build/conf/afterupgrade-systemd.sh \
    --before-remove /hubble_build/conf/beforeremove.sh \
    etc/hubble opt usr /var/log/hubble_osquery/backuplogs

# edit to change iteration number, if necessary
cp hubblestack-${HUBBLE_VERSION}-${HUBBLE_ITERATION}.x86_64.rpm \
    /data/hubblestack-${HUBBLE_VERSION}-${HUBBLE_ITERATION}.el7.x86_64.rpm

openssl dgst -sha256 /data/hubblestack-${HUBBLE_VERSION}-${HUBBLE_ITERATION}.el7.x86_64.rpm \
    > /data/hubblestack-${HUBBLE_VERSION}-${HUBBLE_ITERATION}.el7.x86_64.rpm.sha256

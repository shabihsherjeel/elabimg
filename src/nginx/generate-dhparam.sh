#!/bin/bash
# from https://github.com/jwilder/nginx-proxy

# The first argument is the bit depth of the dhparam, or 2048 if unspecified
DHPARAM_BITS=${1:-2048}

# If a dhparam file is not available, use the pre-generated one and generate a new one in the background.
# Note that /etc/nginx/dhparam is a volume, so this dhparam will persist restarts.
PREGEN_DHPARAM_FILE="/etc/nginx/dhparam.default.pem"
DHPARAM_FILE="/etc/nginx/certs/dhparam.pem"
GEN_LOCKFILE="/tmp/dhparam_generating.lock"

# The hash of the pregenerated dhparam file is used to check if the pregen dhparam is already in use
PREGEN_HASH=$(md5sum $PREGEN_DHPARAM_FILE | cut -d" " -f1)
if [[ -f $DHPARAM_FILE ]]; then
    CURRENT_HASH=$(md5sum $DHPARAM_FILE | cut -d" " -f1)
    if [[ "$PREGEN_HASH" != "$CURRENT_HASH" ]]; then
        # There is already a dhparam, and it's not the default
        if [ "${silent_init}" = false ]; then
            echo "Custom dhparam.pem file found, generation skipped"
        fi
        exit 0
    fi

    if [[ -f $GEN_LOCKFILE ]]; then
        # Generation is already in progress
        exit 0
    fi
fi

if [ "${silent_init}" = false ]; then
cat >&2 <<EOT
INFO: A pre-generated dhparam.pem will be used for now while a new one
is being generated in the background. Once the new dhparam.pem is in place, nginx will be reloaded.
EOT
fi

# Put the default dhparam file in place so we can start immediately
cp $PREGEN_DHPARAM_FILE $DHPARAM_FILE
touch $GEN_LOCKFILE

# Generate a new dhparam in the background in a low priority and reload nginx when finished (grep removes the progress indicator).
(
    (
        nice -n +5 openssl dhparam -out "${DHPARAM_FILE}.tmp" "${DHPARAM_BITS}" 2>&1 \
        && mv $DHPARAM_FILE.tmp $DHPARAM_FILE \
        && echo "INFO: New dhparam generation complete, reloading nginx..." \
        && nginx -s reload
    ) | grep -vE '^[\.+]+'
    rm $GEN_LOCKFILE
) &

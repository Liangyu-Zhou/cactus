#!/usr/bin/env bash
# Copyright 2020-2022 Hyperledger Cactus Contributors
# SPDX-License-Identifier: Apache-2.0

set -e

ROOT_DIR="../.." # Path to cactus root dir
CONFIG_VOLUME_PATH="./etc/cactus" # Docker volume with shared configuration
WAIT_TIME=10 # How often to check container status
 
# Cert options
CERT_CURVE_NAME="prime256v1"
CERT_COUNTRY="JP"
CERT_STATE="Tokyo"
CERT_LOCALITY="Minato-Ku"
CERT_ORG="CactusSamples"

# generate_certificate <common-name> <destination>
function generate_certificate() {
    # Check OpenSSL command existance
    if ! openssl version > /dev/null; then
        echo "Could not execute [openssl version], check if OpenSSL tool is available on the system."
        exit 1;
    fi

    # Check input parameters
    ARGS_NUMBER=2
    if [ "$#" -lt "$ARGS_NUMBER" ]; then
        echo "generate_certificate called with wrong number of arguments (expected - $ARGS_NUMBER, actual - $#)";
        exit 2
    fi

    common_name=$1
    destination=$2
    subject="/C=$CERT_COUNTRY/ST=$CERT_STATE/L=$CERT_LOCALITY/O=$CERT_ORG/CN=$common_name"
    echo "Create new cert in '${destination}' with subject '${subject}'"

    # Crete destination path
    if [ ! -d "$destination" ]; then
        echo "Re-create destination dir..."
        rm -rf "$destination"
        mkdir -p "$destination"
    fi

    keyPath="${destination}/connector.priv"
    csrPath="${destination}/connector.csr"
    certPath="${destination}/connector.crt"

    # Generate keys
    openssl ecparam -genkey -name "$CERT_CURVE_NAME" -out "$keyPath"
    openssl req -new -sha256 -key "$keyPath" -out "$csrPath" -subj "$subject"
    openssl req -x509 -sha256 -days 365 -key "$keyPath" -in "$csrPath" -out "$certPath"
}

function start_ethereum_testnet() {
    pushd "${ROOT_DIR}/tools/docker/geth-testnet"
    ./script-start-docker.sh
    popd
}

function copy_ethereum_validator_config() {
    echo ">> copy_ethereum_validator_config()"
    cp -fr ${ROOT_DIR}/packages/cactus-plugin-ledger-connector-go-ethereum-socketio/sample-config/* \
        "${CONFIG_VOLUME_PATH}/connector-go-ethereum-socketio/"
    generate_certificate "GoEthereumCactusValidator" "${CONFIG_VOLUME_PATH}/connector-go-ethereum-socketio/CA/"
    echo ">> copy_ethereum_validator_config() done."
}

function copy_tcs_config() {
    cp -fr ${ROOT_DIR}/packages/cactus-plugin-ledger-connector-tcs/sample-config/* \
        "${CONFIG_VOLUME_PATH}/connector-tcs/"
    generate_certificate "TcsCactusValidator" "${CONFIG_VOLUME_PATH}/connector-tcs/CA/"
}

function start_tcs_agent(){
    echo ">> start_tcs_agent()"
    docker network create tcs_testnet_1x
    pushd ${ROOT_DIR}/tools/docker/tcs-testnet/agent/example
    docker-compose up > tcs-agent.log &
    popd
    echo ">> start_tcs_agent() done"
}

function start_ledgers() {
    # Clear ./etc/cactus
    mkdir -p "${CONFIG_VOLUME_PATH}/"
    rm -fr ${CONFIG_VOLUME_PATH}/*

    # Copy cmd-socketio-config
    cp -f ./config/*.yaml "${CONFIG_VOLUME_PATH}/"

    # Start Ethereum
    mkdir -p "${CONFIG_VOLUME_PATH}/connector-go-ethereum-socketio"
    start_ethereum_testnet
    copy_ethereum_validator_config

    # Start tcs-agent
    mkdir -p "${CONFIG_VOLUME_PATH}/connector-tcs"
    start_tcs_agent
    copy_tcs_config

}

start_ledgers

echo "All Done."

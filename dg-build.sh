#!/bin/bash

set -euxo pipefail

PROJECT_NAME=dg-platform
PROJECT_ID=dg-platform
CLUSTER_NAME=cluster-1
CLOUDSDK_COMPUTE_ZONE=us-central1-c
CLOUD_SDK_DOWNLOAD_LINK=https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-180.0.1-linux-x86_64.tar.gz

function install_gcloud {
    cd /root
    curl -L $CLOUD_SDK_DOWNLOAD_LINK | tar xz
    CLOUDSDK_CORE_DISABLE_PROMPTS=1 ./google-cloud-sdk/install.sh
    echo 'export PATH=/root/google-cloud-sdk/bin/:$PATH' >> $BASH_ENV
}

function configure_gcloud {
    gcloud --quiet components update
    gcloud --quiet components update kubectl
    echo ${GCLOUD_SERVICE_KEY} | base64 --decode -i > ${HOME}/gcloud-service-key.json
    gcloud auth activate-service-account --key-file ${HOME}/gcloud-service-key.json
    gcloud config set project ${PROJECT_ID}
    gcloud --quiet config set container/cluster ${CLUSTER_NAME}
    gcloud config set compute/zone ${CLOUDSDK_COMPUTE_ZONE}
    gcloud --quiet container clusters get-credentials ${CLUSTER_NAME}
}

function install_docker_client {
    cd /root
    VER="17.03.0-ce"
    curl -L -o /tmp/docker-$VER.tgz https://get.docker.com/builds/Linux/x86_64/docker-$VER.tgz
    tar -xz -f /tmp/docker-$VER.tgz
    echo 'export PATH=/root/docker:$PATH' >> $BASH_ENV
}

function build_image {
    gcloud docker -- build -t shiny-apps:$CIRCLE_SHA1 .
}

function push_image {
    docker tag shiny-apps:$CIRCLE_SHA1 gcr.io/dg-platform/shiny-apps:$CIRCLE_TAG
    gcloud docker -- push gcr.io/dg-platform/shiny-apps:$CIRCLE_TAG
}

function redeploy_k8s {
    NAMESPACE=$1
    
    kubectl -n $NAMESPACE patch deployment/server -p '{"spec":{"template":{"spec":{"containers":[{"name":"server","image":"gcr.io/dg-platform/shiny-apps:'"$CIRCLE_TAG"'"}]}}}}'
}

# run the given function with args
$*

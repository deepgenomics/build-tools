#!/bin/bash

set -euxo pipefail

PROJECT_NAME=dg-platform
PROJECT_ID=dg-platform
CLUSTER_NAME=cluster-1
CLOUDSDK_COMPUTE_ZONE=us-central1-c
CLOUD_SDK_DOWNLOAD_LINK=https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-180.0.1-linux-x86_64.tar.gz

function add_env_command {
    echo "$*" >> $BASH_ENV
}

function add_env_path {
    component="$1"
    echo "export PATH=${component}:\$PATH" >> $BASH_ENV
}

function add_env_var {
    var=$1
    value=$2
    echo "export ${var}=${value}" >> $BASH_ENV
}

function download_miniconda {
    if [ `uname` = "Darwin" ]; then
	URL=https://repo.continuum.io/miniconda/Miniconda2-latest-MacOSX-x86_64.sh
    else
	URL=https://repo.continuum.io/miniconda/Miniconda2-latest-Linux-x86_64.sh
    fi
    curl $URL -o /tmp/miniconda.sh
}

function install_miniconda {
    # install miniconda
    bash /tmp/miniconda.sh -b -f -p $HOME/miniconda

    # source the script that makes the "conda" tool available
    add_env_command ". $HOME/miniconda/etc/profile.d/conda.sh"
}

function create_conda_environment {
    conda env create -f $1
}

function activate_conda_environment {
    add_env_command "conda activate $1"
}

function install_golang {
    if [ `uname` = "Darwin" ]; then
	URL=https://dl.google.com/go/go1.11.1.darwin-amd64.tar.gz
    else
	URL=https://dl.google.com/go/go1.11.1.linux-amd64.tar.gz
    fi
    curl -L $URL | (cd $HOME; tar zxf -)

    add_env_path "$HOME/go/bin"
}

function install_gcloud {
    cd ~
    curl -L $CLOUD_SDK_DOWNLOAD_LINK | tar xz
    CLOUDSDK_CORE_DISABLE_PROMPTS=1 ./google-cloud-sdk/install.sh
    add_env_path "$HOME/google-cloud-sdk/bin"
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
    gcloud --quiet auth configure-docker
}

function install_docker_client {
    cd $HOME
    VER="17.03.0-ce"
    curl -L -o /tmp/docker-$VER.tgz https://get.docker.com/builds/Linux/x86_64/docker-$VER.tgz
    tar zxf /tmp/docker-$VER.tgz
    add_env_path "$HOME/docker"
}

function circleci_upload_anaconda {
    RECIPE_PATH=$1
    VERSION=$2
    export VERSION_MATCH_PATTERN="v([^,\)]+)|([0-9]+(\.[0-9]+)*))"
    export PACKAGE_FILENAME=`conda build --output ${RECIPE_PATH}`
    if [ "${CIRCLE_BRANCH}" == "master" ] || [[ "${VERSION}" =~ $VERSION_MATCH_PATTERN ]]; then
        if [[ "${VERSION}" =~ $VERSION_MATCH_PATTERN ]]; then
            # Upload with "main" label
            anaconda --token ${ANACONDA_TOKEN} upload --force --user deepgenomics --private ${PACKAGE_FILENAME}
        else
            # Upload with "dev" label
            anaconda --token ${ANACONDA_TOKEN} upload --force --user deepgenomics --private ${PACKAGE_FILENAME} --label dev
        fi
    fi

}

function upload_conda_package {
    RECIPE_PATH=$1
    export VERSION_MATCH_PATTERN="v([^,\)]+)|([0-9]+(\.[0-9]+)*))"
    export PACKAGE_FILENAME=`conda build --output ${RECIPE_PATH}`
    if [ "${CIRCLE_BRANCH}" == "master" ] || [[ "${CIRCLE_TAG}" =~ $VERSION_MATCH_PATTERN ]]; then
        if [[ "${CIRCLE_TAG}" =~ $VERSION_MATCH_PATTERN ]]; then
            # Upload with "main" label
            anaconda --token ${ANACONDA_TOKEN} upload --force --user deepgenomics --private ${PACKAGE_FILENAME}
        else
            # Upload with "dev" label
            anaconda --token ${ANACONDA_TOKEN} upload --force --user deepgenomics --private ${PACKAGE_FILENAME} --label dev
        fi
    fi
}

# run the given function with args
$*

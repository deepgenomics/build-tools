#!/bin/bash

set -euxo pipefail

PROJECT_NAME=dg-platform
PROJECT_ID=dg-platform
CLUSTER_NAME=cluster-1
CLOUDSDK_COMPUTE_ZONE=us-central1-c
CLOUD_SDK_DOWNLOAD_LINK=https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-261.0.0-linux-x86_64.tar.gz

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
    add_env_command "if ! command -v conda >/dev/null 2>&1 ; then . ${HOME}/miniconda/etc/profile.d/conda.sh ; fi"
}

function create_conda_environment {
    conda env create -f $1
}

function activate_conda_environment {
    add_env_command "conda activate $1"
}

function configure_conda {
    conda config --set always_yes yes --set changeps1 no
    conda config --append channels conda-forge
    conda config --append channels bioconda
    conda config --append channels deepgenomics

    # configure authentication
    token_dir=$HOME/.continuum/anaconda-client/tokens
    mkdir -p $token_dir
    echo -n $ANACONDA_TOKEN > $token_dir/https%3A%2F%2Fapi.anaconda.org.token
    chmod 0600 $token_dir/https%3A%2F%2Fapi.anaconda.org.token
    token_dir=$HOME/.config/binstar
    mkdir -p $token_dir
    echo -n $ANACONDA_TOKEN > $token_dir/https%3A%2F%2Fapi.anaconda.org.token
    chmod 0600 $token_dir/https%3A%2F%2Fapi.anaconda.org.token

    if [ `uname` = "Darwin" ]; then
	token_dir="$HOME/Library/Application Support/binstar"
	mkdir -p "$token_dir"
	echo -n $ANACONDA_TOKEN > "$token_dir/https%3A%2F%2Fapi.anaconda.org.token"
	chmod 0600 "$token_dir/https%3A%2F%2Fapi.anaconda.org.token"
    fi

    # print some conda info (helpful for debugging)
    conda info -a
}

function install_golang {
    if [ `uname` = "Darwin" ]; then
	URL=https://dl.google.com/go/go1.13.darwin-amd64.tar.gz
    else
	URL=https://dl.google.com/go/go1.13.linux-amd64.tar.gz
    fi
    curl -L $URL | (cd $HOME; tar zxf -)

    add_env_path "$HOME/go/bin"
    add_env_var "GOPRIVATE" "github.com/deepgenomics"
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
    echo "export GOOGLE_APPLICATION_CREDENTIALS=${HOME}/gcloud-service-key.json" >> $BASH_ENV
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

function is_master_branch {
    if [ "${CIRCLE_BRANCH:-}" = "master" ]; then
	return 0
    else
	return 1
    fi
}

function is_version_tag {
    version_pattern="^v[0-9]+\.[0-9]+\.[0-9]+$"
    if [ ! -z "${CIRCLE_TAG:-}" ]; then
	if [[ "${CIRCLE_TAG}" =~ $version_pattern ]]; then
	    return 0
	else
	    return 1
	fi
    else
	return 1
    fi
}

function is_master_or_version_tag {
    if is_master_branch; then
	return 0
    fi

    if is_version_tag; then
	return 0
    fi

    return 1
}

function upload_conda_package {
    RECIPE_PATH=$1
    export PACKAGE_FILENAME=`conda build --output ${RECIPE_PATH}`
    if is_version_tag; then
        # Upload with "main" label
        anaconda --token ${ANACONDA_TOKEN} upload --force --user deepgenomics --private ${PACKAGE_FILENAME}
    elif is_master_branch; then
        # Upload with "dev" label
        anaconda --token ${ANACONDA_TOKEN} upload --force --user deepgenomics --private ${PACKAGE_FILENAME} --label dev
    fi
}

function deploy_sphinx_docs {
    PROJECT_NAME=$1
    BUILD_PATH=$2
    if is_master_or_version_tag; then
        echo $GCLOUD_SERVICE_KEY | base64 --decode > $HOME/gcloud-service-key.json
        source $HOME/google-cloud-sdk/path.bash.inc
        gcloud auth activate-service-account --key-file $HOME/gcloud-service-key.json
        gcloud config set project dg-platform
        if is_version_tag; then
            version=${CIRCLE_TAG}
        else
            version=master
        fi
        cd $BUILD_PATH
        mv html $version

	# See: https://github.com/travis-ci/travis-ci/issues/7940
	export BOTO_CONFIG=/dev/null

        gsutil -m rsync -d -r $version gs://dg-docs/$PROJECT_NAME/$version
    else
	echo "Skipping deploy docs: not on master branch"
    fi
}

# run the given function with args
$*

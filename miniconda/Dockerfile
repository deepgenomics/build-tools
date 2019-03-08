# This image just like the one from continuum except for a couple of
# changes.  It's a bit more optimized because I did all the "apt-get"
# stuff together and cleaned up the apt cache.  Also, /opt/conda/bin
# (ie. the base environment) is not in the path.  However, the conda
# profile script is sourced when bash starts.  As a result, this image
# is good for running shell scripts and for acting as a base image
# (but the sub-image will have to add a conda environment to the
# path).
#
# docker build . -t gcr.io/dg-platform/miniconda2:4.5.11
# docker push gcr.io/dg-platform/miniconda2:4.5.11

FROM debian:latest

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

RUN apt-get update --fix-missing && \
    apt-get install -y \
      wget \
      bzip2 \
      ca-certificates \
      libglib2.0-0 libxext6 \
      libsm6 \
      libxrender1 \
      git \
      curl \
      grep \
      sed \
      dpkg && \
    TINI_VERSION=`curl https://github.com/krallin/tini/releases/latest | grep -o "/v.*\"" | sed 's:^..\(.*\).$:\1:'` && \
    curl -L "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini_${TINI_VERSION}.deb" > tini.deb && \
    dpkg -i tini.deb && \
    rm tini.deb && \
    rm -rf /var/lib/apt/lists/*

RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda2-4.5.11-Linux-x86_64.sh -O ~/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p /opt/conda && \
    rm ~/miniconda.sh && \
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
    echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc

ENTRYPOINT [ "/usr/bin/tini", "--" ]
CMD [ "/bin/bash" ]

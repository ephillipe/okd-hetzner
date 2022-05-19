FROM docker.io/alpine:3.15.4

ARG okd_tools_version
ENV okd_tools_version=${okd_tools_version}

RUN apk update && \
    apk add \
      bash \
      ca-certificates \
      openssh-client \
      openssl \
      ansible \
      make \
      rsync \
      curl \
      git \
      jq \
      libc6-compat \
      apache2-utils \
      python3 \
      py3-pip \
      libvirt-client

# OKD installer
COPY openshift-install-linux-${okd_tools_version}.tar.gz .
COPY openshift-client-linux-${okd_tools_version}.tar.gz .

RUN tar vxzf openshift-install-linux-${okd_tools_version}.tar.gz openshift-install && \
    tar vxzf openshift-client-linux-${okd_tools_version}.tar.gz oc && \
    tar vxzf openshift-client-linux-${okd_tools_version}.tar.gz kubectl && \
    mv openshift-install /usr/local/bin/openshift-install && \
    mv oc /usr/local/bin/oc && \
    mv kubectl /usr/local/bin/kubectl && \
    rm openshift-install-linux-${okd_tools_version}.tar.gz && \
    rm openshift-client-linux-${okd_tools_version}.tar.gz

# Create workspace
RUN mkdir /workspace
WORKDIR /workspace
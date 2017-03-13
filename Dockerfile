FROM ubuntu

MAINTAINER Lachlan Evenson <lachlan@deis.com>

ENV KUBE_LATEST_VERSION="v1.4.7"

RUN apt-get update && apt-get install -y \
    curl \
    jq \
    && curl -L https://storage.googleapis.com/kubernetes-release/release/${KUBE_LATEST_VERSION}/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && rm -rf /var/lib/apt/lists/*

COPY pod-requeue.sh .

CMD ["/pod-requeue.sh"]

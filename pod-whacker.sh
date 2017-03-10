#!/bin/sh

POD_DUMP_JSON=pod-dump.json

export_pods() {
    kubectl get po --export --all-namespaces -o json | jq '.items[] | select(.status.conditions[].reason) | select((.status.conditions[].reason == "Unschedulable") or (.status.conditions[].reason == "OutOfcpu")) |
  del(
    .status,
    .spec.dnsPolicy,
    .spec.securityContext,
    .spec.terminationGracePeriodSeconds,
    .spec.restartPolicy,
    .metadata.uid,
    .metadata.selfLink,
    .metadata.resourceVersion,
    .metadata.creationTimestamp,
    .metadata.generation
  )'  > $POD_DUMP_JSON
}

whack_pods() {
  echo "Deleting stuck pods and recreating..."
  kubectl delete -f $POD_DUMP_JSON && \
  kubectl create -f $POD_DUMP_JSON
}

export_pods
whack_pods

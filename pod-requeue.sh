#!/bin/sh

if [[ $1 != "--execute" ]]; then
  DRY_RUN=true
else
  DRY_RUN=false
fi

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
	export_pods
	POD_LIST=$(cat $POD_DUMP_JSON)

  if [[ $DRY_RUN == true ]]; then
    echo "** Dry run: not executing. The following pods match for deletion:"
		echo $POD_LIST | jq '(.metadata.name) | "Pod: \(.)"'
		exit
  fi

  echo "Deleting stuck pods and recreating..."
  kubectl delete -f $POD_DUMP_JSON && \
  kubectl create -f $POD_DUMP_JSON
}

whack_pods $1

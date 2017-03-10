#!/bin/sh

if [[ $1 != "--execute" ]]; then
  DRY_RUN=true
else
  DRY_RUN=false
fi

POD_DUMP_RAW_JSON=pod-dump-raw.json
POD_DUMP_JSON=pod-dump.json

SLEEP=60

export_pods() {

  # Collect list of all pods matching Status conditions reason of Unschedulable OR OutOfcpu
    kubectl get po --export --all-namespaces -o json | jq '.items[] | select(.status.conditions[].reason) | select((.status.conditions[].reason == "Unschedulable") or (.status.conditions[].reason == "OutOfcpu"))' > $POD_DUMP_RAW_JSON
}

process_pods() {
    # Remove server generated fields
    cat $POD_DUMP_RAW_JSON | jq '
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

pod_requeue() {

  # Dry run loop
  if [[ $DRY_RUN == true ]]; then
    while true; do
      export_pods
      RAW_POD_LIST=$(cat $POD_DUMP_RAW_JSON)
      echo "** Dry run: not executing. The following pods match for deletion:"
      cat $POD_DUMP_RAW_JSON | jq -r '[.metadata.name,.metadata.namespace,.status.conditions[].reason] | "Pod:\(.[0]) Namespace:\(.[1]) Reason:\(.[2])"'
      echo "Sleeping for ${SLEEP} seconds"
      sleep $SLEEP
    done
    exit
  fi

  # Loop to find, delete and recreate matched pods
  while true; do

    # Collect matching pods and process
    export_pods
    process_pods

    POD_LIST=$(cat $POD_DUMP_JSON)

    # Do not run unless there's data in the processed pod dump file
    if [ ! -s $POD_DUMP_JSON ]; then
      echo "${POD_DUMP_JSON} is empty. Nothing to process"
    else
      echo "Deleting and recreating the following pods"
      cat $POD_DUMP_RAW_JSON | jq -r '[.metadata.name,.metadata.namespace,.status.conditions[].reason] | "Pod:\(.[0]) Namespace:\(.[1]) Reason:\(.[2])"'
      echo "---"
      kubectl delete -f $POD_DUMP_JSON && \
      kubectl create -f $POD_DUMP_JSON
    fi
    echo "---\nSleeping for ${SLEEP} seconds"
    sleep $SLEEP
  done
}

pod_requeue $1

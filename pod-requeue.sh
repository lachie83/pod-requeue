#!/bin/bash

if [[ $1 != "--execute" ]]; then
  DRY_RUN=true
else
  DRY_RUN=false
fi

POD_DUMP_RAW_JSON=pod-dump-raw.json
POD_DUMP_JSON=pod-dump.json

SLEEP=60

# confirm access to kube-api
test_kubectl() {
  if kubectl get nodes > /dev/null 2>&1 ; then
    echo "kubectl command success"
  else
    echo "kubectl cannot communicate with a kube-api. exit"
    exit 1
  fi
}

export_pods() {

  # Collect list of all pods matching Status conditions reason of InsufficientFreeCPU OR OutOfcpu
  kubectl get po --export --all-namespaces -o json | jq '.items[] | select(.status.reason) | select((.status.reason == "InsufficientFreeCPU") or (.status.reason == "OutOfcpu"))' > $POD_DUMP_RAW_JSON

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

  test_kubectl

  # Dry run loop
  if [[ $DRY_RUN == true ]]; then
    while true; do

      export_pods

      if [ ! -s $POD_DUMP_RAW_JSON ]; then
        echo "${POD_DUMP_RAW_JSON} is empty. Nothing to process"
      else
        echo "** Dry run: not executing. The following pods match for deletion:"
        cat $POD_DUMP_RAW_JSON | jq -r '[.metadata.name,.metadata.namespace,.status.reason] | "Pod:\(.[0]) Namespace:\(.[1]) Reason:\(.[2])"'
      fi

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

    # Do not run unless there's data in the processed pod dump file
    if [ ! -s $POD_DUMP_JSON ]; then
      echo `date +%D %H:%M:%S`
      echo "${POD_DUMP_JSON} is empty. Nothing to process"
    else
      echo `date +%D-%H:%M:%S`
      echo "Deleting and recreating the following pods"
      cat $POD_DUMP_RAW_JSON | jq -r '[.metadata.name,.metadata.namespace,.status.reason] | "Pod:\(.[0]) Namespace:\(.[1]) Reason:\(.[2])"'
      echo "---"
      echo `date +%D-%H:%M:%S`
      echo "Running delete"
      kubectl delete -f $POD_DUMP_JSON
      echo "Retrying delete to catch any stragglers"
      kubectl delete -f $POD_DUMP_JSON || true
      echo `date +%D-%H:%M:%S`
      echo "Running create"
      kubectl create -f $POD_DUMP_JSON
      echo "Retrying create to catch any stragglers"
      kubectl create -f $POD_DUMP_JSON || true
    fi
    echo "---"
    echo "Sleeping for ${SLEEP} seconds"
    sleep $SLEEP
  done
}

pod_requeue

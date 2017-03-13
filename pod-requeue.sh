#!/bin/bash

if [[ $1 != "--execute" ]]; then
  DRY_RUN=true
else
  DRY_RUN=false
fi

POD_LIST=pod-list.txt
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
    # Find pods in status 'OutOfcpu|InsufficientFreeCPU' without using jsonpath
    # This is a workaround until the status.conditions maps are available in the output of a raw get
    # kubectl get pods --no-headers=true --all-namespaces | egrep -i 'OutOfcpu|InsufficientFreeCPU'
    # clean up files from existing run
    rm -f $POD_LIST
    rm -f $POD_DUMP_RAW_JSON

    # build list of matching pods which should have the following format
    #
    # alloc             flashgames-ozsx01at                                                  0/1       InsufficientFreeCPU       0         1h
    # alloc             flashgames-rkapz2gg                                                  0/1       InsufficientFreeCPU       0         1h
    # alloc             flashgames-ro12oauq                                                  0/1       InsufficientFreeCPU       0         54m

    kubectl get po --all-namespaces | egrep -i 'OutOfcpu|InsufficientFreeCPU' > $POD_LIST

    if [ ! -s $POD_LIST ]; then
      echo "${POD_LIST} is empty. No pods found"
    else
      # build kubectl command to look like `kubectl get pod croc-hunter3 -n x -o json >> pod-dump-raw.json` and run it through xargs
      cat ${POD_LIST} | awk '{print "get pod "$2 " -n "$1 " -o json"}' | xargs -L1 -t kubectl >> $POD_DUMP_RAW_JSON
    fi
}

# Disabling until we can we determine why outputed metadata is different
#export_pods() {

  # Collect list of all pods matching Status conditions reason of Unschedulable OR OutOfcpu
#    kubectl get po --export --all-namespaces -o json | jq '.items[] | select(.status.conditions[].reason) | select((.status.conditions[].reason == "InsufficientFreeCPU") or (.status.conditions[].reason == "OutOfcpu"))' > $POD_DUMP_RAW_JSON
#}

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
        #cat $POD_DUMP_RAW_JSON | jq -r '[.metadata.name,.metadata.namespace,.status.conditions[].reason] | "Pod:\(.[0]) Namespace:\(.[1]) Reason:\(.[2])"'
        cat ${POD_LIST} | awk '{print "Namespace:"$1 " Pod:"$2 " Reason:"$4}'
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
      echo "${POD_DUMP_JSON} is empty. Nothing to process"
    else
      echo "Deleting and recreating the following pods"
      #cat $POD_DUMP_RAW_JSON | jq -r '[.metadata.name,.metadata.namespace,.status.conditions[].reason] | "Pod:\(.[0]) Namespace:\(.[1]) Reason:\(.[2])"'
      cat ${POD_LIST} | awk '{print "Namespace:"$1 " Pod:"$2 " Reason:"$4}'
      echo "---"
      kubectl delete -f $POD_DUMP_JSON && \
      kubectl create -f $POD_DUMP_JSON
    fi
    echo "---"
    echo "Sleeping for ${SLEEP} seconds"
    sleep $SLEEP
  done
}

pod_requeue

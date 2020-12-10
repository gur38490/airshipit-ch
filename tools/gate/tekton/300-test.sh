#!/bin/bash

set -eux

TEKTON_NS="tekton-pipelines"

# Runs the tekton pipeline trigger test
function retry {
  local n=1
  local max=5
  local delay=10

  while true; do
    "$@" && break || {
      if [[ $n -lt $max ]]; then
        (( n++ ))
        sleep $delay
      else
        echo "failed after $n attempts." >&2
        exit 1
      fi
    }
  done
}

sleep 60

kubectl -n $TEKTON_NS apply -f ./tools/gate/tekton/yaml/role-resources/secret.yaml
kubectl -n $TEKTON_NS apply -f ./tools/gate/tekton/yaml/role-resources/serviceaccount.yaml
kubectl -n $TEKTON_NS apply -f ./tools/gate/tekton/yaml/role-resources/clustertriggerbinding-roles
kubectl -n $TEKTON_NS apply -f ./tools/gate/tekton/yaml/role-resources/triggerbinding-roles
retry kubectl -n $TEKTON_NS apply -f ./tools/gate/tekton/yaml/triggertemplates/triggertemplate.yaml
retry kubectl -n $TEKTON_NS apply -f ./tools/gate/tekton/yaml/triggerbindings/triggerbinding.yaml
retry kubectl -n $TEKTON_NS apply -f ./tools/gate/tekton/yaml/triggerbindings/triggerbinding-message.yaml
retry kubectl -n $TEKTON_NS apply -f ./tools/gate/tekton/yaml/eventlisteners/eventlistener.yaml

kubectl -n $TEKTON_NS get svc
kubectl -n $TEKTON_NS get pod
kubectl -n $TEKTON_NS get triggerbinding
kubectl -n $TEKTON_NS get triggertemplate

kubectl -n $TEKTON_NS wait --for=condition=Ready pod --timeout=120s --all

# Install the pipeline
kubectl -n $TEKTON_NS apply -f ./tools/gate/tekton/yaml/example-pipeline.yaml
kubectl -n $TEKTON_NS wait --for=condition=Ready pod --timeout=120s --all

kubectl get po -A

# Trigger the sample github pipeline
SVCIP=$(kubectl -n $TEKTON_NS get svc --no-headers | grep el-listener | awk '{print $3}')
curl -X POST \
  http://$SVCIP:8080 \
  -H 'Content-Type: application/json' \
  -H 'X-Hub-Signature: sha1=2da37dcb9404ff17b714ee7a505c384758ddeb7b' \
  -d '{"repository":{"url": "https://github.com/tektoncd/triggers.git"}}'

# Ensure the run is successful
kubectl -n $TEKTON_NS wait --for=condition=Succeeded pipelineruns --timeout=120s --all

# Check the pipeline runs
kubectl -n $TEKTON_NS get pipelinerun

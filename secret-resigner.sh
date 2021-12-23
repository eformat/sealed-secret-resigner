#!/bin/bash

#set -x
set -e

controller_namespace=
project_list=

# rotate master key
rotate_master() {
    controller_namespace="$1"
    echo "🔨 rotating master key now ..."
    oc -n ${controller_namespace} set env deployment/sealed-secrets SEALED_SECRETS_KEY_CUTOFF_TIME="$(date -R)"
    sleep 3
    oc -n ${controller_namespace} wait pod -l app.kubernetes.io/name=sealed-secrets --for=condition=Ready --timeout=100s
    if [ $? -ne 0 ]; then
        echo "🔴 sealed secret pod not Ready?"
        exit 1;
    fi
}

# reseal secrets
reseal() {
    sealedsecrets="$1" project="$2" controller_namespace="$3"
    for index in ${!sealedsecrets[@]}; do
        echo "🥽🥽🥽 Resigning sealedsecret ${sealedsecrets[index]} in project ${project} with latest master key..."
        oc -n ${project} get sealedsecret ${sealedsecrets[index]} -o json | kubeseal --re-encrypt --controller-namespace ${controller_namespace} --controller-name sealed-secrets -o json | oc apply -f-
    done
}

# find controller namespace
find_controller_ns() {
    if test 1 !=  $(oc api-resources -o name | grep sealedsecrets.bitnami.com | wc -l); then
        echo "🔴 sealed secrets api not found in cluster ?"
        exit 1;
    fi
    controller_namespace=$(oc get pod -l app.kubernetes.io/name=sealed-secrets --all-namespaces -o custom-columns=NAME:.metadata.namespace --no-headers)
}

usage() {
  cat <<EOF 2>&1
usage: $0 [-c <sealed secret controller namespace>] -p <comma separated project list>

rotate master key and update all sealed secrets in the project
    -c      sealed secret controller namesapce (optional - will find controller if no arg given)
    -p      comma separated project list containing sealed secrets to resign
    -h      help
EOF
  exit 1
}

while getopts cp:uh c;
do
    case $c in
        c)
            controller_namespace=$OPTARG
            ;;
        p)
            project_list=$OPTARG
            ;;          
        *)
            usage
            ;;
  esac
done

shift `expr $OPTIND - 1`

rc=0
oc whoami 1,2>/dev/null || rc=$?
if [ "${rc}" -ne 0 ]; then
    echo "🔴 try oc login first?"
    exit 1;
fi

if [ -z "${controller_namespace}" ]; then
    find_controller_ns
    if [ -z "${controller_namespace}" ]; then
        echo "🔴 no sealed secret controller namespace specified (-c) ?"
        usage
    fi
fi

if [ -z "${project_list}" ]; then
    echo "🔴 no project list specified (-p) ?"
    usage
fi

rotate_master "${controller_namespace}"

while IFS=',' read -ra pl; do
    for index in "${!pl[@]}"; do
        project=${pl[index]}
        read -r -a sealedsecrets <<< $(echo -n $(oc -n ${project} get sealedsecret --no-headers -o custom-columns=NAME:.metadata.name))
        if [ -z "$sealedsecrets" ] || [ -z "$project" ]; then
            echo "🔴 could not find any sealedsecrets in project ${project} ?"
            break
        fi
        reseal "${sealedsecrets}" "${project}" "${controller_namespace}"
    done
done <<< "${project_list}"

echo "🟢 Done 🟢"

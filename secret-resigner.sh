#!/bin/bash

#set -x
set -e

controller_namespace=
project_list=
ifs=','

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

# find all namespaces with sealedsecrets
find_secret_ns() {
    project_list=$(echo -n $(oc get sealedsecrets --all-namespaces -o custom-columns=NAME:.metadata.namespace --no-headers | sort | uniq))
    ifs=' '
}

usage() {
  cat <<EOF 2>&1
usage: $0 [-c <sealed secret controller namespace> -p <comma separated project list>]

rotate master key and update all sealed secrets in the project
    -c      sealed secret controller namesapce (optional - will find controller if no arg given)
    -p      comma separated project list containing sealed secrets to resign (optional - will find projects if no arg given)
    -h      help
EOF
  exit 1
}

while getopts c:p:uh c;
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
        echo "🔴 no sealed secret controller namespace found or specified (-c) ?"
        usage
    fi
fi

if [ -z "${project_list}" ]; then
    find_secret_ns
    if [ -z "${project_list}" ]; then    
        echo "🔴 no project list found or specified (-p) ?"
        usage
    fi
fi

rotate_master "${controller_namespace}"

while IFS=${ifs} read -ra pl; do
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

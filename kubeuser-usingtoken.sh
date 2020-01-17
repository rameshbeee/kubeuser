#!/usr/bin/env bash

set -e

if [[ $# == 0 ]]; then
  echo "Usage: $0 SERVICEACCOUNT [kubectl options]"
  exit 1
fi

function _kubectl() {
  kubectl $@ $kub_options
}

serviceaccount="$1"
kub_options="${@:2}"

echo "***** create service account *****"
_kubectl delete sa ${serviceaccount} --ignore-not-found
_kubectl create sa ${serviceaccount}
if ! secret="$(_kubectl get serviceaccount "$serviceaccount" -o 'jsonpath={.secrets[0].name}' 2>/dev/null)"; then
  echo "serviceaccounts \"$serviceaccount\" not found." >&2
  exit 2
fi

if [[ -z "$secret" ]]; then
  echo "serviceaccounts \"$serviceaccount\" doesn't have a serviceaccount token." >&2
  exit 2
fi

echo
echo "***** get cluster details *****"
# context
context="$(_kubectl config current-context)"
cluster="$(_kubectl config view -o "jsonpath={.contexts[?(@.name==\"$context\")].context.cluster}")"
server="$(_kubectl config view -o "jsonpath={.clusters[?(@.name==\"$cluster\")].cluster.server}")"
# token
ca_crt_data="$(_kubectl get secret "$secret" -o "jsonpath={.data.ca\.crt}" | openssl enc -d -base64 -A)"
namespace="$(_kubectl get secret "$secret" -o "jsonpath={.data.namespace}" | openssl enc -d -base64 -A)"
token="$(_kubectl get secret "$secret" -o "jsonpath={.data.token}" | openssl enc -d -base64 -A)"

echo
echo "***** create role & rolebinding *****"
_kubectl delete role ${serviceaccount}-${namespace}-role --ignore-not-found
_kubectl delete rolebinding ${serviceaccount}-${namespace}-rolebinding --ignore-not-found
_kubectl create role ${serviceaccount}-${namespace}-role --verb=get,list,watch,update,create,delete,deletecollection,patch --resource=*  
_kubectl create rolebinding ${serviceaccount}-${namespace}-rolebinding --role=${serviceaccount}-${namespace}-role --serviceaccount=${namespace}:${serviceaccount} 

echo
echo "***** create kubeconfig file *****"
rm -rf ${serviceaccount}.config
kubectl --kubeconfig ${serviceaccount}.config config set-credentials "$serviceaccount" --token="$token" 
ca_crt="$(mktemp)"; echo "$ca_crt_data" > $ca_crt
kubectl  --kubeconfig ${serviceaccount}.config config set-cluster "$cluster" --server="$server" --certificate-authority="$ca_crt" --embed-certs
kubectl  --kubeconfig ${serviceaccount}.config config set-context "$context" --cluster="$cluster" --namespace="$namespace" --user="$serviceaccount" 
kubectl --kubeconfig ${serviceaccount}.config  config use-context "$context" >/dev/null
echo
echo "***** kube config file : ${serviceaccount}.config *****"

# User identifier
set -e

if [[ $# == 0 ]]; then
  echo "***** Usage: $0 USER [kubectl options]"
  exit 1
fi

function _kubectl() {
  kubectl $@ $kube_options
}

USER="$1"
kube_options="${@:2}"


echo "***** create keys/certs and get it approved *****"
key_file="$(mktemp)"
csr_file="$(mktemp)"
openssl genrsa -out "$key_file" 4096
openssl req -new -key "$key_file" -out "$csr_file" -subj "/CN=${USER}/O={USER}"
#openssl req -config ./csr.conf -new -key $USER.key -nodes -out $USER.csr
export BASE64_CSR=$(cat "$csr_file" | base64 | tr -d '\n')
kubectl delete certificatesigningrequests $USER --ignore-not-found
cat csr.yaml | envsubst | kubectl apply -f -
kubectl certificate approve $USER

echo
echo "***** create certs and get it approved *****"
_kubectl delete role ${USER}-role --ignore-not-found
_kubectl delete rolebinding ${USER}-rolebinding --ignore-not-found
_kubectl create role ${USER}-role --verb=get,list,watch,update,create,delete,deletecollection,patch --resource=*
_kubectl create rolebinding ${USER}-rolebinding --role=${USER}-role --user=${USER}

echo
echo "***** Get cluster details *****"
context=$(kubectl config current-context)
cluster="$(kubectl config view -o "jsonpath={.contexts[?(@.name==\"$context\")].context.cluster}")"
server="$(kubectl config view -o "jsonpath={.clusters[?(@.name==\"$cluster\")].cluster.server}")"
ca_crt_data=$(kubectl config view --raw -o "jsonpath={.clusters[?(@.name==\"$context\")].cluster.certificate-authority-data}" | openssl enc -d -base64 -A) 
ca_crt="$(mktemp)"; echo "$ca_crt_data" > $ca_crt

echo
echo "***** Get client cert *****"
client_cert=$(kubectl get csr $USER -o jsonpath='{.status.certificate}' | openssl enc -d -base64 -A)
client_crt="$(mktemp)"; echo "$client_cert" > $client_crt
namespace=$(_kubectl get role ${USER}-role  -o 'jsonpath={.metadata.namespace}')


echo
echo "***** create kubeconfig *****"
rm -rf ${USER}.config
echo $ca_crt $client_crt
kubectl --kubeconfig ${USER}.config config set-credentials $USER --client-certificate="$client_crt" --client-key="$key_file"  --embed-certs=true
kubectl --kubeconfig ${USER}.config config set-cluster "$cluster" --server="$server" --certificate-authority="$ca_crt" --embed-certs 
kubectl --kubeconfig ${USER}.config config set-context "${USER}-${context}" --cluster="$cluster" --namespace="$namespace" --user="$USER" 
kubectl --kubeconfig ${USER}.config config use-context "${USER}-${context}"
echo
echo "***** kube config file : ${USER}.config *****"

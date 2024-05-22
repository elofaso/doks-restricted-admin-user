#!/bin/bash

# Check if all required parameters are provided
if [ $# -ne 3 ]; then
    echo "Usage: $0 <username> <namespace> <cluster-name>"
    exit 1
fi

# Variables
USERNAME="$1"
NAMESPACE="$2"
CLUSTER_NAME="$3"
CONTEXT_NAME="${CLUSTER_NAME}-${USERNAME}"
KUBECONFIG_FILE="${CONTEXT_NAME}-kubeconfig"

# Generate private key and CSR
openssl genrsa -out "${USERNAME}.key" 2048
openssl req -new -key "${USERNAME}.key" -out "${USERNAME}.csr" -subj "/CN=${USERNAME}"

# Create CSR YAML
cat <<EOF > ${USERNAME}-csr.yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USERNAME}-csr
spec:
  request: $(cat ${USERNAME}.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  usages:
    - client auth
EOF

# Submit CSR
kubectl apply -f ${USERNAME}-csr.yaml

# Approve CSR
kubectl certificate approve ${USERNAME}-csr

# Wait for the CSR to be approved and the certificate to be available
for i in {1..10}; do
    CERT=$(kubectl get csr ${USERNAME}-csr -o jsonpath='{.status.certificate}')
    if [ -n "$CERT" ]; then
        break
    fi
    echo "Waiting for certificate to be issued..."
    sleep 1
done

# Check if certificate was issued
if [ -z "$CERT" ]; then
    echo "Error: Certificate was not issued."
    exit 1
fi

# Retrieve Signed Certificate
echo $CERT | base64 --decode > "${USERNAME}.crt"

# Extract cluster info from the current context
CLUSTER_SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name == \"${CLUSTER_NAME}\")].cluster.server}")

# Extract CA from ConfigMap kube-root-ca.crt in kube-public namespace
CLUSTER_CA=$(kubectl get configmap kube-root-ca.crt -n kube-public -o jsonpath="{.data['ca\.crt']}")

# Check if CLUSTER_SERVER and CLUSTER_CA are available
if [ -z "$CLUSTER_SERVER" ] || [ -z "$CLUSTER_CA" ]; then
    echo "Error: Unable to retrieve cluster server or certificate authority data."
    exit 1
fi

# Ensure that CLUSTER_CA is correctly base64 decoded
CLUSTER_CA_PEM=$(echo "${CLUSTER_CA}")

# Create kubeconfig file
cat <<EOF > ${KUBECONFIG_FILE}
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $(echo "${CLUSTER_CA_PEM}" | base64 | tr -d '\n')
    server: ${CLUSTER_SERVER}
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    namespace: ${NAMESPACE}
    user: ${USERNAME}
  name: ${CONTEXT_NAME}
current-context: ${CONTEXT_NAME}
users:
- name: ${USERNAME}
  user:
    client-certificate-data: $(cat ${USERNAME}.crt | base64 | tr -d '\n')
    client-key-data: $(cat ${USERNAME}.key | base64 | tr -d '\n')
EOF

echo "Kubeconfig file '${KUBECONFIG_FILE}' created for user '${USERNAME}' with client certificate."

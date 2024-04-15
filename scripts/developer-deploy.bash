#!/bin/bash

# Set defaults
cluster=<span class="math-inline">\{cluster\:\-"localhost"\}
namespace\=</span>{namespace:-"wac-hospital"}
project_root=<span class="math-inline">\(realpath "</span>{0}/..")
cluster_root="$project_root/clusters/$cluster"

# Check PowerShell version (replaced with exit on non-zero exit code)
if [[ $(ps -v | awk '/^Version\ Major:/ {print $3}') -lt 7 ]]; then
  echo "Error: PowerShell version must be minimum of 7. Please install the latest version."
  exit 1
fi

# Check sops installation (replaced with error message)
if ! command -v sops &> /dev/null; then
  echo "Error: sops CLI must be installed. Use 'sudo apt install sops' (or similar) to install it."
  exit 2
fi

# Check cluster folder existence (replaced with error message)
if [[ ! -d "$cluster_root" ]]; then
  echo "Error: Cluster folder '<span class="math-inline">cluster\_root' does not exist\."
exit 3
fi
banner\=</span>(cat <<EOF
THIS IS A FAST DEPLOYMENT SCRIPT FOR DEVELOPERS!

---

The script shall be running **only on fresh local cluster** **!
After initialization, it **uses gitops** controlled by installed flux cd controller.
To do some local fine tuning get familiar with flux, kustomize, and kubernetes

Verify that your context is coresponding to your local development cluster:

* Your kubectl *context* is **$(kubectl config current-context)**.
* You are installing *cluster* **<span class="math-inline">cluster\*\*\.
\* \*sops\* version is \*\*</span>(sops -v)**.
* You got *private SOPS key* for development setup.

EOF
)

# Display confirmation message
echo "$banner"
read -r -p "Are you sure to continue? (y/n) " confirm

if [[ "$confirm" != "y" ]]; then
  echo "Exiting script due to the user selection."
  exit 1
fi

# Read SOPS AGE key (using read -s for hidden input)
read -s -p "Enter master key of SOPS AGE (for developers): " agekey

# Create namespace
echo "Creating namespace $namespace"
kubectl create namespace "$namespace"

# Create sops-age secret
echo "Creating sops-age private secret in the namespace ${namespace}"
kubectl delete secret sops-age --namespace "$namespace" &>/dev/null
kubectl create secret generic sops-age --namespace "$namespace" --from-literal=age.agekey="$agekey"

# Decrypt and process gitops-repo secret
echo "Creating gitops-repo secret in the namespace ${namespace}"
pat_secret="$cluster_root/secrets/params/repository-pat.env"
if [[ ! -f "$pat_secret" ]]; then
  pat_secret="$cluster_root/../localhost/secrets/params/gitops-repo.env"
  if [[ ! -f "$pat_secret" ]]; then
    echo "Error: gitops-repo secret not found in '$cluster_root/secrets/params/repository-pat.env' or '$cluster_root/../localhost/secrets/params/gitops-repo.env'"
    exit 4
  fi
fi

old_sops_key="$SOPS_AGE_KEY"
export SOPS_AGE_KEY="<span class="math-inline">agekey"
envs\=</span>(sops --decrypt "$pat_secret")
export SOPS_AGE_KEY="$old_sops_key"
unset agekey

if [[ <span class="math-inline">? \-ne 0 \]\]; then
echo "Error\: Failed to decrypt gitops\-repo secret"
exit 5
fi
username\=""
password\=""
while read \-r line; do
key\_value\=\(</span>{line/=/})
  case "<span class="math-inline">\{key\_value\[0\]\}" in
username\) username\="</span>{key_value[1]}";;
    password) password="${key_value[1]}";;
  esac
done <<< "$envs"

kubectl delete secret repository-pat --namespace "$namespace" &>/dev/null
kubectl create secret generic repository-pat --namespace "$namespace" \
  --from-literal=username="$username" \
  --from-literal=password="$password"

unset username password

# Deploy Flux CD (if enabled)
if [[ "$installFlux" == true ]]; then
  echo "Deploying the Flux CD controller"
  kubectl apply -k "$project_root/infrastructure/fluxcd" --wait
  if [[ $? -ne 0 ]]; then
    echo "Failed to deploy Flux CD controller."
    exit 6
  fi
  echo "Flux CD controller deployed"
fi

# Deploy cluster manifests
echo "Deploying the cluster manifests"
kubectl apply -k "$cluster_root" --wait
echo "Bootstrapping process is done, check the status of the GitRepository and Kustomization resource in namespace ${namespace} for reconcilation updates"

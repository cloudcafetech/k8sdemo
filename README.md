# k8sdemo
k8sdemo using killercoda

## Killercoda setup


- K8S tool setup

```
curl -sSLo /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
chmod +x /usr/local/bin/argocd
chmod +x /usr/local/bin/kind

curl -fsSLO https://github.com/kubernetes-sigs/krew/releases/latest/download/krew-linux_amd64.tar.gz
tar zxvf krew-linux_amd64.tar.gz && ./krew-linux_amd64 install krew
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
```

- Kubectl Pluins setup

```
kubectl krew install ctx
kubectl krew install ns
kubectl krew install neat
```

- K8S Cluster using kind

```
HIP=`ip -o -4 addr list enp1s0 | awk '{print $4}' | cut -d/ -f1`

cat <<EOF > kind-kube.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerPort: 19091
  apiServerAddress: $HIP
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 8080
  - containerPort: 30443
    hostPort: 8443
  extraMounts:
  - hostPath: /var/run/docker.sock
    containerPath: /var/run/docker.sock
- role: worker
EOF
kind create cluster --config kind-kube.yaml
```

- Argo setup

```
wget -q https://raw.githubusercontent.com/cloudcafetech/k8sdemo/main/argo.yaml
kubectl create ns argocd
kubectl create -f argo.yaml -n argocd
argopass=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo y | argocd login 172.30.1.2:31080 --username admin --password $argopass
```

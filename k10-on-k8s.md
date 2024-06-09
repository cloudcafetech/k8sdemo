## Kasten K10 Backup & Restore on K8S

<p align="center">
  <img src="https://github.com/cloudcafetech/k8sdemo/blob/main/k10/k10-flow.PNG">
</p>

- Ingress Setup

```
wget https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/main/addon/nginx.yaml
kubectl label node controlplane region=master
sed -i '/ipFamilyPolicy/a externalTrafficPolicy: Local' nginx.yaml
sed -i 's/externalTrafficPolicy/  externalTrafficPolicy/' nginx.yaml
kubectl create -f nginx.yaml
kubectl wait po -l app.kubernetes.io/component=controller --for=condition=Ready --timeout=2m -n ingress-nginx
```

- MinIO Setup

```
wget -q https://raw.githubusercontent.com/cloudcafetech/k8sdemo/main/minio/local/minio.yaml
kubectl create -f minio.yaml
kubectl wait pod/minio-0 --for=condition=Ready --timeout=2m -n minio-store
```

### K10 Setup

- Using Values

```
wget -q https://raw.githubusercontent.com/cloudcafetech/k8sdemo/main/k10/values.yaml
kubectl create ns kasten-io
helm repo add kasten https://charts.kasten.io/
helm install k10 kasten/k10 --namespace=kasten-io -f values.yaml
kubectl wait po -l app.kubernetes.io/managed-by=Helm --for=condition=Ready --timeout=5m -n kasten-io
kubectl get pods --namespace kasten-io
```

- Using helm command

```
kubectl create ns kasten-io
helm repo add kasten https://charts.kasten.io/
helm install k10 kasten/k10 \
--namespace 'kasten-io' \
--create-namespace \
--set "ingress.create=true" \
--set-string "ingress.class=nginx" \
--set-string "ingress.urlPath=/k10" \
--set "prometheus.server.enabled=false" \
--set "auth.tokenAuth.enabled=true" \
--set "siem.logging.cluster.enabled=false" \
--set "grafana.enabled=false"

kubectl wait po -l app.kubernetes.io/managed-by=Helm --for=condition=Ready --timeout=5m -n kasten-io
kubectl get pods --namespace kasten-io
```

- Authentication setup

```
kubectl get secret k10_token-auth -n kasten-io
kubectl get secret k10_token-auth --namespace kasten-io -ojsonpath="{.data.token}" | base64 --decode
kubectl -n kasten-io create token k10-k10 --duration=24h
k10_token=k10-k10-token

kubectl apply -n kasten-io --filename=- <<EOF
apiVersion: v1
kind: Secret
type: kubernetes.io/service-account-token
metadata:
  name: ${k10_token}
  annotations:
    kubernetes.io/service-account.name: "k10-k10"
EOF

echo $(kubectl get secret ${k10_token} -n kasten-io -ojsonpath="{.data.token}" | base64 -d)
```

- MinIO Secret

```
cat <<EOF > minio-cred.yaml
apiVersion: v1
kind: Secret
metadata:
  name: k10-s3-secret
  namespace: kasten-io
type: secrets.kanister.io/aws
data:
  aws_access_key_id: YWRtaW4=
  aws_secret_access_key: YWRtaW4yNjc1
EOF
kubectl create -f minio-cred.yaml
```

- Profile

```
cat <<EOF > minio-profile.yaml
apiVersion: config.kio.kasten.io/v1alpha1
kind: Profile
metadata:
  name: minio-migration
  namespace: kasten-io
spec:
  type: Location
  locationSpec:
    credential:
      secretType: AwsAccessKey
      secret:
        apiVersion: v1
        kind: Secret
        name: k10-s3-secret
        namespace: kasten-io
    type: ObjectStore
    objectStore:
      name: k8s-backup
      objectStoreType: S3
      region: minio
      endpoint: http://minio-svc.minio-store.svc.cluster.local:9000
      skipSSLVerify: true
EOF
kubectl create -f minio-profile.yaml
```

- Policy 

```
cat <<EOF > backup-policy.yaml
apiVersion: config.kio.kasten.io/v1alpha1
kind: Policy
metadata:
  name: backup
  namespace: kasten-io
spec:
  comment: ""
  frequency: "@onDemand"
  #frequency: "@daily"
  paused: false
  actions:
    - action: backup
      backupParameters:
        profile:
          name: minio-profile
          namespace: kasten-io
  retention:
    daily: 7
    weekly: 4
    monthly: 12
    yearly: 7
  selector:
    matchExpressions:
      - key: k10.kasten.io/appNamespace
        operator: In
        values:
          - kasten-io-cluster
  subFrequency: null
EOF
kubectl create -f backup-policy.yaml
```

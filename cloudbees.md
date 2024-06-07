
## Cloubees Setup

- Ingress
  
```
wget https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/main/addon/nginx.yaml
kubectl label node controlplane region=master
sed -i '/ipFamilyPolicy/a externalTrafficPolicy: Local' nginx.yaml
sed -i 's/externalTrafficPolicy/  externalTrafficPolicy/' nginx.yaml
kubectl create -f nginx.yaml
kubectl wait po -l app.kubernetes.io/component=controller --for=condition=Ready --timeout=5m -n ingress-nginx
```

- Values yaml

```
CBHOST=fcc4e4c6-c8ec-44b7-b036-7f41d2af37d0-10-244-7-247-30080.papa.r.killercoda.com
cat <<EOF > values.yaml
Subdomain: false
ingress-nginx:
  Enabled: false
OperationsCenter:
  Enabled: true
  Platform: standard
  # OperationsCenter.HostName -- The hostname used to access Operations Center through the ingress controller.
  HostName: $CBHOST
  License:
    Evaluation:
      Enabled: true
      FirstName: Ashish
      LastName: Thakur
      Email: getashish26@gmail.com
      Company: ABCD
  Name: cjoc
  # OperationsCenter.Protocol -- the protocol used to access CJOC. Possible values are http/https.
  Protocol: http
  # OperationsCenter.Port -- the port used to access CJOC. Defaults to 80/443 depending on Protocol. Can be overridden.
  Port: 80
  #ServiceType: NodePort
  Resources:
    Limits:
      Cpu: .5
      Memory: 2G
    Requests:
      Cpu: .25
      Memory: 1G
  CSRF:
    ProxyCompatibility: true
Persistence:
  StorageClass: local-path
EOF
```
- Deply

```
helm repo add cloudbees https://public-charts.artifacts.cloudbees.com/repository/public/
helm repo update
kubectl create namespace cjoc
kubectl config set-context $(kubectl config current-context) --namespace=cjoc
helm install cloudbees-core cloudbees/cloudbees-core --namespace cjoc -f values.yaml

kubectl wait pod/cjoc-0 --for=condition=Ready --timeout=5m -n cjoc
kubectl exec cjoc-0 --namespace cjoc -- cat /var/jenkins_home/secrets/initialAdminPassword
```



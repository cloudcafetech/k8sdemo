# Istio [Ambient Mesh](https://istio.io/latest/docs/ambient/getting-started/#addtoambient) in K8s

## Setup Istio Ambient Mesh using istioctl tool

```
kubectl get crd | grep gateway

kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
  { kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd/experimental?ref=v0.8.0" | kubectl apply -f -; }

kubectl get crd | grep gateway

curl -sL https://istio.io/downloadIstio | ISTIO_VERSION=1.22.0 sh -
rm /usr/local/bin/istioctl
mv `pwd`/istio-1.22.0/bin/istioctl /usr/local/bin/istioctl

istioctl install --set profile=ambient --set "components.ingressGateways[0].enabled=true" --set "components.ingressGateways[0].name=istio-ingressgateway" --skip-confirmation
```

## Setup Istio Ambient Mesh using helm 

```
kubectl get crd | grep gateway

kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
  { kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd/experimental?ref=v0.8.0" | kubectl apply -f -; }

kubectl get crd | grep gateway

curl -sL https://istio.io/downloadIstio | ISTIO_VERSION=1.22.0 sh -
rm /usr/local/bin/istioctl
mv `pwd`/istio-1.22.0/bin/istioctl /usr/local/bin/istioctl

helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

helm install istio-base istio/base -n istio-system --create-namespace --wait
helm install istio-cni istio/cni -n istio-system --set profile=ambient --wait

helm pull istio/istiod --untar
helm pull istio/ztunnel --untar
helm pull istio/gateway --untar

sed -i "s/2048Mi/256Mi/g" ztunnel/values.yaml
sed -i "s/500m/75m/g" ztunnel/values.yaml

sed -i "s/2048Mi/256Mi/g" istiod/values.yaml
sed -i "s/1024Mi/256Mi/g" istiod/values.yaml
sed -i "s/500m/100m/g" istiod/values.yaml
sed -i "s/2000m/100m/g" istiod/values.yaml

sed -i "s/1024Mi/256Mi/g" gateway/values.yaml
sed -i "s/2000m/100m/g" gateway/values.yaml

helm install istiod istio/istiod -n istio-system --set profile=ambient --wait -f istiod/values.yaml
helm install ztunnel istio/ztunnel -n istio-system --wait -f ztunnel/values.yaml
helm install istio-ingress istio/gateway -n istio-system -f gateway/values.yaml

helm ls -n istio-system
```

### Deploy Prometheus & Kiali

```
wget -q https://raw.githubusercontent.com/istio/istio/release-1.22/samples/addons/prometheus.yaml
wget -q https://raw.githubusercontent.com/istio/istio/release-1.22/samples/addons/kiali.yaml
sed -i "s/1Gi/256Mi/g" kiali.yaml
kubectl apply -f kiali.yaml
kubectl apply -f prometheus.yaml
kubectl patch svc kiali -n istio-system -p '{"spec": {"type": "NodePort"}}'
kubectl patch svc prometheus -n istio-system -p '{"spec": {"type": "NodePort"}}'
kubectl get po -n istio-system
```

### Deploy the sample application

```
kubectl apply -f `pwd`/istio-1.22.0/samples/bookinfo/platform/kube/bookinfo.yaml
kubectl apply -f `pwd`/istio-1.22.0/samples/sleep/sleep.yaml
kubectl apply -f `pwd`/istio-1.22.0/samples/sleep/notsleep.yaml
sleep 10
kubectl get po
```

### Deploy an ingress gateway

```
kubectl apply -f `pwd`/istio-1.22.0/samples/bookinfo/gateway-api/bookinfo-gateway.yaml
kubectl annotate gateway bookinfo-gateway networking.istio.io/service-type=ClusterIP --namespace=default
```

### Set the environment variables for the Kubernetes Gateway:

```
kubectl wait --for=condition=programmed gtw/bookinfo-gateway
export GATEWAY_HOST=bookinfo-gateway-istio.default
export GATEWAY_SERVICE_ACCOUNT=ns/default/sa/bookinfo-gateway-istio
```

### Test application

```
for run in {1..7}; do
 kubectl exec deploy/sleep -- curl -s "http://$GATEWAY_HOST/productpage" | grep -o "<title>.*</title>"
 sleep 2
 kubectl exec deploy/sleep -- curl -s http://productpage:9080/ | grep -o "<title>.*</title>"
 sleep 2
 kubectl exec deploy/notsleep -- curl -s http://productpage:9080/ | grep -o "<title>.*</title>"
 sleep 2
done
```

## Adding application to the ambient mesh

```kubectl label namespace default istio.io/dataplane-mode=ambient```

- Test application after adding application to ambient mesh

```
for run in {1..7}; do
 kubectl exec deploy/sleep -- curl -s "http://$GATEWAY_HOST/productpage" | grep -o "<title>.*</title>"
 sleep 2
 kubectl exec deploy/sleep -- curl -s http://productpage:9080/ | grep -o "<title>.*</title>"
 sleep 2
 kubectl exec deploy/notsleep -- curl -s http://productpage:9080/ | grep -o "<title>.*</title>"
 sleep 2
done
```

Try to view in Kiali

## [Secure](https://istio.io/latest/docs/ambient/getting-started/#secure) application access using Layer 4 authorization policies but not at the Layer 7 level.

- Layer 4 authorization policy

```
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: productpage-viewer
  namespace: default
spec:
  selector:
    matchLabels:
      app: productpage
  action: ALLOW
  rules:
  - from:
    - source:
        principals:
        - cluster.local/ns/default/sa/sleep
        - cluster.local/$GATEWAY_SERVICE_ACCOUNT
EOF
```

- Confirm the above authorization policy is working

```
for run in {1..7}; do
 kubectl exec deploy/sleep -- curl -s "http://$GATEWAY_HOST/productpage" | grep -o "<title>.*</title>"
 sleep 2
 kubectl exec deploy/sleep -- curl -s http://productpage:9080/ | grep -o "<title>.*</title>"
 sleep 2
 kubectl exec deploy/notsleep -- curl -s http://productpage:9080/ | grep -o "<title>.*</title>"
 sleep 2
done
```

#### Note: Above command will give first two ```Simple Bookstore App``` and last one ```command terminated with exit code 56```

## Secure application access using Layer 7 authorization policy

- Deploy a waypoint proxy for default namespace

```istioctl x waypoint apply --enroll-namespace --wait```

- Verify the waypoint proxy & makesure gateway resource with Programmed status True

``kubectl get gtw waypoint```

- Update your AuthorizationPolicy to explicitly allow the sleep service to GET the productpage service, but perform no other operations:

```
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: productpage-viewer
  namespace: default
spec:
  targetRefs:
  - kind: Service
    group: ""
    name: productpage
  action: ALLOW
  rules:
  - from:
    - source:
        principals:
        - cluster.local/ns/default/sa/sleep
    to:
    - operation:
        methods: ["GET"]
EOF
```

- Confirm the new waypoint proxy is enforcing the updated authorization policy

```
for run in {1..7}; do
 kubectl exec deploy/sleep -- curl -s "http://productpage:9080/productpage" -X DELETE
 sleep 2
 kubectl exec deploy/notsleep -- curl -s http://productpage:9080/
 sleep 2
 kubectl exec deploy/sleep -- curl -s http://productpage:9080/ | grep -o "<title>.*</title>"
 sleep 2
done
```

#### Note: above command will give first two ```RBAC: access denied``` and last one ```Simple Bookstore App```

## Control traffic

- Configure traffic routing to send 90% of requests to reviews v1 and 10% to reviews v2:

```kubectl apply -f samples/bookinfo/gateway-api/route-reviews-90-10.yaml```

- Confirm that roughly 10% of the traffic from 100 requests goes to reviews-v2:

```kubectl exec deploy/sleep -- sh -c "for i in \$(seq 1 100); do curl -s http://productpage:9080/productpage | grep reviews-v.-; done"```

## [Uninstall](https://istio.io/latest/docs/ambient/getting-started/#uninstall)

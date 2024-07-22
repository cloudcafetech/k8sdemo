## K8s with Fluent-bit, Loki & Splunk 

- Local splunk setup

```
docker run -d --name splunk --hostname splunk -p 8000:8000 -p 8088:8088 \
  -e "SPLUNK_PASSWORD=admin2675" -e SPLUNK_HEC_TOKEN=abcd1234 \
  -e "SPLUNK_START_ARGS=--accept-license" -it splunk/splunk:7.3
```

- Loki & Fluentbit setup

```
wget -q https://raw.githubusercontent.com/cloudcafetech/k8sdemo/main/minio/local/minio.yaml
wget -q https://raw.githubusercontent.com/cloudcafetech/k8sdemo/main/test-loki.yaml
wget -q https://raw.githubusercontent.com/cloudcafetech/k8sdemo/main/test-grafana.yaml

kubectl create -f minio.yaml
kubectl wait pod/minio-0 --for=condition=Ready --timeout=5m -n minio-store

kubectl create ns logging
kubectl create ns monitoring

kubectl create -f test-loki.yaml -n logging
kubectl create -f test-grafana.yaml -n monitoring

wget -q https://raw.githubusercontent.com/cloudcafetech/k8sdemo/main/test-fb.yaml
kubectl create -f test-fb.yaml -n logging
```

- Test Splunk

```curl -k https://localhost:8088/services/collector/event -H "Authorization: Splunk abcd1234" -d '{"event": "hello world"}'; echo```

- Demo App

```
wget -q https://raw.githubusercontent.com/skynet86/hello-world-k8s/master/hello-world.yaml
kubectl create -f hello-world.yaml
```

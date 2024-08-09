- DB

```
kubectl create ns minio-store
kubectl create ns cert-manager
kubectl create ns confluence
kubectl create ns postgres-operator

git clone https://github.com/CrunchyData/postgres-operator-examples
kubectl apply --server-side -k postgres-operator-examples/kustomize/install/default
kubectl wait po -l app.kubernetes.io/name=pgo --for=condition=Ready --timeout=5m -n postgres-operator

cat <<EOF > postgres-init-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-init
  namespace: confluence
data:
  init.sql: |
    CREATE SCHEMA confluence_db;
    GRANT USAGE ON SCHEMA confluence_db TO confluence;
    GRANT CREATE ON SCHEMA confluence_db TO confluence;
    GRANT ALL ON SCHEMA confluence_db TO confluence;
    GRANT ALL ON ALL TABLES IN SCHEMA confluence_db TO confluence;
    CREATE DATABASE confluence_db WITH ENCODING 'UTF-8' OWNER confluence LC_COLLATE = 'en_US.UTF-8' TEMPLATE template0;
    GRANT CONNECT ON DATABASE confluence_db TO confluence;
EOF

kubectl create -f postgres-init-cm.yaml -n confluence

cat <<EOF > pgc.yaml
apiVersion: postgres-operator.crunchydata.com/v1beta1
kind: PostgresCluster
metadata:
  name: pgatlaciandb
  namespace: confluence
spec:
  #image: registry.developers.crunchydata.com/crunchydata/crunchy-postgres:ubi8-14.6-2
  image: registry.developers.crunchydata.com/crunchydata/crunchy-postgres:ubi8-16.3-1
  #postgresVersion: 14
  postgresVersion: 16
  port: 5432
  instances:
    - name: pgatlaciandb
      replicas: 1
      dataVolumeClaimSpec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi

  backups:
    pgbackrest:
      #image: registry.developers.crunchydata.com/crunchydata/crunchy-pgbackrest:ubi8-2.41-2
      image: registry.developers.crunchydata.com/crunchydata/crunchy-pgbackrest:ubi8-2.51-1
      repos:
      - name: repo1
        volume:
          volumeClaimSpec:
            accessModes:
            - "ReadWriteOnce"
            resources:
              requests:
                storage: 1Gi

  databaseInitSQL:
    key: init.sql
    name: postgres-init

  users:
  - name: confluence
    password:
      type: AlphaNumeric
    options: "SUPERUSER CREATEROLE LOGIN CREATEDB"

  openshift: false
EOF

kubectl config set-context --current --namespace=confluence
kubectl create -f pgc.yaml
kubectl config set-context --current --namespace=confluence
kubectl wait po -l postgres-operator.crunchydata.com/instance-set=pgatlaciandb --for=condition=Ready --timeout=5m -n confluence
```

- Confluence

```
DBPASS=$(kubectl get secrets pgatlaciandb-pguser-confluence -o go-template='{{.data.password | base64decode}}' -n confluence)
kubectl create secret generic confluence-db --from-literal=username='confluence' --from-literal=password="$DBPASS" -n confluence

cat <<EOF > pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    app.kubernetes.io/instance: confluence
    app.kubernetes.io/name: confluence
  name: confluence-shared-home
  namespace: confluence
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: local-path
  volumeMode: Filesystem
EOF
kubectl create -f pvc.yaml

helm repo add atlassian-data-center https://atlassian.github.io/data-center-helm-charts
helm repo update
wget -q https://raw.githubusercontent.com/cloudcafetech/k8sdemo/main/values-confluence.yaml
helm install confluence atlassian-data-center/confluence --namespace confluence --values values-confluence.yaml
sleep 10
kubectl patch svc confluence --type='json' -p '[{"op":"replace","path":"/spec/type","value":"NodePort"}]'
kubectl delete sts confluence-synchrony
kubectl get po -w

kubectl exec -it pod/confluence-0 -- tail -f /var/atlassian/application-data/confluence/logs/atlassian-confluence.log
```

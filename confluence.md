
## Confluence Setup

- MinIO Nginx setup with selfsigned certificate
  
```
wget -q https://raw.githubusercontent.com/cloudcafetech/k8sdemo/main/minio-nginx-selfsigned.sh
chmod 755 minio-nginx-selfsigned.sh
./minio-nginx-selfsigned.sh
cp public.crt repo2-ca.crt
```

- Create NS

```
kubectl create ns cert-manager
kubectl create ns confluence
kubectl create ns postgres-operator
```

- Install Crunchy Postgress Operator

```
git clone https://github.com/CrunchyData/postgres-operator-examples
kubectl apply --server-side -k postgres-operator-examples/kustomize/install/default
kubectl wait po -l app.kubernetes.io/name=pgo --for=condition=Ready --timeout=5m -n postgres-operator
```

- Create Postgress Cluster

```
cat <<EOF > s3.conf
[global]
repo2-s3-key=admin
repo2-s3-key-secret=admin2675
EOF

kubectl create secret generic pgo-multi-repo-creds --from-file=s3.conf  --from-file=repo2-ca.crt -n confluence

cat <<EOF > postgres-init-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-init
  namespace: confluence
data:
  init.sql: |
    CREATE USER confluence PASSWORD 'confluence';
    CREATE SCHEMA confluence_db;
    GRANT USAGE ON SCHEMA confluence_db TO confluence;
    GRANT CREATE ON SCHEMA confluence_db TO confluence;
    GRANT ALL ON SCHEMA confluence_db TO confluence;
    GRANT ALL ON ALL TABLES IN SCHEMA confluence_db TO confluence;
    CREATE DATABASE confluence_db WITH ENCODING 'UTF-8' OWNER confluence LC_COLLATE = 'en_US.UTF-8' TEMPLATE template0;
    GRANT CONNECT ON DATABASE confluence_db TO confluence;
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: pgbackrest-config
  namespace: confluence
data:
  db.conf: |-
    [global]
    compress-level=6
    start-fast=y
    process-max=20
EOF

kubectl create -f postgres-init-cm.yaml -n confluence

cat <<EOF > pgc.yaml
apiVersion: postgres-operator.crunchydata.com/v1beta1
kind: PostgresCluster
metadata:
  name: pgatlaciandb
  namespace: confluence
spec:
  image: registry.developers.crunchydata.com/crunchydata/crunchy-postgres:ubi8-16.3-1
  postgresVersion: 16
  port: 5432
  instances:
    - name: pgatlaciandb
      replicas: 2
      dataVolumeClaimSpec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi
  backups:
    pgbackrest:
      image: registry.developers.crunchydata.com/crunchydata/crunchy-pgbackrest:ubi8-2.51-1
      configuration:
      - secret:
          name: pgo-multi-repo-creds
      - configMap:
          name: pgbackrest-config 
      global:
        repo2-path: /pgbackrest/postgres-operator/pgatlaciandb/repo2
        repo2-retention-full: "30"
        repo2-retention-full-type: time
        repo2-s3-uri-style: path
        repo2-storage-verify-tls: "n"
        repo2-storage-port: "9000"
        repo2-storage-ca-file: /etc/pgbackrest/conf.d/repo2-ca.crt
      manual:
        options:
        - --type=full
        - --log-level-console=info
        repoName: repo2
      repos:
        - name: repo1
          schedules:
            full: "0 1 * * 0"
            incremental: "0 1 * * 1-6"        
          volume:
            volumeClaimSpec:
              accessModes:
                - ReadWriteOnce
              resources:
                requests:
                  storage: 10Gi
        - name: repo2
          schedules:
            full: "0 1 * * 0"
            incremental: "0 1 * * 1-6" 
          s3:
            bucket: "pgbkp"
            endpoint: "minio-api.172.30.1.2.nip.io"
            region: "minio"

  databaseInitSQL:
    key: init.sql
    name: postgres-init

  patroni:
    switchover:
      enabled: true
    dynamicConfiguration:
      postgresql:
        pg_hba:
          - host all all 0.0.0.0/0 md5
        parameters:
          listen_addresses : '*'
          max_locks_per_transaction: 2048
          max_parallel_workers: 8
          max_parallel_workers_per_gather: 2
          max_pred_locks_per_transaction: 2048
          max_worker_processes: 26
          shared_buffers: 2GB
          shared_preload_libraries: pgaudit,timescaledb
          synchronous_commit: "on"
          synchronous_standby_names: '*'
          timescaledb.license: timescale
          timescaledb.max_background_workers: 16
          wal_keep_size: 2048
          wal_level: replica
          work_mem: 100MB

  monitoring:
    pgmonitor:
      exporter:
        image: registry.developers.crunchydata.com/crunchydata/crunchy-postgres-exporter:ubi8-5.3.1-0

  userInterface:
    pgAdmin:
      dataVolumeClaimSpec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 4Gi
      image: registry.developers.crunchydata.com/crunchydata/crunchy-pgadmin4:ubi8-4.30-22     
      replicas: 1

  users:
  - name: research
    options: "SUPERUSER CREATEROLE LOGIN CREATEDB"
  - name: postgres

  openshift: false
EOF

kubectl create -f pgc.yaml
kubectl config set-context --current --namespace=confluence
kubectl get po -w
```

- Deploy Confluence

```
DBPASS=$(kubectl get secrets pgatlaciandb-pguser-postgres -o go-template='{{.data.password | base64decode}}' -n confluence)
kubectl create secret generic confluence-db --from-literal=username='postgres' --from-literal=password="$DBPASS" -n confluence
helm repo add atlassian-data-center https://atlassian.github.io/data-center-helm-charts
helm repo update

wget -q https://raw.githubusercontent.com/cloudcafetech/k8sdemo/main/values-confluence.yaml
helm install confluence atlassian-data-center/confluence --namespace confluence --values values-confluence.yaml

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
kubectl delete -f pvc.yaml
kubectl create -f pvc.yaml
```

- Manual DB Backup

```kubectl annotate -n confluence postgrescluster pgatlaciandb --overwrite postgres-operator.crunchydata.com/pgbackrest-backup="$(date)"```

- Manual DB Restore

```kubectl annotate -n confluence postgrescluster pgatlaciandb --overwrite postgres-operator.crunchydata.com/pgbackrest-restore="$(date)"```



https://docs.aidbox.app/storage-1/backup-and-restore/crunchy-operator-pgbackrest#recovery


```kubectl annotate -n aidboxdb-db  postgrescluster aidboxdb --overwrite \
        postgres-operator.crunchydata.com/pgbackrest-restore="$(date)"



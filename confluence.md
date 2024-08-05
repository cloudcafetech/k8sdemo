
## Confluence Setup

- Create NS

```
kubectl create ns minio-store
kubectl create ns cert-manager
kubectl create ns confluence
kubectl create ns postgres-operator
```

- MinIO & Nginx setup with selfsigned in Docker
  
```
wget -q https://raw.githubusercontent.com/cloudcafetech/k8sdemo/main/minio-nginx-selfsigned.sh
chmod 755 minio-nginx-selfsigned.sh
./minio-nginx-selfsigned.sh
cp public.crt repo2-ca.crt
```

### OR

- MinIO with selfsigned in K8S
  
```
cat <<EOF > openssl.conf
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = IN
ST = WB
L = Kolkata
O = Cafe
OU = Cloud
CN = controlplane

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = minio-svc.minio-store.svc.cluster.local
EOF
openssl req -new -x509 -nodes -days 730 -keyout private.key -out public.crt -config openssl.conf
cp public.crt repo2-ca.crt

wget -q https://raw.githubusercontent.com/cloudcafetech/k8sdemo/main/minio-selfsign.yaml
kubectl create secret generic minio-server-secret --from-file=./public.crt --from-file=./private.key -n minio-store
kubectl create -f minio-selfsign.yaml
kubectl wait pod/minio-0 --for=condition=Ready --timeout=5m -n minio-store

kubectl exec -it minio-0 -n minio-store -- mc config host add minio https://localhost:9000 admin admin2675 --insecure
kubectl exec -it minio-0 -n minio-store -- mc mb minio/pgbkp --insecure
kubectl exec -it minio-0 -n minio-store -- ls -l /data
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
    -- DB SQL for CONFLUENCE
    CREATE SCHEMA confluence_db;
    GRANT USAGE ON SCHEMA confluence_db TO confluence;
    GRANT CREATE ON SCHEMA confluence_db TO confluence;
    GRANT ALL ON SCHEMA confluence_db TO confluence;
    GRANT ALL ON ALL TABLES IN SCHEMA confluence_db TO confluence;
    CREATE DATABASE confluence_db WITH ENCODING 'UTF-8' OWNER confluence LC_COLLATE = 'en_US.UTF-8' TEMPLATE template0;
    GRANT CONNECT ON DATABASE confluence_db TO confluence;
    -- DB SQL for JIRA
    CREATE SCHEMA jira_db;
    GRANT USAGE ON SCHEMA jira_db TO jira;
    GRANT CREATE ON SCHEMA jira_db TO jira;
    GRANT ALL ON SCHEMA jira_db TO jira;
    GRANT ALL ON ALL TABLES IN SCHEMA jira_db TO jira;
    CREATE DATABASE jira_db WITH ENCODING 'UTF-8' OWNER jira LC_COLLATE = 'en_US.UTF-8' TEMPLATE template0;
    GRANT CONNECT ON DATABASE jira_db TO jira;
    -- DB SQL for BITBUCKET
    CREATE SCHEMA bitbucket_db;
    GRANT USAGE ON SCHEMA bitbucket_db TO bitbucket;
    GRANT CREATE ON SCHEMA bitbucket_db TO bitbucket;
    GRANT ALL ON SCHEMA bitbucket_db TO bitbucket;
    GRANT ALL ON ALL TABLES IN SCHEMA bitbucket_db TO bitbucket;
    CREATE DATABASE bitbucket_db WITH ENCODING 'UTF-8' OWNER bitbucket LC_COLLATE = 'en_US.UTF-8' TEMPLATE template0;
    GRANT CONNECT ON DATABASE bitbucket_db TO bitbucket;
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
        repo2-storage-port: "443"
        #repo2-storage-port: "9000"
        repo2-storage-ca-file: /etc/pgbackrest/conf.d/repo2-ca.crt
      manual:
        options:
        - --type=full
        - --log-level-console=info
        repoName: repo2
      repos:
        - name: repo2
          schedules:
            full: "0 1 * * 0"
            incremental: "0 1 * * 1-6" 
          s3:
            bucket: "pgbkp"
            endpoint: "minio-api.172.30.1.2.nip.io"
            #endpoint: "minio-svc.minio-store.svc.cluster.local"
            region: "minio"

  databaseInitSQL:
    key: init.sql
    name: postgres-init

  patroni:
    switchover:
      enabled: true

  monitoring:
    pgmonitor:
      exporter:
        image: registry.developers.crunchydata.com/crunchydata/crunchy-postgres-exporter:ubi8-5.3.1-0

  users:
  - name: confluence
    options: "SUPERUSER CREATEROLE LOGIN CREATEDB"
  - name: jira
    options: "SUPERUSER CREATEROLE LOGIN CREATEDB"
  - name: bitbucket
    options: "SUPERUSER CREATEROLE LOGIN CREATEDB"

  openshift: false
EOF

kubectl create -f pgc.yaml
kubectl config set-context --current --namespace=confluence
wget -q https://raw.githubusercontent.com/cloudcafetech/k8sdemo/main/postgres-client.yaml
kubectl create -f postgres-client.yaml
kubectl patch secret pgatlaciandb-pguser-confluence -p '{"stringData":{"password":"river@123456","verifier":""}}' -n confluence
kubectl patch secret pgatlaciandb-pguser-jira -p '{"stringData":{"password":"pond@123456","verifier":""}}' -n confluence
kubectl patch secret pgatlaciandb-pguser-bitbucket -p '{"stringData":{"password":"ocen@123456","verifier":""}}' -n confluence
sleep 20
kubectl get secrets pgatlaciandb-pguser-confluence -o go-template='{{.data.password | base64decode}}' -n confluence; echo
kubectl wait po postgresql-client --for=condition=Ready --timeout=5m -n confluence
kubectl exec -it postgresql-client -- psql -U confluence -d confluence_db -h pgatlaciandb-ha -p 5432 -c "select * from information_schema.role_table_grants where grantee='confluence';"
kubectl get po -w
```

- Setup PGAdmin

```

cat <<EOF > pgadmin.yaml
apiVersion: postgres-operator.crunchydata.com/v1beta1
kind: PGAdmin
metadata:
  name: pgadmin
  namespace: confluence
spec:
  dataVolumeClaimSpec:
    accessModes:
    - "ReadWriteOnce"
    resources:
      requests:
        storage: 1Gi
  serverGroups:
  - name: supply
    postgresClusterSelector: {}
  users:
  - username: admin@example.com
    role: Administrator
    passwordRef:
      name: pgadmin-password-secret
      key: admin-password
  - username: user@example.com
    role: User
    passwordRef:
      name: pgadmin-password-secret
      key: user-password
EOF

kubectl create secret generic pgadmin-password-secret -n confluence --from-literal=admin-password=admin2675 --from-literal=user-password=user2675
```

- Deploy Confluence

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
kubectl get po -w
```

- Manual DB Backup

```kubectl annotate -n confluence postgrescluster pgatlaciandb --overwrite postgres-operator.crunchydata.com/pgbackrest-backup="$(date)"```

- Manual DB Restore

```kubectl annotate -n confluence postgrescluster pgatlaciandb --overwrite postgres-operator.crunchydata.com/pgbackrest-restore="$(date)"```

- Manual DB Switchover

```kubectl annotate -n confluence postgrescluster pgatlaciandb --overwrite postgres-operator.crunchydata.com/trigger-switchover="$(date)"```


[ReF:Setup](https://docs.aidbox.app/storage-1/ha-aidboxdb#crunchy-operator)

[ReF:Backup](https://docs.aidbox.app/storage-1/backup-and-restore/crunchy-operator-pgbackrest#create-backup)

[ReF:Restore](https://docs.aidbox.app/storage-1/backup-and-restore/crunchy-operator-pgbackrest#recovery)

[ReF:Inspect](https://docs.aidbox.app/storage-1/backup-and-restore/crunchy-operator-pgbackrest#inspect-backup)

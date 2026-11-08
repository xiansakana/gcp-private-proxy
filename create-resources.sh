#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
: "${PROJECT:?Set PROJECT to your GCP project ID}"
: "${ADMIN_SOURCE_RANGES:?Set ADMIN_SOURCE_RANGES to your SSH CIDR allowlist}"
test -s ssh-keys.txt
ZONE=${ZONE:-us-west1-a}
REGION=${REGION:-us-west1}
NAME=private-proxy-us
gcloud services enable compute.googleapis.com --project="$PROJECT" --quiet
gcloud compute networks create private-proxy-net --project="$PROJECT" --subnet-mode=custom --bgp-routing-mode=regional --quiet
gcloud compute networks subnets create private-proxy-us --project="$PROJECT" --network=private-proxy-net --region="$REGION" --range=10.42.0.0/24 --quiet
gcloud compute firewall-rules create private-proxy-admin --project="$PROJECT" --network=private-proxy-net --direction=INGRESS --action=ALLOW --rules=tcp:22 --source-ranges="$ADMIN_SOURCE_RANGES" --target-tags=private-proxy --quiet
gcloud compute firewall-rules create private-proxy-tls --project="$PROJECT" --network=private-proxy-net --direction=INGRESS --action=ALLOW --rules=tcp:443 --source-ranges=0.0.0.0/0 --target-tags=private-proxy --quiet
gcloud compute instances create "$NAME" --project="$PROJECT" --zone="$ZONE" --machine-type=e2-micro --network-interface=network=private-proxy-net,subnet=private-proxy-us,network-tier=STANDARD --image-family=debian-12 --image-project=debian-cloud --boot-disk-size=30GB --boot-disk-type=pd-standard --boot-disk-auto-delete --no-service-account --no-scopes --tags=private-proxy --labels=purpose=private-proxy --metadata=block-project-ssh-keys=TRUE,enable-oslogin=FALSE --metadata-from-file=startup-script=bootstrap.sh,ssh-keys=ssh-keys.txt --shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --quiet
gcloud compute instances describe "$NAME" --project="$PROJECT" --zone="$ZONE" --format='json(name,status,machineType,networkInterfaces,disks)'
echo PRIVATE_PROXY_CREATE_DONE

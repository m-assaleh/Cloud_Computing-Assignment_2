#!/bin/bash

# Hi there!

# Check if the existing SSH key file exists and remove it
if [ -f "$HOME/.ssh/id_rsa" ]; then
  sudo rm -f "$HOME/.ssh/id_rsa"
fi

if [ -f "$HOME/.ssh/id_rsa.pub" ]; then
  sudo rm -f "$HOME/.ssh/id_rsa.pub"
fi

if [ -f "$HOME/.ssh/gcp_id_rsa.pub" ]; then
  sudo rm -f "$HOME/.ssh/gcp_id_rsa.pub"
fi

# Generate a new SSH key pair
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -C "gcp_user" -q -N ""

# Format the new public key and save it to gcp_id_rsa.pub
echo "gcp_user:$(cat $HOME/.ssh/id_rsa.pub | tr -d '\n')" > $HOME/.ssh/gcp_id_rsa.pub
echo "New public key formatted and added to gcp_id_rsa.pub."

# https://cloud.google.com/compute/docs/connect/add-ssh-keys?cloudshell=false#add_ssh_keys_to_project_metadata
# Fetch existing project SSH keys
EXISTING_KEYS=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata[items][ssh-keys])")

# If existing keys are found, append them to gcp_id_rsa.pub
if [ -n "$EXISTING_KEYS" ]; then
  echo "Appending existing keys to gcp_id_rsa.pub."
  echo "$EXISTING_KEYS" >> $HOME/.ssh/gcp_id_rsa.pub
else
  echo "No existing SSH keys found in project metadata."
fi

# Update project metadata with the new list of SSH keys
gcloud compute project-info add-metadata --metadata-from-file=ssh-keys=$HOME/.ssh/gcp_id_rsa.pub
echo "Project metadata updated with new SSH keys."

# Create two additional VPC networks
echo "Creating VPC networks 'cc-network1' and 'cc-network2'..."
gcloud compute networks create cc-network1 --subnet-mode=custom
gcloud compute networks create cc-network2 --subnet-mode=custom

# Create subnet for cc-network1 with a secondary range and subnet for cc-network2
gcloud compute networks subnets create cc-subnet1 \
    --network=cc-network1 \
    --region=europe-west10 \
    --range=10.0.1.0/24 \
    --secondary-range=secondary-cc-subnet1=10.0.3.0/24

gcloud compute networks subnets create cc-subnet2 \
    --network=cc-network2 \
    --region=europe-west10 \
    --range=10.0.2.0/24

# Create a disk from the "ubuntu-2204-lts" image family
echo "Creating a 120GB disk from 'ubuntu-2204-lts' image family..."
gcloud compute disks create nested-virt-disk \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --size=120GB \
    --zone=europe-west10-c

# Create a custom image with nested virtualization license
echo "Creating a custom image that supports nested virtualization..."
gcloud compute images create nested-virt-image \
    --source-disk=nested-virt-disk \
    --source-disk-zone=europe-west10-c \
    --licenses=https://www.googleapis.com/compute/v1/projects/vm-options/global/licenses/enable-vmx

# Add the SSH public key to Google Cloud OS Login
gcloud compute os-login ssh-keys add --key-file=$HOME/.ssh/gcp_id_rsa.pub
gcloud compute os-login ssh-keys add --key-file=$HOME/.ssh/id_rsa.pub

# Start 3 VM instances with nested virtualization enabled
echo "Starting 3 VMs: controller, compute1, compute2..."
for vm_name in controller compute1 compute2; do
    gcloud compute instances create $vm_name \
        --zone=europe-west10-c \
        --machine-type=n2-standard-2 \
        --image=nested-virt-image \
        --tags=cc \
        --enable-nested-virtualization \
        --metadata=ssh-keys="$(cat $HOME/.ssh/gcp_id_rsa.pub)" \
        --network-interface=subnet=cc-subnet1,network=cc-network1 \
        --network-interface=subnet=cc-subnet2,network=cc-network2
done

# Create a firewall rule to allow all TCP, ICMP, UDP traffic and external access
echo "Creating a firewall rule for the VMs with 'cc' tag..."
gcloud compute firewall-rules create allow-cc-traffic \
    --network=cc-network1 \
    --action=ALLOW \
    --rules=TCP,UDP,ICMP \
    --source-ranges=10.0.1.0/24,10.0.3.0/24 \
    --target-tags=cc

gcloud compute firewall-rules create cc-firewall-rule-2 \
  --network=cc-network2 \
  --allow tcp,udp,icmp \
  --source-ranges=10.0.2.0/24 \
  --target-tags=cc

gcloud compute firewall-rules create allow-external-tcp-icmp \
  --network=cc-network1 \
  --allow=tcp,icmp \
  --source-ranges=0.0.0.0/0 \
  --target-tags=cc

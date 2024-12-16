#!/bin/bash

# Hi there!

# Create a new security group named "open-all"
echo "Creating security group 'open-all'..."
openstack security group create open-all

# Add rules to the 'open-all' security group to allow all traffic
echo "Adding rules to the 'open-all' security group..."
openstack security group rule create --protocol tcp --ingress open-all
openstack security group rule create --protocol udp --ingress open-all
openstack security group rule create --protocol icmp --ingress open-all
openstack security group rule create --protocol tcp --egress open-all
openstack security group rule create --protocol udp --egress open-all
openstack security group rule create --protocol icmp --egress open-all

# Create a new key-pair and add it to the SSH agent
echo "Creating a new key-pair..."
openstack keypair create openstack-key > $HOME/.ssh/openstack-key.pem
chmod 400 $HOME/.ssh/openstack-key.pem
eval $(ssh-agent -s)
ssh-add $HOME/.ssh/openstack-key.pem

# Copy the key to Controller VM and add it to the SSH agent
scp -i $HOME/.ssh/id_rsa $HOME/.ssh/openstack-key.pem gcp_user@34.32.65.62:/home/gcp_user/.ssh
# Give permission 400 to it
ssh -i $HOME/.ssh/id_rsa gcp_user@34.32.65.62 << 'EOF'
chmod 400 /home/gcp_user/.ssh/openstack-key.pem
eval $(ssh-agent -s)
ssh-add /home/gcp_user/.ssh/openstack-key.pem
echo "Key added to the SSH agent on the controller VM"
EOF

# Launch a new VM instance OpenStack VM
echo "Starting a new OpenStack VM instance named openstack-vm..."
openstack server create \
  --image ubuntu-16.04 \
  --flavor m1.medium \
  --security-group open-all \
  --key-name openstack-key \
  --network admin-net \
  openstack-vm

# Wait until the VM is in the RUNNING state
echo "Waiting for the VM to reach the RUNNING state..."
while true; do
  STATUS=$(openstack server show openstack-vm -f value -c status)
  if [ "$STATUS" == "ACTIVE" ]; then
    echo "VM openstack-vm is now running."
    break
  else
    echo "Current status: $STATUS. Checking again in 5 seconds..."
    sleep 5
  fi
done

# Assign a floating IP to the OpenStack VM
echo "Assigning a floating IP to the OpenStack VM..."
FLOATING_IP=$(openstack floating ip create -f value -c floating_ip_address external)
openstack server add floating ip openstack-vm $FLOATING_IP



# The Tasks 11 - 17
# ssh -i $HOME/.ssh/id_rsa gcp_user@34.32.65.62 "ping -c 5 $FLOATING_IP"
# scp -i $HOME/.ssh/id_rsa /home/ubuntu/Assignment-2/kolla-ansible/iptables-magic.sh gcp_user@34.32.65.62:/home/gcp_user
# ssh -i $HOME/.ssh/id_rsa gcp_user@34.32.65.62 "sudo bash /home/gcp_user/iptables-magic.sh"
# ssh -i $HOME/.ssh/id_rsa gcp_user@34.32.65.62 "ping -c 5 $FLOATING_IP"
# ssh -i $HOME/.ssh/id_rsa gcp_user@34.32.65.62 << 'EOF'
# eval $(ssh-agent -s)
# ssh-add /home/gcp_user/.ssh/openstack-key.pem
# ssh -i /home/gcp_user/.ssh/openstack-key ubuntu@$FLOATING_IP "echo OpenStack VM is ready"
# ssh -i /home/gcp_user/.ssh/openstack-key ubuntu@$FLOATING_IP "ping -c 5 8.8.8.8"
# ssh -i /home/gcp_user/.ssh/openstack-key ubuntu@$FLOATING_IP "wget -O /home/ubuntu/network_data.json 169.254.169.254/openstack/2018-08-27/network_data.json"
# ssh -i /home/gcp_user/.ssh/openstack-key ubuntu@$FLOATING_IP "cat /home/ubuntu/network_data.json"
# EOF

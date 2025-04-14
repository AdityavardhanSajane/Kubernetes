#!/bin/bash

# Prompt user to check if they are on the master node
echo "Is this the master node? (yes/no)"
read is_master

if [ "$is_master" != "yes" ]; then
    echo "This script must be run from the EC2 instance named 'master'. Exiting..."
    exit 1
fi

echo "Proceeding with Kubernetes Setup Script - Master Node"
echo "----------------------------------------"

# Step 1: Configure /etc/hosts with the current node's IP and hostname
echo "### Step 1: Configure /etc/hosts ###"
echo "Configuring hostname and IP in /etc/hosts for master node..."
hostnamectl set-hostname k8s-master.lab.example.com
hostname -I >> /etc/hosts
hostname >> /etc/hosts
exec bash

# Step 2: Add Kernel Modules (same for master and worker nodes)
echo "### Step 2: Add Kernel Modules ###"
echo "Loading necessary kernel modules for Kubernetes..."
modprobe br_netfilter
modprobe ip_vs
modprobe ip_vs_rr
modprobe ip_vs_wrr
modprobe ip_vs_sh
modprobe overlay

lsmod | egrep 'br_netfilter|ip_vs|ip_vs_rr|ip_vs_sh|ip_vs_wrr|overlay'

cat > /etc/modules-load.d/kubernetes.conf << EOF
br_netfilter
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
overlay
EOF

cat > /etc/sysctl.d/kubernetes.conf << EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sysctl --system

# Step 3: Disable Swap (same for master and worker nodes)
echo "### Step 3: Disable Swap ###"
echo "Disabling swap on all nodes..."
sudo swapoff -a
sed -e '/swap/s/^/#/g' -i /etc/fstab
cat /etc/fstab

# Step 4: Install Containerd and Docker (same for master and worker nodes)
echo "### Step 4: Install Containerd and Docker ###"
echo "Installing container runtime for Kubernetes..."
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf makecache
sudo dnf -y install containerd.io
sudo sh -c "containerd config default > /etc/containerd/config.toml"

# Modify containerd config
echo "Modifying containerd configuration..."
sed -i 's/disabled_plugins = []/disabled_plugins = ["cri"]/' /etc/containerd/config.toml
systemctl enable --now containerd.service

# Step 5: Install Kubernetes Components (same for master and worker nodes)
echo "### Step 5: Install Kubernetes Components ###"
echo "Adding Kubernetes repository and installing kubelet, kubeadm, and kubectl..."
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

dnf makecache
dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet.service

# Step 6: Initialize Master Node (only on master node)
if [ "$is_master" == "yes" ]; then
    echo "### Step 6: Initialize Kubernetes Master Node ###"
    echo "Pulling necessary images and initializing Kubernetes master node..."
    
    # Pull required images
    sudo kubeadm config images pull

    # Initialize Kubernetes with specified CIDR for Pod Network
    sudo kubeadm init --pod-network-cidr=10.244.0.0/16

    # Set up kubeconfig for kubectl access
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    # Install Calico Network Plugin
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml

    curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml

    sed -i 's/cidr: 192\.168\.0\.0\/16/cidr: 10.244.0.0\/16/g' custom-resources.yaml
    kubectl create -f custom-resources.yaml

    # Generate and display the join command
    sudo kubeadm token create --print-join-command
fi

echo "Kubernetes setup completed successfully!"

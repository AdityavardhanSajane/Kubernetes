#!/bin/bash

echo "🔧 Kubernetes Setup Script"
echo "----------------------------------------"

# Ask if it is master node or worker node
read -p "Is this the master node? (yes/no): " is_master

if [[ "$is_master" == "yes" ]]; then
    echo "✅ Running Master Node Setup..."
else
    echo "✅ Running Worker Node Setup..."
fi

# Step 1 - Set hostname and update /etc/hosts
echo "*************************"
echo "Step 1: Setting Hostname and Updating /etc/hosts"
if [[ "$is_master" == "yes" ]]; then
    hostnamectl set-hostname k8s-master.lab.example.com
else
    hostnamectl set-hostname k8s-worker.lab.example.com
fi

hostname -I >> /etc/hosts
hostname >> /etc/hosts

# Step 2 - Load Kernel Modules
echo "*************************"
echo "Step 2: Loading Kernel Modules for Kubernetes"
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

# Step 3 - Disable Swap
echo "*************************"
echo "Step 3: Disabling Swap Memory"
sudo swapoff -a
sed -e '/swap/s/^/#/g' -i /etc/fstab
cat /etc/fstab

# Step 4 - Install Docker and Containerd
echo "*************************"
echo "Step 4: Installing Docker and Containerd"
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf makecache
sudo dnf -y install containerd.io
sudo sh -c "containerd config default > /etc/containerd/config.toml"

# Edit the /etc/containerd/config.toml file and set SystemdCgroup = true
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl enable --now containerd.service
sudo systemctl status containerd.service

# Step 5 - Install Kubernetes
echo "*************************"
echo "Step 5: Installing Kubernetes"
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

# Step 6 (Only for Master Node)
if [[ "$is_master" == "yes" ]]; then
    echo "*************************"
    echo "Step 6: Initializing Kubernetes Cluster (Master Only)"
    sudo kubeadm config images pull
    sudo kubeadm init --pod-network-cidr=10.244.0.0/16

    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml

    curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml

    sed -i 's/cidr: 192\.168\.0\.0\/16/cidr: 10.244.0.0\/16/g' custom-resources.yaml
    kubectl create -f custom-resources.yaml

    sudo kubeadm token create --print-join-command
else
    echo "❌ Skipping Master-Specific Setup (Step 6)"
fi

echo "Script completed successfully!"

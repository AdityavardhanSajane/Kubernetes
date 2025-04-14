#!/bin/bash

echo "🔧 Kubernetes Setup Script"
echo "----------------------------------------"

# Ask if the current machine is the master node
read -p "Is this the master node? (yes/no): " is_master

if [ "$is_master" == "yes" ]; then
    echo "✅ Proceeding with Master Node Setup..."

    # Step 1: Add current node in /etc/hosts (for master)
    hostnamectl set-hostname k8s-master.lab.example.com
    hostname -I >> /etc/hosts
    hostname >> /etc/hosts
    exec bash  # Ensure changes are effective

    # Step 2: Add Kernel Modules (for both master and worker)
    modprobe br_netfilter
    modprobe ip_vs
    modprobe ip_vs_rr
    modprobe ip_vs_wrr
    modprobe ip_vs_sh
    modprobe overlay

    lsmod | egrep 'br_netfilter|ip_vs|ip_vs_rr|ip_vs_sh|ip_vs_wrr|overlay'

    cat > /etc/modules-load.d/kubernetes.conf <<EOF
br_netfilter
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
overlay
EOF

    cat > /etc/sysctl.d/kubernetes.conf <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

    sysctl --system

    # Step 3: Disable swap (for both master and worker)
    sudo swapoff -a
    sed -e '/swap/s/^/#/g' -i /etc/fstab
    cat /etc/fstab

    # Step 4: Install Docker and Containerd (for both master and worker)
    sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo dnf makecache
    sudo dnf -y install containerd.io
    sudo sh -c "containerd config default > /etc/containerd/config.toml"
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
    systemctl enable --now containerd.service
    sudo systemctl status containerd.service
    sudo dnf install kernel-devel

    # Step 5: Install Kubernetes components (for both master and worker)
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

    # Step 6: Master-specific steps
    # Only for master node
    echo "❌ Skipping Step 6 for worker nodes"

    if [ "$is_master" == "yes" ]; then
        echo "✅ Running Master-Specific Steps..."
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
    fi
else
    echo "❌ This script is not configured to run on a non-master node. Skipping master-specific setup."

    # Continue running steps for worker nodes (Steps 1-5)
    echo "✅ Running Worker Node Setup..."

    # Step 1: Add current node in /etc/hosts (for worker)
    hostnamectl set-hostname k8s-worker.lab.example.com
    hostname -I >> /etc/hosts
    hostname >> /etc/hosts
    exec bash  # Ensure changes are effective

    # Step 2: Add Kernel Modules (same for both master and worker)
    modprobe br_netfilter
    modprobe ip_vs
    modprobe ip_vs_rr
    modprobe ip_vs_wrr
    modprobe ip_vs_sh
    modprobe overlay

    lsmod | egrep 'br_netfilter|ip_vs|ip_vs_rr|ip_vs_sh|ip_vs_wrr|overlay'

    cat > /etc/modules-load.d/kubernetes.conf <<EOF
br_netfilter
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
overlay
EOF

    cat > /etc/sysctl.d/kubernetes.conf <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

    sysctl --system

    # Step 3: Disable swap (same for both master and worker)
    sudo swapoff -a
    sed -e '/swap/s/^/#/g' -i /etc/fstab
    cat /etc/fstab

    # Step 4: Install Docker and Containerd (same for both master and worker)
    sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo dnf makecache
    sudo dnf -y install containerd.io
    sudo sh -c "containerd config default > /etc/containerd/config.toml"
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
    systemctl enable --now containerd.service
    sudo systemctl status containerd.service
    sudo dnf install kernel-devel

    # Step 5: Install Kubernetes components (same for both master and worker)
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
fi

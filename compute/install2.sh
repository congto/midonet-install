#!/bin/bash

if [[ $EUID -ne 0 ]]; then
  echo "You must be a root user!" 2>&1
  exit 1
fi

if [ $# -eq 0 ]; then
    echo -e "\nError: IP address of controller/zookeeper-server is required. Aborting...\n\n"
    exit 1
elif [ $# -gt 1 ]; then
    echo -e "\nError: Too many arguments provided. Aborting...\n\n"
    exit 1
fi

ipaddress=$1
nova_metadata_sharedsecret="<shared-secret>"

# Remove openvswitch packages
yum erase -y openstack-neutron-openvswitch openvswitch python-openvswitch

# Remove ML2 plugin if there
yum erase -y openstack-neutron-ml2

# Configure libvirt
sed -i "s/^#user/user/g" /etc/libvirt/qemu.conf
sed -i "s/^#group/group/g" /etc/libvirt/qemu.conf

grep -r "^cgroup_device_acl" /etc/libvirt/qemu.conf
rc=$?

if [ $rc != 0 ]
then
    cat >> /etc/libvirt/qemu.conf << EOF
cgroup_device_acl = [
    "/dev/null", "/dev/full", "/dev/zero",
    "/dev/random", "/dev/urandom",
    "/dev/ptmx", "/dev/kvm", "/dev/kqemu",
    "/dev/rtc","/dev/hpet", "/dev/vfio/vfio",
    "/dev/net/tun"
]
EOF
fi

# Restart the libvirt service
systemctl restart libvirtd.service

# Install nova-rootwrap network filters
yum -y install openstack-nova-network
systemctl disable openstack-nova-network.service

# Restart the Compute service
systemctl restart openstack-nova-compute.service

# Midolman configuration
yum -y install java-1.8.0-openjdk-headless
yum -y install midolman

sed -i "s/^zookeeper_hosts = 127.0.0.1:2181/zookeeper_hosts = $ipaddress:2181/g" /etc/midolman/midolman.conf

mn-conf template-set -h local -t agent-compute-medium

/bin/cp /etc/midolman/midolman-env.sh.compute.medium /etc/midolman/midolman-env.sh

iptables -I INPUT 1 -i metadata -j ACCEPT

systemctl enable midolman.service
systemctl start midolman.service

echo "Compute node configured!!!"

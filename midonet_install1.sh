#!/bin/bash

username=$1
password=$2

yum update
setenforce Permissive

sed -i '/^SELINUX=/c\SELINUX=permissive' /etc/selinux/config

systemctl stop firewalld
systemctl disable firewalld

systemctl stop iptables
systemctl disable iptables

subscription-manager repos --enable=rhel-7-server-rpms-local

subscription-manager repos --enable=rhel-7-server-openstack-7.0-rpms-local

echo > /etc/yum.repos.d/datastax.repo

cat > "/etc/yum.repos.d/datastax.repo" << EOF
# DataStax (Apache Cassandra)
[datastax]
name = DataStax Repo for Apache Cassandra
baseurl = http://rpm.datastax.com/community
enabled = 1
gpgcheck = 1
gpgkey = https://rpm.datastax.com/rpm/repo_key
EOF

echo > /etc/yum.repos.d/midokura.repo

cat > "/etc/yum.repos.d/midokura.repo" << EOF
[mem]
name=MEM
baseurl=http://$username:$password@repo.midokura.com/mem-5/stable/el7/
enabled=1
gpgcheck=1
gpgkey=https://repo.midokura.com/midorepo.key

[mem-openstack-integration]
name=MEM OpenStack Integration
baseurl=http://repo.midokura.com/openstack-kilo/stable/el7/
enabled=1
gpgcheck=1
gpgkey=https://repo.midokura.com/midorepo.key

[mem-misc]
name=MEM 3rd Party Tools and Libraries
baseurl=http://repo.midokura.com/misc/stable/el7/
enabled=1
gpgcheck=1
gpgkey=https://repo.midokura.com/midorepo.key
EOF

yum clean all
yum upgrade

#reboot

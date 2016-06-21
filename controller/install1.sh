#!/bin/bash

# set SELINUX=permissive
sed -i '/^SELINUX=/c\SELINUX=permissive' /etc/selinux/config
 
# Disable suricata
sed -i "s/^* */#* /g" /etc/cron.d/surnfq.cron
 
iptables -F
systemctl stop firewalld
systemctl disable firewalld
 
systemctl stop iptables
systemctl disable iptables
 
cat > /etc/yum.repos.d/datastax.repo << EOF
# DataStax (Apache Cassandra)
[datastax]
name = DataStax Repo for Apache Cassandra
baseurl = http://rpm.datastax.com/community
enabled = 1
gpgcheck = 1
gpgkey = https://rpm.datastax.com/rpm/repo_key
EOF
 
cat > /etc/yum.repos.d/midokura.repo << EOF
[midonet]
name=MidoNet
baseurl=http://builds.midonet.org/midonet-5/stable/el7/
enabled=1
gpgcheck=1
gpgkey=https://builds.midonet.org/midorepo.key
 
[midonet-openstack-integration]
name=MidoNet OpenStack Integration
baseurl=http://builds.midonet.org/openstack-kilo/stable/el7/
enabled=1
gpgcheck=1
gpgkey=https://builds.midonet.org/midorepo.key
 
[midonet-misc]
name=MidoNet 3rd Party Tools and Libraries
baseurl=http://builds.midonet.org/misc/stable/el7/
enabled=1
gpgcheck=1
gpgkey=https://builds.midonet.org/midorepo.key
EOF
 
yum clean all
yum -y upgrade
reboot

#!/bin/bash

#yum install -y openstack-packstack

#packstack --allinone

yum erase -y openstack-neutron-openvswitch openvswitch python-openvswitch
yum erase -y openstack-neutron-ml2

systemctl stop neutron-dhcp-agent
systemctl disable neutron-dhcp-agent
systemctl stop neutron-l3-agent
systemctl disable neutron-l3-agent
systemctl stop neutron-metadata-agent
systemctl disable neutron-metadata-agent

echo "Enter host ip-address followed by [Enter]:"
read ipaddress
echo "Enter password for midonet user followed by [Enter]:"
read midonet_password

neutron_db_pass=$(openstack-config --get /etc/neutron/neutron.conf database connection | awk -F '@' '{print $1}' | awk -F':' '{print $3}')

source keystonerc_admin
openstack service create --name midonet --description "MidoNet API Service" midonet
keystone user-create --name midonet --pass $midonet_password --tenant services
keystone user-role-add --user midonet --role admin --tenant services

yum install -y python-neutron-plugin-midonet

openstack-config --set /etc/neutron/neutron.conf DEFAULT core_plugin midonet.neutron.plugin_v2.MidonetPluginV2
openstack-config --set /etc/neutron/neutron.conf DEFAULT service_plugins lbaas
openstack-config --set /etc/neutron/neutron.conf DEFAULT dhcp_agent_notification False
openstack-config --set /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips True
openstack-config --set /etc/neutron/neutron.conf service_providers service_provider LOADBALANCER:Midonet:midonet.neutron.services.loadbalancer.driver.MidonetLoadbalancerDriver:default

mkdir /etc/neutron/plugins/midonet

echo > /etc/neutron/plugins/midonet/midonet.ini

cat > /etc/neutron/plugins/midonet/midonet.ini << EOF
[DATABASE]
sql_connection = mysql://neutron:$neutron_db_pass@$ipaddress/neutron

[MIDONET]
# MidoNet API URL
midonet_uri = http://$ipaddress:8181/midonet-api
# MidoNet administrative user in Keystone
username = midonet
password = $midonet_password
# MidoNet administrative user's tenant
project_id = services
EOF

# update symlink to point to midonet configuration
ln -sfn /etc/neutron/plugins/midonet/midonet.ini /etc/neutron/plugin.ini

systemctl stop neutron-server
mysql -e 'drop database neutron'
mysql -e 'create database neutron'

neutron-db-manage \
   --config-file /usr/share/neutron/neutron-dist.conf \
   --config-file /etc/neutron/neutron.conf \
   --config-file /etc/neutron/plugin.ini \
   upgrade head

midonet-db-manage upgrade head

systemctl start neutron-server

# Enable load balancing in the Horizon Dashboard
sed -i "s/^    'enable_lb': False/    'enable_lb': True/g" /etc/openstack-dashboard/local_settings

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

systemctl restart libvirtd

# Midonet Installation
yum install -y java-1.7.0-openjdk-headless
yum install -y zookeeper zkdump nmap-ncat

server=$ipaddress":2888:3888"
grep -r "^server.1" /etc/zookeeper/zoo.cfg
rc=$?

if [ $rc != 0 ]
    echo "server.1="$server >> /etc/zookeeper/zoo.cfg
if

mkdir /var/lib/zookeeper/data
chown zookeeper:zookeeper /var/lib/zookeeper/data
echo 1 > /var/lib/zookeeper/data/myid
mkdir -p /usr/java/default/bin/
ln -s /usr/lib/jvm/jre-1.7.0-openjdk/bin/java /usr/java/default/bin/java
systemctl enable zookeeper
systemctl start zookeeper

yum install -y dsc20

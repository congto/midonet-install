#!/bin/bash

if [[ $EUID -ne 0 ]]; then
  echo "You must be a root user!" 2>&1
  exit 1
fi

if [ $# -eq 0 ]; then
    echo -e "\nError: IP address is required. Aborting...\n\n"
    exit 1
elif [ $# -gt 1 ]; then
    echo -e "\nError: Too many arguments provided. Aborting...\n\n"
    exit 1
fi
 
ipaddress=$1
PASSWORD="<SET-PASSWD>"
NEUTRON_DBPASS="<SET-DB-PASS>"
neutron_user="<SET-USER>"
neutron_db="<SET-DB>"
admintoken="<SET-TOKEN>"
adminpass="<SET-ADMIN-PASS>"
hostname="<SET-HOSTNAME>"
 
# Adding midonet user
source /root/keystonerc_admin
openstack service create --name midonet --description "Midonet API Service" midonet
 
keystone user-create --name midonet --pass $PASSWORD --tenant services
keystone user-role-add --user midonet --role admin --tenant services
 
# Network configuration
yum -y install openstack-neutron openstack-utils openstack-selinux python-neutron-plugin-midonet
 
yum erase -y openstack-neutron-openvswitch openvswitch python-openvswitch
yum erase -y openstack-neutron-ml2
 
systemctl stop neutron-dhcp-agent
systemctl disable neutron-dhcp-agent
systemctl stop neutron-l3-agent
systemctl disable neutron-l3-agent
systemctl stop neutron-metadata-agent
systemctl disable neutron-metadata-agent
 
openstack-config --set /etc/neutron/neutron.conf DEFAULT core_plugin midonet.neutron.plugin_v2.MidonetPluginV2
openstack-config --set /etc/neutron/neutron.conf DEFAULT service_plugins lbaas
openstack-config --set /etc/neutron/neutron.conf DEFAULT dhcp_agent_notification False
openstack-config --set /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips True
openstack-config --set /etc/neutron/neutron.conf service_providers service_provider LOADBALANCER:Midonet:midonet.neutron.services.loadbalancer.driver.MidonetLoadbalancerDriver:default
 
# Configure midonet plugin
mkdir /etc/neutron/plugins/midonet
 
echo > /etc/neutron/plugins/midonet/midonet.ini
 
cat > /etc/neutron/plugins/midonet/midonet.ini << EOF
[DATABASE]
sql_connection = mysql://$neutron_user:$NEUTRON_DBPASS@$ipaddress/$neutron_db
 
[MIDONET]
# MidoNet API URL
midonet_uri = http://$ipaddress:8181/midonet-api
# MidoNet administrative user in Keystone
username = midonet
password = $PASSWORD
# MidoNet administrative user's tenant
project_id = services
EOF
 
# update symlink to point to midonet configuration
rm -rf /etc/neutron/plugin.ini
ln -sfn /etc/neutron/plugins/midonet/midonet.ini /etc/neutron/plugin.ini
 
systemctl stop neutron-server
mysql -e 'drop database $neutron_db'
mysql -e 'create database $neutron_db character set utf8'
mysql -e "GRANT ALL PRIVILEGES ON $neutron_db.* TO '$neutron_user'@'localhost' IDENTIFIED BY '$NEUTRON_DBPASS';"
mysql -e "GRANT ALL PRIVILEGES ON $neutron_db.* TO '$neutron_user'@'%' IDENTIFIED BY '$NEUTRON_DBPASS';"
mysql -e "FLUSH PRIVILEGES;"
 
neutron-db-manage \
    --config-file /usr/share/neutron/neutron-dist.conf \
    --config-file /etc/neutron/neutron.conf \
    --config-file /etc/neutron/plugin.ini \
    upgrade head
 
midonet-db-manage upgrade head
 
systemctl start neutron-server
 
sed -i "s/^    'enable_lb': False/    'enable_lb': True/g" /etc/openstack-dashboard/local_settings
 
# Midonet Installation
yum install -y java-1.7.0-openjdk-headless
yum install -y zookeeper zkdump nmap-ncat
 
server=$ipaddress":2888:3888"
grep -r "^server.1" /etc/zookeeper/zoo.cfg
rc=$?
 
if [ $rc != 0 ]; then
    echo "server.1="$server >> /etc/zookeeper/zoo.cfg
fi
 
mkdir /var/lib/zookeeper/data
chown zookeeper:zookeeper /var/lib/zookeeper/data
 
echo 1 > /var/lib/zookeeper/data/myid
 
mkdir -p /usr/java/default/bin/
ln -s /usr/lib/jvm/jre-1.7.0-openjdk/bin/java /usr/java/default/bin/java
 
systemctl enable zookeeper.service
systemctl start zookeeper.service
 
echo "Checking status of zookeeper"
echo stat | nc 127.0.0.1 2181
echo ruok | nc 127.0.0.1 2181
 
read -p "If the above status is not \"imok\", you need to fix it --> Press ^C (Ctrl + C) to exit; press [Enter] to continue."
 
# Cassandra installation
yum -y install java-1.8.0-openjdk-headless
yum -y install dsc22
 
sed -i 's/^          - seeds: "127.0.0.1"/          - seeds: "$ipaddress"/g' /etc/cassandra/conf/cassandra.yaml
sed -i "s/^listen_address: localhost/listen_address: $ipaddress/g" /etc/cassandra/conf/cassandra.yaml
sed -i "s/^rpc_address: localhost/rpc_address: $ipaddress/g" /etc/cassandra/conf/cassandra.yaml
sed -i '/"Starting Cassandra: "/ a \        mkdir -p \/var\/run\/cassandra\n\        chown cassandra:cassandra \/var\/run\/cassandra' /etc/init.d/cassandra
 
systemctl enable cassandra.service
systemctl start cassandra.service
 
echo "checking status of cassandra service:"
nodetool --host 127.0.0.1 status
 
read -p "If the above status of cassandra is not ok, you need to fix it --> Press ^C (Ctrl + C) to exit; press [Enter] to continue."
 
yum -y install midonet-cluster
sed -i "s/^zookeeper_hosts = 127.0.0.1:2181/zookeeper_hosts = $ipaddress:2181/g" /etc/midonet/midonet.conf
 
cat << EOF | mn-conf set -t default
zookeeper {
    zookeeper_hosts = "$ipaddress:2181"
}
 
cassandra {
    servers = "$ipaddress"
}
EOF
 
echo "cassandra.replication_factor : 1" | mn-conf set -t default
 
keytool -import -trustcacerts -keystore /etc/pki/java/cacerts -storepass changeit -noprompt -alias mycert1 -file /etc/pki/ca-trust/source/anchors/rootCA.crt
 
cat << EOF | mn-conf set -t default
cluster.auth {
    provider_class = "org.midonet.cluster.auth.keystone.KeystoneService"
    admin_role = "admin"
    keystone.tenant_name = "admin"
    keystone.admin_token = "$admintoken"
    keystone.host = "$hostname"
    keystone.port = 35357
    keystone.protocol = "https"
    keystone.insecure = true
}
EOF
 
service midonet-cluster start
 
yum -y install python-midonetclient
 
cat > ~/.midonetrc << EOF
[cli]
api_url = http://$ipaddress:8181/midonet-api
username = admin
password = $adminpass
project_id = admin
EOF
 
reboot

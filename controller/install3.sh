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
nova_metadata_sharedsecret="<SHARED-SECRET>"
 
yum -y install openjdk-8-jre-headless
yum -y install midolman
 
sed -i "s/^zookeeper_hosts = 127.0.0.1:2181/zookeeper_hosts = $ipaddress:2181/g" /etc/midolman/midolman.conf
 
mn-conf template-set -h local -t agent-gateway-medium
 
/bin/cp /etc/midolman/midolman-env.sh.gateway.medium /etc/midolman/midolman-env.sh
 
echo "agent.openstack.metadata.nova_metadata_url : \"http://$ipaddress:8775\"" | mn-conf set -t default
echo "agent.openstack.metadata.shared_secret : $nova_metadata_sharedsecret" | mn-conf set -t default
echo "agent.openstack.metadata.enabled : true" | mn-conf set -t default
 
iptables -I INPUT 1 -i metadata -j ACCEPT
service midolman start

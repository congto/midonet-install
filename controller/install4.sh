#!/bin/bash

if [[ $EUID -ne 0 ]]; then
  echo "You must be a root user!" 2>&1
  exit 1
fi

read -p "Make sure you are running this script only once, else it will break things!!! --> Press ^C (Ctrl + C) to exit; press [Enter] to continue."

# host configuration
hostname=""
edge_router_name=""

# floating-ip network
floating_net=""
floating_gateway=""
floating_start=""
floating_end=""

# uplink configuration
uplink_name=""
interface=""
ip=""
uplink_net=""

# interface having internet connectivity
internet_eth=""

# https://docs.midonet.org/docs/latest-en/quick-start-guide/rhel-7_kilo-osp/content/initial_network_configuration.html

source ~/keystonerc_admin
ext_net_id=$(neutron net-create ext-net --router:external | grep " id " | awk -F' ' '{print $4}')
edge_router_id=$(neutron router-create $edge_router_name | grep " id " | awk -F' ' '{print $4}')
pub_subnet_id=$(neutron subnet-create --gateway $floating_gateway --allocation-pool start=$floating_start,end=$floating_end --disable-dhcp $ext_net_id $floating_net | grep " id " | awk -F' ' '{print $4}')
neutron router-interface-add $edge_router_id $pub_subnet_id
uplink_net_id=$(neutron net-create $uplink_name --tenant_id admin --provider:network_type uplink | grep " id " | awk -F' ' '{print $4}')
uplink_subnet_id=$(neutron subnet-create --tenant_id admin --disable-dhcp --name subnetA $uplink_net_id $uplink_net)
port_id=$(neutron port-create $uplink_net_id --binding:host_id $hostname --binding:profile type=dict interface_name=$interface --fixed-ip ip_address=$ip | grep " id " | awk -F' ' '{print $4}')
neutron router-interface-add $edge_router_id port=$port_id

# https://docs.midonet.org/docs/latest/operations-guide/content/static_setup.html

ip link add type veth
ip link set dev veth0 up
ip link set dev veth1 up

brctl addbr uplinkbridge
brctl addif uplinkbridge veth0
ip addr add 172.19.0.1/30 dev uplinkbridge
ip link set dev uplinkbridge up

sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf

edge_router=$(midonet-cli -A -e router list | grep $edge_router_name | awk -F' ' '{print $2}')
port_id=$(midonet-cli -A -e router $edge_router add port address 172.19.0.2 net 172.19.0.0/30)
midonet-cli -A -e router $edge_router add route src 0.0.0.0/0 dst 0.0.0.0/0 type normal port router $edge_router port $port_id gw 172.19.0.1
host_id=$(midonet-cli -A -e host list | grep $hostname | awk -F' ' '{print $2}')
midonet-cli -A -e host $host_id add binding port router $edge_router port $port_id interface veth1

iptables -t nat -I POSTROUTING -o $internet_eth -s $floating_net -j MASQUERADE
iptables -I FORWARD -s $floating_net -j ACCEPT

service iptables save

echo "Done. Enjoy Midonet!!!"

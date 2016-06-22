#!/bin/bash

if [[ $EUID -ne 0 ]]; then
  echo "You must be a root user!" 2>&1
  exit 1
fi

# create tunnel-zone with vxlan
tunnel_id=$(midonet-cli -A -e tunnel-zone create name tz type vxlan)

# provide the ip-address of each host
midonet-cli -A -e list host
read -p "You need to provide private ip-address used by each node for tunneling. Kindly look at the previous output, and based on the UUID and hostname, provide the ip-address. Press [ENTER] to continue..."
midonet-cli -A -e list host | awk -F' ' '{print $2}' | while read -r host; do
    echo "Enter ip address of host with UUID: $host followed by [ENTER]"
    read host_ip
    midonet-cli -A -e tunnel-zone $tunnel_id add member host $host address $host_ip
    echo "Added host $host with ip_address $host_ip to the tunnel-zone $tunnel_id"
done

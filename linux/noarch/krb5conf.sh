#!/usr/bin/env bash
#http://www.cloudera.com/content/cloudera-content/cloudera-docs/CDH4/latest/CDH4-Security-Guide/cdh4sg_topic_3.html
#http://www.cloudera.com/content/cloudera-content/cloudera-docs/CM4Ent/latest/Cloudera-Manager-Managing-Clusters/cmmc_hadoop_security.html

# if [ $# -lt 1 ]; then
    # echo "usage: $0 [REALM i.e. LUNIX.LAN]" 1>&2
    # exit 1
# fi
# http://stackoverflow.com/a/12202793
function promptyn () {
  while true; do
    read -p "$1 " yn
    case ${yn:-$2} in
      [Yy]* ) return 0;;
      [Nn]* ) return 1;;
      * ) echo "Please answer with [y]es or [n]o.";;
    esac
  done
}

#pre-req 

yum install krb5-server krb5-workstation krb5-libs rng-tools -y
# KB/000002527
/etc/init.d/rngd start
chkconfig rngd on
echo "Add EXTRAOPTIONS /etc/sysconfig/rngd"
cat << EOF > /etc/sysconfig/rngd
# Add extra options here
EXTRAOPTIONS="-i -o /dev/random -r /dev/urandom -t 10 -W 2048"
EOF

#REALM=${1^^}
REALM=LUNIX.LAN
FQDN=$(hostname -f)
PASSWRD=Had00p

function kerberos_cmapi() { 
  CLUSTER_NAME=$(curl -u admin:admin http://$(hostname -f):7180/api/v4/clusters/ -s | grep name | cut -d ':' -f 2 | sed 's/.*"\(.*\)"[^"]*$/\1/' | sed 's/ /%20/g')
  HDFS_NAME=$(curl -u admin:admin http://$(hostname -f):7180/api/v4/clusters/${CLUSTER_NAME}/services -s | grep name | grep hdfs | cut -d ':' -f 2 | sed 's/.*"\(.*\)"[^"]*$/\1/')
  ZOOKEEPER_NAME=$(curl -u admin:admin http://$(hostname -f):7180/api/v4/clusters/${CLUSTER_NAME}/services -s | grep name | grep zookeeper | cut -d ':' -f 2 | sed 's/.*"\(.*\)"[^"]*$/\1/')
  HUE_NAME=$(curl -u admin:admin http://$(hostname -f):7180/api/v4/clusters/${CLUSTER_NAME}/services -s | grep name | grep hue | cut -d ':' -f 2 | sed 's/.*"\(.*\)"[^"]*$/\1/')
  HUE_SERVER_NAME=$(curl -u admin:admin http://$(hostname -f):7180/api/v4/clusters/${CLUSTER_NAME}/services/${HUE_NAME}/roles -s | grep name | grep HUE_SERVER | head -1 | cut -d ':' -f 2 | sed 's/.*"\(.*\)"[^"]*$/\1/')
  HUE_HOSTID=$(curl -u admin:admin http://$(hostname -f):7180/api/v4/clusters/${CLUSTER_NAME}/services/${HUE_NAME}/roles -s | grep hostId | head -1 | cut -d ':' -f 2 | sed 's/.*"\(.*\)"[^"]*$/\1/')
  KT_RENEWER_NAME=$(curl -u admin:admin http://$(hostname -f):7180/api/v4/clusters/${CLUSTER_NAME}/services/${HUE_NAME}/roles -s | grep name | grep HUE_SERVER | head -1 | cut -d ':' -f 2 | sed 's/.*"\(.*\)"[^"]*$/\1/' | sed 's/HUE_SERVER/KT_RENEWER/g')
  MAPREDUCE_NAME=$(curl -u admin:admin http://$(hostname -f):7180/api/v4/clusters/${CLUSTER_NAME}/services -s | grep name | grep mapreduce | cut -d ':' -f 2 | sed 's/.*"\(.*\)"[^"]*$/\1/')
  MAPREDUCE_GATEWAY_NAME=$(curl -u admin:admin http://$(hostname -f):7180/api/v4/clusters/${CLUSTER_NAME}/services/${MAPREDUCE_NAME}/roles -s | grep name | grep JOBT | head -1 | cut -d ':' -f 2 | sed 's/.*"\(.*\)"[^"]*$/\1/' | sed 's/mapreduce1-JOBTRACKER/mapreduce1-GATEWAY/g')
  
  curl -X PUT -H 'Content-Type:application/json' -u admin:admin -d \
    "{\"items\" : [ {\"name\" : \"SECURITY_REALM\",\"value\" : \"$REALM\"} ]}" \
    http://$(hostname -f):7180/api/v4/cm/config
  
  curl -X PUT -H 'Content-Type:application/json' -u admin:admin -d '{
    "items" : [ {
      "name" : "hadoop_security_authentication",
      "value" : "kerberos"
    }, {
      "name" : "hadoop_security_authorization",
      "value" : "true"
    } ]
  }' http://$(hostname -f):7180/api/v4/clusters/${CLUSTER_NAME}/services/${HDFS_NAME}/config

  curl -X PUT -H 'Content-Type:application/json' -u admin:admin -d '{
    "items" : [ {
      "name" : "dfs_datanode_http_port",
      "value" : "1006"
    }, {
      "name" : "dfs_datanode_port",
      "value" : "1004"
    }, {
      "name" : "dfs_datanode_data_dir_perm",
      "value" : "700"
    } ]
  }' http://$(hostname -f):7180/api/v4/clusters/${CLUSTER_NAME}/services/${HDFS_NAME}/roleConfigGroups/${HDFS_NAME}-DATANODE-BASE/config

  curl -X PUT -H 'Content-Type:application/json' -u admin:admin -d '{
    "items" : [ {
      "name" : "enableSecurity",
      "value" : "true"
    } ]
  }' http://$(hostname -f):7180/api/v4/clusters/${CLUSTER_NAME}/services/${ZOOKEEPER_NAME}/config

 curl -X POST -H "Content-Type:application/json" -u admin:admin -d "{
   \"items\": [ {
     \"name\" : \"$KT_RENEWER_NAME\",
     \"type\" : \"KT_RENEWER\",
     \"hostRef\" : {
       \"hostId\" : \"$HUE_HOSTID\"
     },
     \"config\" : {
       \"items\" : [ ]
     },
     \"roleConfigGroupRef\" : {
       \"roleConfigGroupName\" : \"$HUE_NAME-KT_RENEWER-BASE\"
     }
   } ] 
 }" http://$(hostname -f):7180/api/v4/clusters/${CLUSTER_NAME}/services/${HUE_NAME}/roles
 
 curl -X POST -H "Content-Type:application/json" -u admin:admin -d "{
   \"items\": [ {
     \"name\" : \"$MAPREDUCE_GATEWAY_NAME\",
     \"type\" : \"GATEWAY\",
     \"hostRef\" : {
       \"hostId\" : \"$HUE_HOSTID\"
     },
     \"config\" : {
       \"items\" : [ ]
     },
     \"roleConfigGroupRef\" : {
       \"roleConfigGroupName\" : \"$MAPREDUCE_NAME-GATEWAY-BASE\"
     }
   } ] 
 }" http://$(hostname -f):7180/api/v4/clusters/${CLUSTER_NAME}/services/${MAPREDUCE_NAME}/roles
 
 # TODO
  # {
    # "name" : "hive1-HIVESERVER2-dae69bb962a2e73f2e045a1375521e7f",
    # "type" : "HIVESERVER2",
    # "hostRef" : {
      # "hostId" : "192-168-88-209.lunix.lan"
    # },
    # "config" : {
      # "items" : [ ]
    # },
    # "roleConfigGroupRef" : {
      # "roleConfigGroupName" : "hive1-HIVESERVER2-BASE"
    # }
  # }, {
    # "name" : "hive1-WEBHCAT-dae69bb962a2e73f2e045a1375521e7f",
    # "type" : "WEBHCAT",
    # "hostRef" : {
      # "hostId" : "192-168-88-209.lunix.lan"
    # },
    # "config" : {
      # "items" : [ {
        # "name" : "hive_webhcat_secret_key",
        # "value" : "9Wm21ORqHlnYL3ppxejfl4f6M2Qzet"
      # } ]
    # },
    # "roleConfigGroupRef" : {
      # "roleConfigGroupName" : "hive1-WEBHCAT-BASE"
    # }
  # } 
  # {
      # "displayName" : "hive1",
      # "roleConfigGroups" : [ {
        # "name" : "hive1-GATEWAY-BASE",
        # "displayName" : "Gateway (Default)",
        # "roleType" : "GATEWAY",
        # "base" : true,
        # "serviceRef" : {
          # "clusterName" : "Cluster 1 - CDH4",
          # "serviceName" : "hive1"
        # },
        # "config" : {
          # "items" : [ {
            # "name" : "hive_client_config_safety_valve",
            # "value" : "<property>\r\n  <name>hive.server2.authentication</name>\r\n  <value>KERBEROS</value>\r\n</property>\r\n"
          # } ]
        # }
      # }
  # }
  # {
  # "displayName" : "hive1",
      # "roleConfigGroups" : [ {
        # "name" : "hive1-GATEWAY-BASE",
        # "displayName" : "Gateway (Default)",
        # "roleType" : "GATEWAY",
        # "base" : true,
        # "serviceRef" : {
          # "clusterName" : "Cluster 1 - CDH4",
          # "serviceName" : "hive1"
        # },
        # "config" : {
          # "items" : [ {
            # "name" : "hive_client_config_safety_valve",
            # "value" : "<property>\r\n  <name>hive.server2.authentication</name>\r\n  <value>KERBEROS</value>\r\n</property>\r\n"
          # } ] } }        
  # }
# curl -X POST -H "Content-Type:application/json" -u admin:admin -d '{
   # "sshPort" : 22,
   # "userName" : "root",
   # "password" : "password",
   # "hostNames" : ["192.168.88.215"]
# }' http://$(hostname -f):7180/api/v6/cm/commands/hostInstall
 

}

(
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
cp /etc/krb5.conf /etc/krb5.conf.backup.$TIMESTAMP
cp /var/kerberos/krb5kdc/kadm5.acl /var/kerberos/krb5kdc/kadm5.acl.backup.$TIMESTAMP
cp /var/kerberos/krb5kdc/kdc.conf /var/kerberos/krb5kdc/kdc.conf.backup.$TIMESTAMP
sed -n 'H;${x;s/  supported_enctypes = .*\n/  max_life = 1d\n  max_renewable_life = 7d\n&/;p;}' /var/kerberos/krb5kdc/kdc.conf.backup.$TIMESTAMP > /var/kerberos/krb5kdc/kdc.conf
sed -n 'H;${x;s/ ticket_lifetime = .*\n/ max_life = 1d\n max_renewable_life = 7d\n&/;p;}' /etc/krb5.conf.backup.$TIMESTAMP > /etc/krb5.conf
sed -i "s/kerberos.example.com/$FQDN/g" /etc/krb5.conf
sed -i "s/example.com/$FQDN/g" /etc/krb5.conf
sed -i "s/EXAMPLE.COM/$REALM/g" /etc/krb5.conf
sed -i "s/EXAMPLE.COM/$REALM/g" /var/kerberos/krb5kdc/kadm5.acl
sed -i "s/EXAMPLE.COM/$REALM/g" /var/kerberos/krb5kdc/kdc.conf
)
 
(
echo "Creating the KDC with password: $PASSWRD"
kdb5_util -P "$PASSWRD" create -s

chkconfig krb5kdc on
chkconfig kadmin on
service krb5kdc start
service kadmin start
sleep 10 

kadmin.local -q "addprinc -pw $PASSWRD root/admin"
kadmin.local -q "addprinc -pw $PASSWRD hdfs@$REALM"
kadmin.local -q "addprinc -pw $PASSWRD mko/admin"
kadmin.local -q "addprinc -pw $PASSWRD mko@$REALM"
kadmin.local -q "addprinc -pw $PASSWRD guest@$REALM"

echo "Generating cloudera-scm/admin principal for Cloudera Manager"
kadmin.local >/dev/null <<EOF
addprinc -randkey cloudera-scm/admin
xst -k cmf.keytab cloudera-scm/admin
EOF
 
echo "cloudera-scm/admin@$REALM" > /etc/cloudera-scm-server/cmf.principal
mv cmf.keytab /etc/cloudera-scm-server/cmf.keytab
chown cloudera-scm:cloudera-scm /etc/cloudera-scm-server/cmf.keytab /etc/cloudera-scm-server/cmf.principal
chmod 0600 /etc/cloudera-scm-server/cmf.keytab /etc/cloudera-scm-server/cmf.principal
dd if=/dev/urandom of=/etc/hadoop/hadoop-http-auth-signature-secret bs=1024 count=1
)

if promptyn "Setup Kerberos in CM via API?"; then
  kerberos_cmapi
fi

echo "Additional Kerberos post-conf"
cat <<EOF
groupadd supergroup -g 10001
useradd mko -G supergroup,hdfs,hadoop,root -u 10002 -d /home/mko -m
sudo -u hdfs hadoop fs -mkdir /user/mko
sudo -u hdfs hadoop fs -chown mko:supergroup /user/mko
mkdir -p /home/hdfs && chown -R hdfs:hdfs /home/hdfs
EOF
# curl -v -u mko:xxxxx --negotiate http://$(hostname -f):50070/dfshealth.jsp
# userdel -f -r mko 
# usermod -a -G root mko


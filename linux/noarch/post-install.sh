#!/usr/bin/env bash
set -x

#start -init
sed -i 's/alias/#alias/g' /root/.bashrc
#echo "set -o vi"    >> /root/.bashrc
echo "alias vi=vim" >> /root/.bashrc

cat << EOF >> /root/.bashrc
# Auto-screen invocation. see: http://taint.org/wk/RemoteLoginAutoScreen
# if we're coming from a remote SSH connection, in an interactive session
# then automatically put us into a screen(1) session.   Only try once
# -- if $STARTED_SCREEN is set, don't try it again, to avoid looping
# if screen fails for some reason.
if [ "\$PS1" != "" -a "\${STARTED_SCREEN:-x}" = x -a "\${SSH_TTY:-x}" != x ]
then
  STARTED_SCREEN=1 ; export STARTED_SCREEN
  [ -d \$HOME/lib/screen-logs ] || mkdir -p \$HOME/lib/screen-logs
  sleep 1
  screen -RR && exit 0
  # normally, execution of this rc script ends here...
  echo "Screen failed! continuing with normal bash startup"
fi
# [end of auto-screen snippet]
EOF

#http://www.cyberciti.biz/faq/unable-to-read-consumer-identity-rhn-yum-warning/
if grep -q -i "Red Hat" /etc/redhat-release; then
  sed -i 's/1/0/g' /etc/yum/pluginconf.d/product-id.conf 
  sed -i 's/1/0/g' /etc/yum/pluginconf.d/subscription-manager.conf
fi
echo "192.168.88.250 archive.cloudera.com" >> /etc/hosts
echo "192.168.88.250 beta.cloudera.com" >> /etc/hosts
mkdir -p /root/CDH
#end -init

echo "* Downloading the latest Cloudera Manager installer ..."
wget -q "http://archive.cloudera.com/cm4/installer/latest/cloudera-manager-installer.bin" -O /root/CDH/cloudera-manager-installer.bin && chmod +x /root/CDH/cloudera-manager-installer.bin
wget -q "https://github.com/mrmichalis/hadoop-cdh/raw/master/linux/noarch/.screenrc" -O /root/.screenrc 

POST_OPTIONS=( dep-download.sh mysql-init.sh vboxadditions.sh orajava-install.sh getip.sh cm-install.sh krb5conf.sh )
for OPT in ${POST_OPTIONS[@]}; do
  wget -q "https://github.com/mrmichalis/hadoop-cdh/raw/master/linux/noarch/${OPT}" -O /root/CDH/${OPT} && chmod +x /root/CDH/${OPT}  
done;

# Make sure udev doesn't block our network
# http://6.ptmc.org/?p=164
echo "* Cleaning up udev rules ..."
rm /etc/udev/rules.d/70-persistent-net.rules
mkdir /etc/udev/rules.d/70-persistent-net.rules
# rm -rf /dev/.udev/
# rm /lib/udev/rules.d/75-persistent-net-generator.rules

#Install vagrant keys. See: https://github.com/mitchellh/vagrant/tree/master/keys
echo "* Installing SSH keys..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh
wget --no-check-certificate 'https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub' -O /root/.ssh/authorized_keys
wget --no-check-certificate 'https://raw.github.com/mitchellh/vagrant/master/keys/vagrant' -O /root/.ssh/id_rsa
wget --no-check-certificate 'https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub' -O /root/.ssh/id_rsa.pub
chmod 600 /root/.ssh/authorized_keys /root/.ssh/id_rsa /root/.ssh/id_rsa.pub
chown -R root /root/.ssh

# Zero out the free space to save space in the final image:
#echo "* Zeroing out unused space ..."
#dd if=/dev/zero of=/EMPTY bs=1M
#rm -f /EMPTY
OS=`uname -p`;
ether=`ifconfig | cut -c 1-8 | sort | uniq -u | grep venet0 | grep -v venet0:`
if [ "$ether" = "" ]; then
        ether=eth0
fi
#ether='ifconfig -a | sed 's/[ \t].*//;/^\(lo\|\)$/d' | grep -v venet0:';
MYIP=`curl -s ifconfig.me`;
MYIP2="s/xxxxxxxxx/$MYIP/g";


# install squid
yum -y install squid
wget -O /etc/squid/squid.conf "https://raw.github.com/ardi85/autoscript/master/squid-centos.conf"
sed -i $MYIP2 /etc/squid/squid.conf;
service squid restart
chkconfig squid on

# info
clear
echo "https://www.facebook.com/ardi85" 
echo "===========================================" 
echo ""  | tee -a log-install.txt
echo "Service"  | tee -a log-install.txt
echo "-------"  | tee -a log-install.txt
echo "Squid    : 8080"  | tee -a log-install.txt
echo ""  | tee -a log-install.txt
echo "==========================================="  

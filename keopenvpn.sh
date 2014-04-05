#!/bin/bash
# OpenVPN road warrior installer for Debian-based distros

# This script will only work on Debian-based systems. It isn't bulletproof but
# it will probably work if you simply want to setup a VPN on your Debian/Ubuntu
# VPS. It has been designed to be as unobtrusive and universal as possible.

if [ $USER != 'root' ]; then
	echo "Sorry, you need to run this as root"
	exit
fi


if [ ! -e /dev/net/tun ]; then
    echo "TUN/TAP is not available"
    exit
fi

# Try to get our IP from the system and fallback to the Internet.
# I do this to make the script compatible with NATed servers (lowendspirit.com)
# and to avoid getting an IPv6.
IP=$(ifconfig | grep 'inet addr:' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | cut -d: -f2 | awk '{ print $1}' | head -1)
if [ "$IP" = "" ]; then
        IP=$(wget -qO- ipv4.icanhazip.com)
fi

if [ -e /etc/openvpn/server.conf ]; then
	while :
	do
	clear
		echo "Looks like OpenVPN is already installed"
		echo "What do you want to do?"
		echo ""
		echo "1) Remove OpenVPN"
		echo "2) Exit"
		echo ""
		read -p "Select an option [1-4]:" option
		case $option in
			1) 
			apt-get remove --purge -y openvpn
			rm -rf /etc/openvpn
			rm -rf /usr/share/doc/openvpn
			sed -i '/--dport 53 -j REDIRECT --to-port 1194/d' /etc/rc.local
			sed -i '/iptables -t nat -A POSTROUTING -s 10.8.0.0/d' /etc/rc.local
			echo ""
			echo "OpenVPN removed!"
			exit
			;;
			2) exit;;
		esac
	done
else
	echo 'Welcome to this quick OpenVPN "road warrior" installer'
	echo "Modifikasi Oleh Abu naifa untuk opreker"
	echo ""
	# OpenVPN setup and first user creation
	echo "I need to ask you a few questions before starting the setup"
	echo "You can leave the default options and just press enter if you are ok with them"
	echo ""
	echo "First I need to know the IPv4 address of the network interface you want OpenVPN"
	echo "listening to."
	read -p "IP address: " -e -i $IP IP
	echo ""
	echo "What port do you want for OpenVPN?"
	read -p "Port: " -e -i 1194 PORT
	echo ""
	echo "Do you want OpenVPN to be available at port 53 too?"
	echo "This can be useful to connect under restrictive networks"
	read -p "Listen at port 53 [y/n]:" -e -i y ALTPORT
	echo ""
	echo "Finally, tell me your name for the client cert"
	echo "Please, use one word only, no special characters"
	read -p "Client name: " -e -i client CLIENT
	echo ""
	echo "Okay, that was all I needed. We are ready to setup your OpenVPN server now"
	read -n1 -r -p "Press any key to continue..."
	apt-get update
	apt-get install openvpn iptables openssl -y
	cp -R /usr/share/doc/openvpn/examples/easy-rsa/ /etc/openvpn
	# easy-rsa isn't available by default for Debian Jessie and newer
	if [ ! -d /etc/openvpn/easy-rsa/2.0/ ]; then
		wget --no-check-certificate -O ~/easy-rsa.tar.gz https://github.com/OpenVPN/easy-rsa/archive/2.2.2.tar.gz
		tar xzf ~/easy-rsa.tar.gz -C ~/
		mkdir -p /etc/openvpn/easy-rsa/2.0/
		cp ~/easy-rsa-2.2.2/easy-rsa/2.0/* /etc/openvpn/easy-rsa/2.0/
		rm -rf ~/easy-rsa-2.2.2
	fi
	cd /etc/openvpn/easy-rsa/2.0/
	# Let's fix one thing first...
	cp -u -p openssl-1.0.0.cnf openssl.cnf
	# Bad NSA - 1024 bits was the default for Debian Wheezy and older
	sed -i 's|export KEY_SIZE=1024|export KEY_SIZE=2048|' /etc/openvpn/easy-rsa/2.0/vars
	# Create the PKI
	. /etc/openvpn/easy-rsa/2.0/vars
	. /etc/openvpn/easy-rsa/2.0/clean-all
	# The following lines are from build-ca. I don't use that script directly
	# because it's interactive and we don't want that. Yes, this could break
	# the installation script if build-ca changes in the future.
	export EASY_RSA="${EASY_RSA:-.}"
	"$EASY_RSA/pkitool" --initca $*
	# Same as the last time, we are going to run build-key-server
	export EASY_RSA="${EASY_RSA:-.}"
	"$EASY_RSA/pkitool" --server server
	# Now the client keys. We need to set KEY_CN or the stupid pkitool will cry
	export KEY_CN="$CLIENT"
	export EASY_RSA="${EASY_RSA:-.}"
	"$EASY_RSA/pkitool" $CLIENT
	# DH params
	. /etc/openvpn/easy-rsa/2.0/build-dh
	# Let's configure the server
	SERVER='
	port 1194
	proto tcp
	dev tun
	tun-mtu 1500
	tun-mtu-extra 32
	mssfix 1450
	ca /etc/openvpn/ca.crt
	cert /etc/openvpn/server.crt
	key /etc/openvpn/server.key
	dh /etc/openvpn/dh2048.pem
	plugin /usr/share/openvpn/plugin/lib/openvpn-auth-pam.so /etc/pam.d/login
	client-cert-not-required
	username-as-common-name
	server 10.8.0.0 255.255.255.0
	ifconfig-pool-persist ipp.txt
	push "redirect-gateway def1"
	push "dhcp-option DNS 8.8.8.8"
	push "dhcp-option DNS 8.8.4.4"
	push "route-method exe"
	push "route-delay 2"
	keepalive 5 30
	cipher AES-128-CBC
	comp-lzo
	persist-key
	persist-tun
	status server-vpn.log
	verb 3'
	
	echo "$SERVER" > /etc/openvpn/server.conf
	#cd /usr/share/doc/openvpn/examples/sample-config-files
	#gunzip -d server.conf.gz
	#cp server.conf /etc/openvpn/
	cd /etc/openvpn/easy-rsa/2.0/keys
	cp ca.crt ca.key dh2048.pem server.crt server.key /etc/openvpn
	#cd /etc/openvpn/
	# Set the server configuration
	#sed -i 's|dh dh1024.pem|dh dh2048.pem|' server.conf
	#sed -i 's|;push "redirect-gateway def1 bypass-dhcp"|push "redirect-gateway def1 bypass-dhcp"|' server.conf
	#sed -i 's|;push "dhcp-option DNS 208.67.222.222"|push "dhcp-option DNS 8.8.8.8"|' server.conf
	#sed -i 's|;push "dhcp-option DNS 208.67.220.220"|push "dhcp-option DNS 8.8.4.4"|' server.conf
	sed -i "s|port 1194|port $PORT|" server.conf
	# Listen at port 53 too if user wants that
	if [ $ALTPORT = 'y' ]; then
		iptables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-port 1194
		sed -i "/# By default this script does nothing./a\iptables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-port 1194" /etc/rc.local
	fi
	# Enable net.ipv4.ip_forward for the system
	sed -i 's|#net.ipv4.ip_forward=1|net.ipv4.ip_forward=1|' /etc/sysctl.conf
	# Avoid an unneeded reboot
	echo 1 > /proc/sys/net/ipv4/ip_forward
	# Set iptables
	iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP
	iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE 
	iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o venet0 -j SNAT --to $IP
	sed -i "/# By default this script does nothing./a\iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP" /etc/rc.local
	# And finally, restart OpenVPN
	/etc/init.d/openvpn restart
	# Let's generate the client config
	mkdir ~/ovpn-$CLIENT
	# Try to detect a NATed connection and ask about it to potential LowEndSpirit
	# users
	EXTERNALIP=$(wget -qO- ipv4.icanhazip.com)
	if [ "$IP" != "$EXTERNALIP" ]; then
		echo ""
		echo "Looks like your server is behind a NAT!"
		echo ""
		echo "If your server is NATed (LowEndSpirit), I need to know the external IP"
		echo "If that's not the case, just ignore this and leave the next field blank"
		read -p "External IP: " -e USEREXTERNALIP
		if [ $USEREXTERNALIP != "" ]; then
			IP=$USEREXTERNALIP
		fi
	fi
	# IP/port set on the default client.conf so we can add further users
	# without asking for them
	#sed -i "s|remote my-server-1 1194|remote $IP $PORT|" /usr/share/doc/openvpn/examples/sample-config-files/client.conf
	#cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf ~/ovpn-$CLIENT/$CLIENT.conf
	
	Client='
	client
	proto tcp
	persist-key
	persist-tun
	dev tun
	pull
	comp-lzo
	ns-cert-type server
	verb 3
	mute 2
	mute-replay-warnings
	auth-user-pass
	redirect-gateway def1
	script-security 2
	route-method exe
	route-delay 2
	remote $IP 1194
	cipher AES-128-CBC
	ca [inline]'
	
	echo "$client" > $CLIENT.conf
	cp /etc/openvpn/easy-rsa/2.0/keys/ca.crt ~/ovpn-$CLIENT
	#cp /etc/openvpn/easy-rsa/2.0/keys/$CLIENT.crt ~/ovpn-$CLIENT
	#cp /etc/openvpn/easy-rsa/2.0/keys/$CLIENT.key ~/ovpn-$CLIENT
	cd ~/ovpn-$CLIENT
	#sed -i "s|cert client.crt|cert $CLIENT.crt|" $CLIENT.conf
	#sed -i "s|key client.key|key $CLIENT.key|" $CLIENT.conf
	#echo "remote-cert-tls server" >> $CLIENT.conf
	
	cp $CLIENT.conf $CLIENT.ovpn
	
	#sed -i "s|ca ca.crt|ca [inline]|" $CLIENT.ovpn
	#sed -i "s|cert $CLIENT.crt|cert [inline]|" $CLIENT.ovpn
	#sed -i "s|key $CLIENT.key|key [inline]|" $CLIENT.ovpn
	#echo -e "keepalive 10 60\n" >> $CLIENT.ovpn
	
	echo "<ca>" >> $CLIENT.ovpn
	cat ca.crt >> $CLIENT.ovpn
	echo -e "</ca>\n" >> $CLIENT.ovpn
	
	#echo "<cert>" >> $CLIENT.ovpn
	#sed -n "/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p" $CLIENT.crt >> $CLIENT.ovpn
	#echo -e "</cert>\n" >> $CLIENT.ovpn
	
	#echo "<key>" >> $CLIENT.ovpn
	#cat $CLIENT.key >> $CLIENT.ovpn
	#echo -e "</key>\n" >> $CLIENT.ovpn

	#tar -czf ../ovpn-$CLIENT.tar.gz $CLIENT.conf ca.crt $CLIENT.crt $CLIENT.key $CLIENT.ovpn
	tar -czf ../ovpn-$CLIENT.tar.gz $CLIENT.conf ca.crt $CLIENT.ovpn
	cd ~/
	rm -rf ovpn-$CLIENT
	echo ""
	echo "Finished!"
	echo ""
	echo "Your client config is available at ~/ovpn-$CLIENT.tar.gz"
fi

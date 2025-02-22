#!/bin/bash

set -e

# Cập nhật hệ thống và cài đặt các gói cần thiết
apt update -y && apt install -y openvpn easy-rsa unzip

# Tạo thư mục chứa CA và chuyển vào đó
make-cadir ~/openvpn-ca
cd ~/openvpn-ca

# Cấu hình các thông số CA
echo "set_var EASYRSA_ALGO "ec"
set_var EASYRSA_DIGEST "sha512"" > vars

# Xây dựng CA
./easyrsa init-pki
./easyrsa build-ca nopass <<< "\n"

# Tạo khóa riêng và chứng chỉ cho máy chủ
./easyrsa gen-req server nopass
./easyrsa sign-req server server <<< "yes\n"

# Tạo Diffie-Hellman key
./easyrsa gen-dh
openvpn --genkey --secret ta.key

# Sao chép các tệp quan trọng vào thư mục OpenVPN
cp pki/ca.crt pki/issued/server.crt pki/private/server.key pki/dh.pem ta.key /etc/openvpn/

# Tạo file cấu hình server OpenVPN
cat > /etc/openvpn/server.conf << EOF
port 1194
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-auth ta.key 0
server 10.8.0.0 255.255.255.0
keepalive 10 120
cipher AES-256-CBC
auth SHA256
persist-key
persist-tun
status openvpn-status.log
verb 3
EOF

# Bật chế độ forwarding trên hệ thống
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Cấu hình tường lửa để cho phép VPN hoạt động
ufw allow 1194/udp
ufw disable && ufw enable

# Bật dịch vụ OpenVPN
systemctl start openvpn@server
systemctl enable openvpn@server

# Tạo client
CLIENT_NAME="client1"
./easyrsa gen-req $CLIENT_NAME nopass
./easyrsa sign-req client $CLIENT_NAME <<< "yes\n"

# Tạo file cấu hình OpenVPN cho client
mkdir -p ~/client-configs
cp pki/ca.crt pki/issued/$CLIENT_NAME.crt pki/private/$CLIENT_NAME.key ta.key ~/client-configs/

cat > ~/client-configs/$CLIENT_NAME.ovpn << EOF
client
dev tun
proto udp
remote $(curl -s ifconfig.me) 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
cipher AES-256-CBC
tls-auth ta.key 1
ca ca.crt
cert $CLIENT_NAME.crt
key $CLIENT_NAME.key
EOF

# Cung cấp đường dẫn tải file cấu hình
mkdir -p /var/www/html/openvpn
cp ~/client-configs/$CLIENT_NAME.ovpn /var/www/html/openvpn/

# Cài đặt web server đơn giản để tải file
apt install -y apache2
systemctl enable apache2
systemctl start apache2

# Hiển thị link tải file cấu hình
IP=$(curl -s ifconfig.me)
echo "Hoàn thành! Tải file OpenVPN client từ: http://$IP/openvpn/$CLIENT_NAME.ovpn"

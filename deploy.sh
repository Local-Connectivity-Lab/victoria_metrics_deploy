set -e
set -u
set -o pipefail
set -x

if [ -z "${VM_VIEWER_PASSWORD:-}" ]; then
  echo "Error: Environment variable VM_VIEWER_PASSWORD is not set"
  exit 1
fi


#mkdir -p victoria_metrics
cd victoria_metrics


#vm_exe=victoria-metrics-linux-amd64-v1.122.0.tar.gz
#wget https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v1.122.0/$vm_exe

#tar xf $vm_exe
#rm $vm_exe


#vmutils_exe=vmutils-linux-amd64-v1.122.0.tar.gz
#wget https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v1.122.0/$vmutils_exe

#tar xf $vmutils_exe
#rm $vmutils_exe vmagent-prod vmalert-prod vmalert-tool-prod vmbackup-prod vmctl-prod vmrestore-prod

cat << EOF > ./auth.yml
users:
  - username: user
    password: $VM_VIEWER_PASSWORD
    url_prefix: "http://localhost:8428/"
EOF



vm="victoria_metrics"
vm_log_path="/var/log/$vm.log"
cat << EOF > /etc/systemd/system/$vm.service
[Unit]
Description=victoria metrics
After=network.target

[Service]
Type=simple
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/victoria-metrics-prod
Restart=always
RestartSec=10
StandardOutput=append:$vm_log_path
StandardError=append:$vm_log_path

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable $vm
systemctl start $vm



vmauth="vmauth"
vmauth_log_path="/var/log/$vmauth.log"
cat << EOF > /etc/systemd/system/$vmauth.service
[Unit]
Description=victoria metrics
After=network.target

[Service]
Type=simple
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/vmauth-prod -auth.config=./auth.yml
Restart=always
RestartSec=10
StandardOutput=append:$vmauth_log_path
StandardError=append:$vmauth_log_path

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable $vmauth
systemctl start $vmauth



base64_credentials=$(echo -n user:$VM_VIEWER_PASSWORD | base64)

#curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh

parser_file_path=/etc/fluent-bit/vm_parser.conf
cat << EOF > $parser_file_path
[PARSER]
    Name       vm_parser
    Format     regex
    Regex      ^(?<time>[^ ]+)\s+(?<level>[^ ]+)\s+(?<source>[^ ]+)\s+(?<msg>.+)$
    Time_Key   time
    Time_Format %Y-%m-%dT%H:%M:%S.%LZ
EOF

cat << EOF > /etc/fluent-bit/fluent-bit.conf
[SERVICE]
    Parsers_File $parser_file_path

[INPUT]
    Name          tail
    Path          $vm_log_path
    Tag           vm_log
    Parser        vm_parser

[FILTER]
    Name        record_modifier
    Match       vm_log
    Record      stream yol.log

[OUTPUT]
    Name        http
    Match       vm_log
    Host        172.16.20.23
    Port        8427  # vmauth port
    URI         /insert/jsonline?_stream_fields=stream&_msg_field=msg&_time_field=time
    Format      json_lines
    Compress    gzip
    Header      Authorization Basic $base64_credentials
EOF

systemctl restart fluent-bit


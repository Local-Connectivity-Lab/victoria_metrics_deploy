if [ -z "${VM_VIEWER_PASSWORD:-}" ]; then
  echo "Error: Environment variable VM_VIEWER_PASSWORD is not set"
  exit 1
fi

base64_credentials=$(echo -n user:$VM_VIEWER_PASSWORD | base64)

curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh

parser_file_path=/etc/fluent-bit/vm-parser.conf
cat << EOF > $parser_file_path
[PARSER]
    Name       vm_parser
    Format     regex
    Regex      ^\[(?<time>.+)\] (?<msg>.+)$
    Time_Key   time
    Time_Format %d/%b/%Y:%H:%M:%S.%L %z
EOF

cat << EOF > /etc/fluent-bit/fluent-bit.conf
[SERVICE]
    Parsers_File $parser_file_path

[INPUT]
    Name          tail
    Path          /var/log/dirsrv/slapd-CLOUD-SEATTLECOMMUNITYNETWORK-ORG/access
    Tag           fipa_log
    Parser        vm_parser

[OUTPUT]
    Name        http
    Match       fipa_log
    Host        172.16.20.23
    Port        8427  # vmauth port
    URI         /insert/jsonline?_msg_field=msg&_time_field=time
    Format      json_lines
    Compress    gzip
    Header      Authorization Basic $base64_credentials
EOF

systemctl restart fluent-bit

#!/bin/sh

apk --update --no-cache add ca-certificates
wget -O /usr/local/share/ca-certificates/root.crt https://gitee.com/mitchx7/FoundryDeploy/raw/master/assets/redir_ca.crt
update-ca-certificates
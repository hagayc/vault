#!/bin/bash -x
### Vault CLI can be obtained here: https://releases.hashicorp.com/vault/  (For Linux distro we need: vault_${VAULT_VERSION}_linux_amd64.zip)
set -e
 
### Skelaton ###
mkdir -p ~/vault/{policies,config,data,logs}
cd
 
### Dockerfile ###
cat > vault/Dockerfile <<'EOF'
# base image
FROM alpine:3.7
# set vault version according to your downloaded version (!)
ENV VAULT_VERSION 1.4.1
# create a new directory
RUN mkdir /vault
# download dependencies
RUN apk --no-cache add \
      bash \
      ca-certificates \
      wget
# download and set up vault
RUN wget --quiet --output-document=/tmp/vault.zip \
    https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip &&\
    unzip /tmp/vault.zip -d /vault &&\
    rm -f /tmp/vault.zip &&\
    chmod +x /vault
# update PATH
ENV PATH="PATH=$PATH:$PWD/vault"
# add the config file
COPY ./config/vault-config.json /vault/config/vault-config.json
# expose port 8200
EXPOSE 8200
# run vault
ENTRYPOINT ["vault"]
EOF
 
### docker-compose.yml ###
cat > docker-compose.yml <<'EOF'
version: '2.0'
services:
  vault:
    build:
      context: ./vault
      dockerfile: Dockerfile
    image: vault:1.4.1
    container_name: vault_1.4.1
    ports:
      - 8200:8200
    volumes:
      - ./vault/config:/vault/config
      - ./vault/policies:/vault/policies
      - ./vault/data:/vault/data
      - ./vault/logs:/vault/logs
    environment:
      - VAULT_ADDR=http://127.0.0.1:8200
    command: server -config=/vault/config/vault-config.json
    cap_add:
      - IPC_LOCK
EOF
 
### vault-config.json  ###
cat > vault/config/vault-config.json <<'EOF'
{
  "backend": {
    "file": {
      "path": "vault/data"
    }
  },
  "listener": {
    "tcp":{
      "address": "0.0.0.0:8200",
      "tls_disable": 1
    }
  },
  "ui": true
}
EOF
 
### Can We Build It?! - Yes, We Can! ###
docker-compose up -d --build 
 
### Initilaization ###
docker exec -it vault_1.4.1 vault operator init > ~/vault/config/genesis
 
### Unsealing ###
for i in 1 2 3 ;
    do docker exec -it vault_1.4.1 bash -c \
    "vault operator unseal $(cat vault/config/genesis | grep $i: | awk '{print $4}' | sed -e 's/\x1b\[[0-9;]*m//g')" ;
done
 
### Verification ###
STATUS=$(docker exec -it vault_1.4.1 vault status | grep Sealed | awk '{print $2}'| tr -dc '[:print:]')
if [ "$STATUS" == "false" ] ; then
   echo "###########################"
   echo "## Vault is now unsealed ##"
   echo "###########################"
else
   echo "Failed to unseal vault. Exiting" && exit 1
fi



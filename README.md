# vault-circleci-integration

A simple repo to demonstrate Vault and CircleCI Integration

The main goal of this project is to have a set of Terraform, vagrant or shell scritps to deploy Vault with CircleCI plugin installed and enabled.

This project used the work from Marc Boudreau (look at special thanks) and his Vault CircleCI Plugin.

## Disclaimer
This repo is not intented to support production deployment. The main objective is to demonstrate how CircleCI and Vault work together.

## Pre Requisites

You should :
- Have some knowledge on Vault and CircleCI
- Have access to CircleCI with a proper account
- be able to create a Token on CircleCI : https://circleci.com/docs/2.0/managing-api-tokens/
- have a project defined in CircleCI
- have a pipeline 
- have access to vault on port 8200 from CircleCI


## How to use it 

- Clone the repo on your laptop :

```
$ git clone https://github.com/nehrman/vault-circle-ci-integration
```

- Look at the variables :

```
##################################################################################################
# How to use this script :                                                                       #
#   ./vault_single_server.sh vault_version vault _enterprise os_type os vault_backend license    #
#                                                                                                #
# Vault_version :                                                                                #
#   - OSS : 1.1.1                                                                                #
#   - Ent: 1.1.1+ent (Default)                                                                   #
# os_type :                                                                                      #
#   - linux_386 or linux_amd64 (Default)                                                         #
#   - linux_arm or linux_arm64                                                                   #
#   - freebsd_386 or freebsd_amd64                                                               #
#   - darwin_386 or darwin_amd64                                                                 #
#   - solaris_amd64                                                                              #
# os :                                                                                           #
#   - redhat                                                                                     #
#   - centos                                                                                     #
#   - ubuntu (Default)                                                                           #
#   - solaris                                                                                    #
#   - freebsd                                                                                    #
#   - macosx                                                                                     #
# Backend :                                                                                      #
#   - consul : Use Consul as backend. (Local agent is required on Vault Server)                  #
#   - file : Use local disk as data directory for Vault Server (Test purpose)                    # 
# license : Enter the license number that Hashicorp provides                                     #
##################################################################################################
```

Example : 
```
vaultadmin@vault01:~$ ./vault_single_server-circleci.sh 1.1.2 false
```
It will download, install and configure Vault version 1.1.2 Open Source automatically on ubuntu OS.

CircleCI Pipeline Code that can connect to vault and read a secret in the K/V : 

```
test:
    docker:
      - image: IMAGE_NAME
        environment:
          VAULT_ADDR: http://VAULT_IP_OR_FQDN:8200/v1
    steps:
      - checkout
      - run:
          name: Login to Vault and register token 
          command: |
              tee payload.json <<EOF
              {
                "project": "$CIRCLE_PROJECT_REPONAME",
                "vcs_revision": "$CIRCLE_SHA1",
                "build_num": "$CIRCLE_BUILD_NUM"
              }
              EOF
              VAULT_TOKEN="$(curl -v -d "@./payload.json" "${VAULT_ADDR}/auth/circleci-auth-plugin/login" | jq -r '.auth.client_token')"
              echo "VAULT_TOKEN=$VAULT_TOKEN" >> $BASH_ENV
              cat $BASH_ENV 
      - run:
          name: Read the secret from Vault
          command: "curl -H \"X-Vault-Token: ${VAULT_TOKEN}\" \"${VAULT_ADDR}/kv/circleci\" | jq '.'"
```

## What's next ?

I would like to add :
- Terraform code for any Cloud (GCP, Azure and AWS)
- Vagrant box
- Possibility to deploy more than 1 Vault

## Special thanks

* **Marc Boudreau** - For his amazing work creating vault CircleCI Auth plugin [Github](https://github.com/marcboudreau)

## Authors

* **Nicolas Ehrman** - *Initial work* - [Hashicorp](https://www.hashicorp.com)


#!/bin/bash

set -e

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

# Variables

vault_version=${1:-'1.1.1'}
vault_enterprise=${2:-true}
vault_path="/etc/vault.d"
os_type=${3:-'linux_amd64'}
os=${4:-'ubuntu'}
cluster_name="dc1"
nic=$(ip route show default | awk '/default/ {print $5}')
node_name=$(hostnamectl --static)
vault_backend=${5:-'file'}
license=${6}

# Prepare the environment and download Vault

echo "# Ensure all pre requisites are met"
echo "-----------------------------------"

if [ ${os} == redhat ]
    then 
        sudo yum install -y jq unzip net-tools bzip2
    elif  [ ${os} == ubuntu ]
        then
            sudo apt-get install -y jq unzip net-tools bzip2
    else 
        brew install -y jq unzip bzip2
fi


echo "# Downloading Vault Binaries from Hashicorp Repository"
echo "-------------------------------------------------------------"

if [ ${vault_enterprise} == true ]
    then 
        curl -o ~/vault-${vault_version}+ent.zip  https://s3-us-west-2.amazonaws.com/hc-enterprise-binaries/vault/ent/${vault_version}/vault-enterprise_${vault_version}%2Bent_${os_type}.zip
    else 
        curl -o ~/vault-${vault_version}.zip  https://releases.hashicorp.com/vault/${vault_version}/vault_${vault_version}_${os_type}.zip
fi

echo "# Unzip Vault package, apply appropriate permissions and move binary to correct directory"
echo "------------------------------------------------------------------------------------------"

if [ ${vault_enterprise} == true ]
    then 
        unzip ~/vault-${vault_version}+ent.zip
    else 
        unzip ~/vault-${vault_version}.zip
fi

sudo chown root:root vault
if [ ${os} == "redhat" ]
    then 
        sudo mv vault /usr/local/sbin
    else 
        sudo mv vault /usr/local/bin
fi

if [ ${vault_enterprise} == true ]
    then 
        sudo rm ~/vault-${vault_version}+ent.zip
    else 
        sudo rm ~/vault-${vault_version}.zip
fi

echo "# Create Vault User and Directories"
echo "-----------------------------------------"

# Create Vault User 
sudo useradd -r -d ${vault_path} -s /bin/false vault

# Configuration and Plugins Dirs
sudo mkdir -p ${vault_path}
sudo mkdir -p ${vault_path}/plugins
sudo chown -R vault:vault ${vault_path}
# Logs Dir
sudo mkdir -p /var/log/vault
# Run Dir
sudo mkdir -p /var/run/vault
sudo chown -R vault:vault /var/run/vault

# Data Dir
sudo mkdir -p /var/vault
sudo chown -R vault:vault /var/vault

echo "# Give Vault the ability to use mlock syscall"
echo "---------------------------------------------"

sudo setcap cap_ipc_lock=+ep $(readlink -f $(which vault))

# Retrieve IP Address on Default Nic on the Host

if [ ${os} == redhat ]
    then
        ip_address=$(ifconfig ${nic} | awk '/inet /{print substr($2, 1)}')
    else
        ip_address=$(ifconfig ${nic} | awk '/inet addr/{print substr($2, 6)}')
fi

echo "# Create Vault Server Configuration File"
echo "----------------------------------"

# Generate VaultConfiguration file
if [ ${vault_backend} == "consul" ]
    then
        sudo tee /etc/vault.d/config.hcl > /dev/null <<EOF
cluster_name = "${cluster_name}"

storage "consul" {
    path = "vault/"
}

listener "tcp" {
    address = "0.0.0.0:8200",
    tls_disable = true   
}
plugin_directory = "${vault_path}/plugins"
api_addr = "${ip_address}:8200"
cluster_address = "${ip_address}:8201"
ui = true 
EOF
        sudo chown -R vault:vault ${vault_path}
    else 
        sudo tee /etc/vault.d/config.hcl > /dev/null <<EOF
cluster_name = "${cluster_name}"

storage "file" {
    path = "/var/vault"
}

listener "tcp" {
    address = "0.0.0.0:8200",   
    tls_disable = true
}
plugin_directory = "${vault_path}/plugins"
api_addr = "http://${ip_address}:8200"
cluster_address = "http://${ip_address}:8201"
ui = true 
EOF
        sudo chown -R vault:vault ${vault_path}
fi

# Register where Vault is deployed 
vault_bin_path=$(which vault)

# Generate Vault Service configuration file
echo "# Create Vault Service Configuration with systemd"
echo "--------------------------------------------------"

sudo tee /etc/systemd/system/vault.service > /dev/null <<EOF
[Unit]
Description="HashiCorp Vault - A Centralized Secrets Management Solution"
Documentation=https://www.vaultproject.io/
Requires=network-online.target
After=network-online.target

[Service]
User=vault
Group=vault
PIDFile=/var/run/vault/vault.pid
PermissionsStartOnly=true
ExecStart=${vault_bin_path} server -config=/etc/vault.d/config.hcl
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
KillSignal=SIGTERM
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "# Enabling and Starting Vault Service"
echo "--------------------------------------"

sudo systemctl enable vault
sudo systemctl start vault

echo "# Wait until Vault Server is responsive"
echo "----------------------------------------"

while [ -z "$(curl -s http://${ip_address}:8200/ui)" ]; do
  sleep 3
done

echo "# Initialize Vault Server"
echo "-------------------------"
export VAULT_ADDR="http://${ip_address}:8200"
vault operator init -recovery-threshold=1 -key-shares=1 -key-threshold=1 > /tmp/vault_init.txt
vault_unseal_key=$(cat /tmp/vault_init.txt | grep "Unseal Key 1" | sed 's/Unseal Key 1: //')
vault_root_token=$(cat /tmp/vault_init.txt | grep "Initial Root Token" | sed 's/Initial Root Token: //')

echo "# Unseal Vault Server"
echo "---------------------"

vault operator unseal "${vault_unseal_key}"

echo "# Adding Vault License to Server if Enterprise Version"
echo "---------------------------------"

export VAULT_ADDR="http://${ip_address}:8200"
export VAULT_TOKEN="${vault_root_token}"

if [ ${vault_enterprise} == true ]
    then 
        vault write sys/license text="${license}"
fi

echo "# Wait until Vault Server is responsive"
echo "----------------------------------------"

while [ -z "$(curl -s http://${ip_address}:8200/v1/sys/health)" ]; do
  sleep 3
done

echo "# Download CircleCI Vault Plugin from Github"
echo "--------------------------------------------"

if [ ${os_type} == linux_amd64 ]
    then 
        wget -O ~/vault-circleci-auth-plugin.bz2 https://github.com/marcboudreau/vault-circleci-auth-plugin/releases/download/0.1.4/linux-amd64-vault-circleci-auth-plugin.bz2
    elif [ ${os_type} == darwin_amd64 ]
        then
            wget -O ~/vault-circleci-auth-plugin.bz2 https://github.com/marcboudreau/vault-circleci-auth-plugin/releases/download/0.1.4/darwin-amd64-vault-circleci-auth-plugin.bz2
    else
        echo "Your OS is not managed by the plugin"
fi

echo "# Decompress Plugin and move it in the right folder"
echo "---------------------------------------------------"

if [ ${os_type} != darwin_amd64 ]
    then 
        bzip2 -df ~/vault-circleci-auth-plugin.bz2
        sudo mv vault-circleci-auth-plugin ${vault_path}/plugins/
        sudo chown -R vault:vault ${vault_path}/plugins/
        sudo chmod +x ${vault_path}/plugins/vault-circleci-auth-plugin
        sudo setcap cap_ipc_lock=+ep ${vault_path}/plugins/vault-circleci-auth-plugin
else 
        bzip2 -df ~/vault-circleci-auth-plugin.bz2
        sudo mv vault-circleci-auth-plugin /private${vault_path}/plugins/
        sudo chown -R vault:vault /private${vault_path}/plugins/
        sudo chmod +x /private${vault_path}/plugins/vault-circleci-auth-plugin
        sudo setcap cap_ipc_lock=+ep /private${vault_path}/plugins/vault-circleci-auth-plugin
fi

echo "# Register Vault CircleCI Auth Plugin"
echo "-------------------------------------"

if [ ${os_type} != darwin_amd64 ]
    then 
        sha256=$(shasum -a 256 "${vault_path}"/plugins/vault-circleci-auth-plugin | awk '{print $1}')
    else 
        sha256=$(shasum -a 256 private"${vault_path}"/plugins/vault-circleci-auth-plugin | awk '{print $1}')
fi

vault plugin register -sha256=${sha256} auth vault-circleci-auth-plugin

echo "# Enable Vault CircleCI Auth Plugin"
echo "-------------------------------------"

vault auth enable -path=vault-circleci-auth-plugin -plugin-name=vault-circleci-auth-plugin plugin

echo ""
echo "-------------------"
echo "# What to do next ?"
echo "-------------------"
echo ""
echo "Configure the CircleCI Vault plugin :"
echo "vault write auth/vault-circleci-auth-plugin/config \\"
echo    "base_url=\"https://circleci.com/api/v1.1/\" \\"
echo    "circleci_token=\"circleci_token\" \\"
echo    "owner=\"nehrman\" \\"
echo    "vcs_type=\"github\" \\"
echo    "ttl=\"10m\" \\"
echo    "max_ttl=\"30m\" \\"
echo ""
echo "Attach an existing policy to a project"
echo "vault write auth/vault-circleci-auth-plugin/map/project_name policy_name"
echo ""
echo "Now, you're all set and can test to authenticate via CircleCI"

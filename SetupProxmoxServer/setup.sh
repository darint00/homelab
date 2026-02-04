#!/bin/bash

function checkRC(){
  rc=$1
  msg=$2
  if (( $rc )) 
  then
    echo "FAILED: $msg"
    exit 1
  else
     echo "SUCCESS: $msg"
  fi
}

HOSTNAME=`hostname`

########################################################## 
### [1] setup darint userid
########################################################## 

USERNAME="darint"
PASSWORD="changeme123"   # optional (or remove for interactive)
SUDO_FILE="/etc/sudoers.d/$USERNAME"

# Create user (no password prompt)
# Done in itital Instructions.md
#useradd -m -s /bin/bash "$USERNAME"
#echo "$USERNAME:$PASSWORD" | chpasswd

usermod -aG sudo "$USERNAME"
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "$SUDO_FILE"
chmod 440 "$SUDO_FILE"



########################################################## 
### [2] Setup GITREPOS 
########################################################## 

### mkdir for mach-setup
mkdir -p ~/darint/GITREPOS
  checkRC  $? "mkdir -p ~/darint/GITREPOS"
GITREPOS=~/darint/GITREPOS


########################################################## 
### [3] Setup bashrc.bashrc 
########################################################## 
found=`grep bashrc.bashrc ~/.bashrc | wc -l`
if [[ "$found" == "0" ]]; then
  echo ". $GITREPOS/homelab/bashrc.bashrc" >> ~/.bashrc
fi  
  checkRC  $? "Add bash.rc to .bashrc"



########################################################## 
### [4] Install k8s 
########################################################## 
cd $GITREPOS
git clone git@github.com:darint00/K8S.git  k8s
  checkRC $? "git clone git@github.com:darint00/K8S.git  k8s"



########################################################## 
### [5] Install Terraform 
########################################################## 
apt update 
apt install -y gnupg software-properties-common wget unzip

# Add HashiCorp GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg



# Add HashiCorp repo
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list




# Install Terraform
apt update
apt install terraform -y


########################################################## 
### [6] Install Ansible 
########################################################## 
apt update
apt install -y software-properties-common
add-apt-repository --yes --update ppa:ansible/ansible
apt update
apt install -y ansible










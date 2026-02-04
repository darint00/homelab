######
###### Manual Steps (as root)
######

1.  ### Install Proxmox 9.1
    - Installs server.  It installs as root

2.  ### Install Sudo
    apt update
    apt install root -y     # (on server)

3.  ### Create darint user (sudo nopw)
    useradd -m -s /bin/bash "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd

4. ### Setup git  
    sudo apt install git -y     # (on server)
    git config --global user.name darint00
    git config --global user.email darint00@gmail.com

    ssh-keygen             # (on server) 
    cp ~darint/.ssh/id_rsa.pub  # (new sshkey on github)
    LOGIN to github.com    # (darint00)

5. ### Clone This Repo
    git clone git@github.com:darint00/homelab

6. ### Copy sshkey to laptop (passwordless)  
    ssh-copy-id darint@dc1



######
######  Automated Steps
######

[NOTE] - Copy setup.sh to machine and run as root.  Should do the following

1.  Install sudo

2.  Create darint userid




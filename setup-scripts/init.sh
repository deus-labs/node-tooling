#!/bin/sh

[ "$(id -u)" -ne 0 ] && echo "You must be root to run this script!" && exit 1

SCRIPT_PATH="$(dirname -- "$0")"
set -a && . "$SCRIPT_PATH"/${1:-.env} && set +a

install_packages() {
    apt-get update
    apt-get -y upgrade
    apt-get -y install curl git gcc make wget build-essential git-lfs jq
    ### for snapshot
    # apt-get install liblz4-tool aria2 -y
}

setup_swap() {
    if [ ! -f /swapfile ]; then
        fallocate -l 4G /swapfile
        dd if=/dev/zero of=/swapfile bs=1024 count=4194304
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile swap swap defaults 0 0' >>/etc/fstab
    fi
    sysctl vm.swappiness=1
    echo 'vm.swappiness=1' >>/etc/sysctl.conf
}

init() {
    install_packages
    setup_swap

    # git lfs install --skip-repo
    cp /usr/share/doc/util-linux/examples/securetty /etc/securetty

    cat > /etc/security/limits.d/nofile.conf <<EOF
*                soft    nofile          65535
*                hard    nofile          65535
EOF
}

create_user() {
    USERNAME=$1
    mkdir -p /home/"$USERNAME"/.ssh
    cp ~/.ssh/authorized_keys /home/"$USERNAME"/.ssh/authorized_keys
    useradd -s /bin/bash -d /home/"$USERNAME" "$USERNAME"
    usermod -aG sudo "$USERNAME"

    chmod 700 /home/"$USERNAME"/.ssh
    chmod 644 /home/"$USERNAME"/.ssh/authorized_keys

    cp ~/.profile ~/.bashrc /home/"$USERNAME"/
    sed -i 's/\xterm-color\b/&|*-256color/' /home/"$USERNAME"/.bashrc

    chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"/
}

install_go() {
    go_version=$(curl -s "https://golang.org/dl/?mode=json" | jq -r '.[].files[].version' | uniq | grep -v -E 'go[0-9\.]+(beta|rc)' | sed -e 's/go//' | sort -V | tail -1)
    go_tar="go$go_version.linux-amd64.tar.gz"
    cd /tmp
    wget "https://golang.org/dl/$go_tar"
    tar -xvf "$go_tar"
    rm -rf /usr/local/go
    mv go /usr/local
    rm "$go_tar"

    sed -i '/^PATH=/ s/"$/:\/usr\/local\/go\/bin"/' /etc/environment
    echo "GOROOT=/usr/local/go" >>/etc/environment

    cat >>/home/"$VALIDATOR_USER"/.profile <<'EOF'
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export GO111MODULE=on
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
EOF
    . /home/"$VALIDATOR_USER"/.profile
}

init
create_user "$VALIDATOR_USER"
install_go
su "$VALIDATOR_USER" -c "$SCRIPT_PATH"/install-juno2.sh
create_user "$MONITOR_USER"
"$SCRIPT_PATH"/install-monitoring "$MONITOR_USER"

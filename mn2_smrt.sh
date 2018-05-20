#!/bin/bash

TMP_FOLDER=$(mktemp -d)
CONFIG_FILE='smrt.conf'
BINARY_FILE="/usr/local/bin/smrtd"
CROP_REPO="https://github.com/smrt-crypto/smrt.git"
COIN_TGZ='https://github.com/zoldur/Smrt/releases/download/v1.1.0.5/smrt.tar.gz'

CONFIGFOLDER='/root/.smrt'
COIN_DAEMON='smrtd'
COIN_CLI='smrt-cli'
COIN_PATH='/usr/local/bin/'
COIN_ZIP=$(echo $COIN_TGZ | awk -F'/' '{print $NF}')
COIN_NAME='Smrt'
COIN_PORT=52312
RPC_PORT=52307



RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'


function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}Failed to compile $@. Please investigate.${NC}"
  exit 1
fi
}


function checks() {
if [[ $(lsb_release -d) != *16.04* ]]; then
  echo -e "${RED}You are not running Ubuntu 16.04. Installation is cancelled.${NC}"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}"
   exit 1
fi

if [ -n "$(pidof smrtd)" ]; then
  echo -e "${GREEN}\c"
  read -e -p "smrtd is already running. Do you want to add another MN? [Y/N]" NEW_CROP
  echo -e "{NC}"
  clear
else
  NEW_CROP="new"
fi
}

function prepare_system() {

echo -e "Prepare the system to install Cropcoin master node."
apt-get update >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade >/dev/null 2>&1
apt install -y software-properties-common >/dev/null 2>&1
echo -e "${GREEN}Adding bitcoin PPA repository"
apt-add-repository -y ppa:bitcoin/bitcoin >/dev/null 2>&1
echo -e "Installing required packages, it may take some time to finish.${NC}"
apt-get update >/dev/null 2>&1
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" make software-properties-common \
build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev libboost-program-options-dev \
libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git wget pwgen curl libdb4.8-dev bsdmainutils \
libdb4.8++-dev libminiupnpc-dev libgmp3-dev ufw pwgen
clear
if [ "$?" -gt "0" ];
  then
    echo -e "${RED}Not all required packages were installed properly. Try to install them manually by running the following commands:${NC}\n"
    echo "apt-get update"
    echo "apt -y install software-properties-common"
    echo "apt-add-repository -y ppa:bitcoin/bitcoin"
    echo "apt-get update"
    echo "apt install -y make build-essential libtool software-properties-common autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev \
libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git pwgen curl libdb4.8-dev \
bsdmainutils libdb4.8++-dev libminiupnpc-dev libgmp3-dev ufw"
 exit 1
fi

clear
echo -e "Checking if swap space is needed."
PHYMEM=$(free -g|awk '/^Mem:/{print $2}')
SWAP=$(swapon -s)
if [[ "$PHYMEM" -lt "2" && -z "$SWAP" ]];
  then
    echo -e "${GREEN}Server is running with less than 2G of RAM, creating 2G swap file.${NC}"
    dd if=/dev/zero of=/swapfile bs=1024 count=2M
    chmod 600 /swapfile
    mkswap /swapfile
    swapon -a /swapfile
else
  echo -e "${GREEN}The server running with at least 2G of RAM, or SWAP exists.${NC}"
fi
clear
}


function download_node() {
  echo -e "Prepare to download $COIN_NAME binaries"
  cd $TMP_FOLDER
  wget -q $COIN_TGZ
  tar xvzf $COIN_ZIP -C $COIN_PATH >/dev/null 2>&1
  compile_error
  chmod +x $COIN_PATH$COIN_DAEMON $COIN_PATH$COIN_CLI
  cd - >/dev/null 2>&1
  rm -r $TMP_FOLDER >/dev/null 2>&1
  clear
}



function deploy_binaries() {
  cd $TMP
  wget -q $COIN_TGZ >/dev/null 2>&1
  tar xvzf $COIN_ZIP -C $COIN_PATH >/dev/null 2>&1
  chmod +x smrtd >/dev/null 2>&1
  cp smrtd /usr/local/bin/ >/dev/null 2>&1
}





function ask_permission() {
 echo -e "${RED}I trust zoldur and want to use binaries compiled on his server.${NC}."
 echo -e "Please type ${RED}YES${NC} if you want to use precompiled binaries, or type anything else to compile them on your server"
 read -e ZOLDUR
}


function enable_firewall() {
  echo -e "Installing and setting up firewall to allow incomning access on port ${GREEN}$CROPCOINPORT${NC}"
  ufw allow $COIN_PORT/tcp comment "Cropcoin MN port" >/dev/null
  ufw allow $RPC_PORT/tcp comment "Cropcoin RPC port" >/dev/null
  ufw allow ssh >/dev/null 2>&1
  ufw limit ssh/tcp >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  echo "y" | ufw enable >/dev/null 2>&1
}

function systemd_cropcoin() {
  cat << EOF > /etc/systemd/system/$CROPCOINUSER.service
[Unit]
Description=Cropcoin service
After=network.target
[Service]
Type=forking
User=$CROPCOINUSER
Group=$CROPCOINUSER
WorkingDirectory=$CROPCOINHOME
ExecStart=$COIN_PATH$COIN_DAEMON -daemon -conf=$CROPCOINFOLDER/$CONFIG_FILE -datadir=$CROPCOINFOLDER
ExecStop=-$COIN_PATH$COIN_CLI -conf=$CROPCOINFOLDER/$CONFIG_FILE -datadir=$CROPCOINFOLDER stop
Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5
[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $CROPCOINUSER.service
  systemctl enable $CROPCOINUSER.service >/dev/null 2>&1

  if [[ -z "$(ps axo cmd:100 | egrep $COIN_DAEMON)" ]]; then
    echo -e "${RED}Cropcoind is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo "systemctl start $CROPCOINUSER.service"
    echo "systemctl status $CROPCOINUSER.service"
    echo -e "less /var/log/syslog${NC}"
    exit 1
  fi
}


function ask_port() {
DEFAULTCROPCOINPORT=$COIN_PORT
read -p "CROPCOIN Port: " -i $DEFAULTCROPCOINPORT -e CROPCOINPORT
: ${CROPCOINPORT:=$DEFAULTCROPCOINPORT}
}

function ask_user() {
  DEFAULTCROPCOINUSER="cropcoin"
  read -p "Cropcoin user: " -i $DEFAULTCROPCOINUSER -e CROPCOINUSER
  : ${CROPCOINUSER:=$DEFAULTCROPCOINUSER}

  if [ -z "$(getent passwd $CROPCOINUSER)" ]; then
    useradd -m $CROPCOINUSER
    USERPASS=$(pwgen -s 12 1)
    echo "$CROPCOINUSER:$USERPASS" | chpasswd

    CROPCOINHOME=$(sudo -H -u $CROPCOINUSER bash -c 'echo $HOME')
    DEFAULTCROPCOINFOLDER="$CROPCOINHOME/.smrt"
    read -p "Configuration folder: " -i $DEFAULTCROPCOINFOLDER -e CROPCOINFOLDER
    : ${CROPCOINFOLDER:=$DEFAULTCROPCOINFOLDER}
    mkdir -p $CROPCOINFOLDER
    chown -R $CROPCOINUSER: $CROPCOINFOLDER >/dev/null
  else
    clear
    echo -e "${RED}User exits. Please enter another username: ${NC}"
    ask_user
  fi
}

function check_port() {
  declare -a PORTS
  PORTS=($(netstat -tnlp | awk '/LISTEN/ {print $4}' | awk -F":" '{print $NF}' | sort | uniq | tr '\r\n'  ' '))
  ask_port

  while [[ ${PORTS[@]} =~ $COIN_PORT ]] || [[ ${PORTS[@]} =~ $RPC_PORT ]]; do
    clear
    echo -e "${RED}Port in use, please choose another port:${NF}"
    ask_port
  done
}

function create_config() {
  RPCUSER=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n1)
  RPCPASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w22 | head -n1)
  cat << EOF > $CROPCOINFOLDER/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
rpcport=$RPC_PORT
listen=1
server=1
daemon=1
port=$COIN_PORT
EOF
}

function create_key() {
  echo -e "Enter your ${RED}Masternode Private Key${NC}. Leave it blank to generate a new ${RED}Masternode Private Key${NC} for you:"
  read -e CROPCOINKEY
  if [[ -z "$CROPCOINKEY" ]]; then
  sudo -u $CROPCOINUSER $COIN_PATH$COIN_DAEMON -daemon -conf=$CROPCOINFOLDER/$CONFIG_FILE -datadir=$CROPCOINFOLDER

  sleep 30
  if [ -z "$(ps axo cmd:100 | grep $COIN_DAEMON)" ]; then
   echo -e "${RED}$COIN_NAME server couldn not start. Check /var/log/syslog for errors.{$NC}"
   exit 1
  fi

  
  CROPCOINKEY=$(sudo -u $CROPCOINUSER $COIN_PATH$COIN_CLI -conf=$CROPCOINFOLDER/$CONFIG_FILE -datadir=$CROPCOINFOLDER masternode genkey)
  sudo -u $CROPCOINUSER $COIN_PATH$COIN_CLI -conf=$CROPCOINFOLDER/$CONFIG_FILE -datadir=$CROPCOINFOLDER stop
fi
clear
}


function update_config() {
  sed -i 's/daemon=1/daemon=0/' $CROPCOINFOLDER/$CONFIG_FILE
  NODEIP=$(curl -s4 icanhazip.com)
  cat << EOF >> $CROPCOINFOLDER/$CONFIG_FILE
logtimestamps=1
maxconnections=256
masternode=1
masternodeaddr=$NODEIP:$CROPCOINPORT
masternodeprivkey=$CROPCOINKEY
EOF
  chown -R $CROPCOINUSER: $CROPCOINFOLDER >/dev/null
}

function important_information() {
 echo
 echo -e "================================================================================================================================"
 echo -e "Cropcoin Masternode is up and running as user ${GREEN}$CROPCOINUSER${NC} and it is listening on port ${GREEN}$CROPCOINPORT${NC}."
 echo -e "${GREEN}$CROPCOINUSER${NC} password is ${RED}$USERPASS${NC}"
 echo -e "Configuration file is: ${RED}$CROPCOINFOLDER/$CONFIG_FILE${NC}"
 echo -e "Start: ${RED}systemctl start $CROPCOINUSER.service${NC}"
 echo -e "Stop: ${RED}systemctl stop $CROPCOINUSER.service${NC}"
 echo -e "VPS_IP:PORT ${RED}$NODEIP:$CROPCOINPORT${NC}"
 echo -e "MASTERNODE PRIVATEKEY is: ${RED}$CROPCOINKEY${NC}"
 echo -e "================================================================================================================================"
}

function setup_node() {
  ask_user
  check_port
  create_config
  create_key
  update_config
  enable_firewall
  important_information
  systemd_cropcoin
  
}


##### Main #####
clear

checks
if [[ ("$NEW_CROP" == "y" || "$NEW_CROP" == "Y") ]]; then
  setup_node
  exit 0
elif [[ "$NEW_CROP" == "new" ]]; then
  prepare_system
  download_node	
  setup_node
else
  echo -e "${GREEN}Cropcoind already running.${NC}"
  exit 0
fi



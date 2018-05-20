#!/bin/bash

TMP_FOLDER=$(mktemp -d)
CONFIG_FILE='smrt.conf'
BINARY_FILE="/usr/local/bin/smrtd"
COIN_REPO="https://github.com/smrt-crypto/smrt.git"
COIN_TGZ='https://github.com/zoldur/Smrt/releases/download/v1.1.0.5/smrt.tar.gz'

CONFIGFOLDER='/root/.smrt'
COIN_DAEMON='smrtd'
COIN_CLI='smrt-cli'
COIN_PATH='/usr/local/bin/'
COIN_ZIP=$(echo $COIN_TGZ | awk -F'/' '{print $NF}')
COIN_NAME='Smrt'
COIN_PORT=52312
RPC_PORT=52306



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



function ask_permission() {
 echo -e "${RED}I trust zoldur and want to use binaries compiled on his server.${NC}."
 echo -e "Please type ${RED}YES${NC} if you want to use precompiled binaries, or type anything else to compile them on your server"
 read -e ZOLDUR
}



function compile_node() {
  echo -e "Prepare to compile $COIN_NAME"
  git clone $COIN_REPO $TMP_FOLDER >/dev/null 2>&1
  compile_error
  cd $TMP_FOLDER
  chmod +x ./autogen.sh 
  chmod +x ./share/genbuild.sh
  chmod +x ./src/leveldb/build_detect_platform
  ./autogen.sh
  compile_error
  ./configure
  compile_error
  make
  compile_error
  make install
  compile_error
  strip $COIN_PATH$COIN_DAEMON $COIN_PATH$COIN_CLI
  cd - >/dev/null 2>&1
  rm -rf $TMP_FOLDER >/dev/null 2>&1
  clear
}

function compile_cropcoin() {
  echo -e "Clone git repo and compile it. This may take some time. Press a key to continue."
  read -n 1 -s -r -p ""

  git clone $CROP_REPO $TMP_FOLDER
  cd $TMP_FOLDER/src
  mkdir obj/support
  mkdir obj/crypto
  make -f makefile.unix
  compile_error cropcoin
  cp -a cropcoind $BINARY_FILE
  clear
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


function get_ip() {
  declare -a NODE_IPS
  for ips in $(netstat -i | awk '!/Kernel|Iface|lo/ {print $1," "}')
  do
    NODE_IPS+=($(curl --interface $ips --connect-timeout 2 -s4 icanhazip.com))
  done

  if [ ${#NODE_IPS[@]} -gt 1 ]
    then
      echo -e "${GREEN}More than one IP. Please type 0 to use the first IP, 1 for the second and so on...${NC}"
      INDEX=0
      for ip in "${NODE_IPS[@]}"
      do
        echo ${INDEX} $ip
        let INDEX=${INDEX}+1
      done
      read -e choose_ip
      NODEIP=${NODE_IPS[$choose_ip]}
  else
    NODEIP=${NODE_IPS[0]}
  fi
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
  DEFAULTCROPCOINUSER="user01"
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

  while [[ ${PORTS[@]} =~ $CROPCOINPORT ]] || [[ ${PORTS[@]} =~ $[CROPCOINPORT+1] ]]; do
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
  sleep 5
  if [ -z "$(pidof $COIN_DAEMON)" ]; then
   echo -e "${RED}Cropcoind server couldn't start. Check /var/log/syslog for errors.{$NC}"
   exit 1
  fi
  CROPCOINKEY=$(sudo -u $CROPCOINUSER $COIN_PATH$COIN_CLI -conf=$CROPCOINFOLDER/$CONFIG_FILE -datadir=$CROPCOINFOLDER masternode genkey)
  sudo -u $CROPCOINUSER $COIN_PATH$COIN_CLI -conf=$CROPCOINFOLDER/$CONFIG_FILE -datadir=$CROPCOINFOLDER stop
fi
}



function update_config() {
  sed -i 's/daemon=1/daemon=0/' $CROPCOINFOLDER/$CONFIG_FILE
  cat << EOF >> $CROPCOINFOLDER/$CONFIG_FILE
logintimestamps=1
maxconnections=256
#bind=$NODEIP
masternode=1
externalip=$NODEIP:$COIN_PORT
masternodeprivkey=$CROPCOINKEY
EOF
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
  get_ip
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
  ask_permission
  if [[ "$ZOLDUR" == "YES" ]]; then
    download_node
  else
    compile_node
  fi
  setup_node
else
  echo -e "${GREEN}Cropcoind already running.${NC}"
  exit 0
fi



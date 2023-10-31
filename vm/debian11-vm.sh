# Définition de la fonction header_info
function header_info {
  # Nettoie le terminal
  clear
  
  # Affiche un logo ASCII Art entre les balises EOF
  cat <<"EOF"
    ____       __    _                ___ ___
   / __ \___  / /_  (_)___ _____     <  /<_ /
  / / / / _ \/ __ \/ / __ `/ __ \    / / / /
 / /_/ /  __/ /_/ / / /_/ / / / /   / / / /
/_____/\___/_.___/_/\__,_/_/ /_/   /_/ /_/
EOF
}

# Appel de la fonction header_info pour afficher le logo ASCII Art
header_info

# Affiche un message indiquant que quelque chose est en cours de chargement
echo -e "\n Loading..."

# Génère une adresse MAC aléatoire et la stocke dans la variable GEN_MAC
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')

# Récupère le prochain ID disponible dans un cluster Proxmox VE et le stocke dans la variable NEXTID
NEXTID=$(pvesh get /cluster/nextid)


# Définit des variables pour les codes d'échappement ANSI, qui sont utilisés pour colorer le texte dans le terminal
YW=$(echo "\033[33m")         # Jaune
BL=$(echo "\033[36m")         # Bleu clair
HA=$(echo "\033[1;34m")       # Bleu foncé en gras
RD=$(echo "\033[01;31m")      # Rouge en gras
BGN=$(echo "\033[4;92m")      # Vert clair souligné
GN=$(echo "\033[1;92m")       # Vert clair en gras
DGN=$(echo "\033[32m")        # Vert foncé
CL=$(echo "\033[m")           # Reset des couleurs
BFR="\\r\\033[K"              # Efface la ligne courante dans le terminal
HOLD="-"                      # Un tiret, peut être utilisé comme indicateur visuel
CM="${GN}✓${CL}"              # Icône de validation en vert
CROSS="${RD}✗${CL}"           # Icône de croix en rouge
THIN="discard=on,ssd=1,"      # Une chaîne de texte, probablement utilisée comme option quelque part

# Active l'arrêt du script en cas d'erreur
set -e

# Définit une fonction trap pour gérer les erreurs et appeler la fonction error_handler avec le numéro de ligne et la commande qui a échoué
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR

# Définit une fonction trap pour appeler la fonction cleanup lors de la sortie du script
trap cleanup EXIT

# Définition de la fonction error_handler qui affiche un message d'erreur détaillé et appelle une fonction de nettoyage
function error_handler() {
  # Récupère le code de sortie de la dernière commande exécutée
  local exit_code="$?"
  
  # Récupère les paramètres passés à la fonction : numéro de ligne et commande
  local line_number="$1"
  local command="$2"
  
  # Construit et affiche le message d'erreur
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
  
  # Appelle une fonction de nettoyage (non définie dans cet extrait)
  cleanup_vmid
}


# Définition de la fonction cleanup_vmid qui arrête et détruit une machine virtuelle (VM) si elle existe
function cleanup_vmid() {
  # Vérifie si la VM avec l'ID $VMID existe
  if qm status $VMID &>/dev/null; then
    # Arrête la VM
    qm stop $VMID &>/dev/null
    
    # Détruit la VM
    qm destroy $VMID &>/dev/null
  fi
}

# Définition de la fonction cleanup qui revient au répertoire précédent et supprime un répertoire temporaire
function cleanup() {
  # Reviens au répertoire d'origine
  popd >/dev/null
  
  # Supprime le répertoire temporaire $TEMP_DIR
  rm -rf $TEMP_DIR
}

# Crée un répertoire temporaire et stocke son chemin dans la variable TEMP_DIR
TEMP_DIR=$(mktemp -d)

# Change le répertoire de travail courant pour le répertoire temporaire créé
pushd $TEMP_DIR >/dev/null

# Affiche une boîte de dialogue pour demander à l'utilisateur s'il souhaite créer une nouvelle VM Debian 11
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Debian 11 VM" --yesno "This will create a New Debian 11 VM. Proceed?" 10 58; then
  # Ne fait rien si l'utilisateur choisit "Yes"
  :
else
  # Affiche le logo ASCII Art et un message indiquant que l'utilisateur a quitté le script, puis termine le script
  header_info && echo -e "⚠ User exited script \n" && exit
fi

# Définition de la fonction msg_info qui affiche un message à l'utilisateur
function msg_info() {
  # Récupère le message à afficher
  local msg="$1"
  
  # Affiche le message avec une icône et une couleur spécifique
  echo -ne " ${HOLD} ${YW}${msg}..."
}


# Définition de la fonction msg_ok qui affiche un message de succès
function msg_ok() {
  # Récupère le message à afficher
  local msg="$1"
  
  # Affiche le message avec une icône de succès et une couleur verte
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

# Définition de la fonction msg_error qui affiche un message d'erreur
function msg_error() {
  # Récupère le message à afficher
  local msg="$1"
  
  # Affiche le message avec une icône de croix et une couleur rouge
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

# Définition de la fonction check_root qui vérifie si le script est exécuté en tant que root
function check_root() {
  # Vérifie si l'utilisateur est root ou si le script est exécuté avec sudo
  if [[ "$(id -u)" -ne 0 || $(ps -o comm= -p $PPID) == "sudo" ]]; then
    # Efface l'écran
    clear
    
    # Affiche un message d'erreur indiquant que le script doit être exécuté en tant que root
    msg_error "Please run this script as root."
    
    # Affiche un message indiquant que le script va se terminer
    echo -e "\nExiting..."
    
    # Attends 2 secondes
    sleep 2
    
    # Termine le script
    exit
  fi
}

# Définition de la fonction pve_check qui vérifie la version de Proxmox Virtual Environment
function pve_check() {
  # Vérifie si la version de PVE est au moins 7.2
  if ! pveversion | grep -Eq "pve-manager/(7\.[2-9]|8\.[0-9])"; then
    # Affiche un message d'erreur indiquant que la version de PVE n'est pas supportée
    msg_error "This version of Proxmox Virtual Environment is not supported"
    
    # Affiche un message indiquant les versions requises de PVE
    echo -e "Requires PVE Version 7.2 or higher"
    
    # Affiche un message indiquant que le script va se terminer
    echo -e "Exiting..."
    
    # Attends 2 secondes
    sleep 2
    
    # Termine le script
    exit
  fi
}


# Définition de la fonction arch_check qui vérifie l'architecture du système
function arch_check() {
  # Vérifie si l'architecture du système est amd64
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    # Affiche un message d'erreur indiquant que le script ne fonctionnera pas avec PiMox
    msg_error "This script will not work with PiMox! \n"
    
    # Affiche un message indiquant que le script va se terminer
    echo -e "Exiting..."
    
    # Attends 2 secondes
    sleep 2
    
    # Termine le script
    exit
  fi
}

# Définition de la fonction ssh_check qui vérifie si le script est exécuté via SSH
function ssh_check() {
  # Vérifie si la commande pveversion est disponible
  if command -v pveversion >/dev/null 2>&1; then
    # Vérifie si le script est exécuté via SSH
    if [ -n "${SSH_CLIENT:+x}" ]; then
      # Demande à l'utilisateur s'il souhaite continuer malgré l'exécution via SSH
      if whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "SSH DETECTED" --yesno "It's suggested to use the Proxmox shell instead of SSH, since SSH can create issues while gathering variables. Would you like to proceed with using SSH?" 10 62; then
        # Affiche un avertissement à l'utilisateur
        echo "you've been warned"
      else
        # Efface l'écran
        clear
        
        # Termine le script
        exit
      fi
    fi
  fi
}

# Définition de la fonction exit-script qui termine le script si l'utilisateur décide de quitter
function exit-script() {
  # Efface l'écran
  clear
  
  # Affiche un message indiquant que l'utilisateur a quitté le script
  echo -e "⚠  User exited script \n"
  
  # Termine le script
  exit
}


# Définition de la fonction default_settings qui configure les paramètres par défaut pour une machine virtuelle
function default_settings() {
  # Attribue l'ID de la prochaine machine virtuelle disponible à la variable VMID
  VMID="$NEXTID"
  
  # Définit le format du disque avec une partition EFI de 4M
  FORMAT=",efitype=4m"
  
  # Laisse la variable MACHINE vide, ce qui signifie que le type de machine par défaut sera utilisé
  MACHINE=""
  
  # Laisse la variable DISK_CACHE vide, ce qui signifie que le cache de disque par défaut sera utilisé
  DISK_CACHE=""
  
  # Définit le nom d'hôte de la machine virtuelle à "debian"
  HN="debian"
  
  # Laisse la variable CPU_TYPE vide, ce qui signifie que le type de CPU par défaut sera utilisé
  CPU_TYPE=""
  
  # Définit le nombre de cœurs CPU à allouer à la machine virtuelle à 2
  CORE_COUNT="2"
  
  # Définit la taille de la RAM à allouer à la machine virtuelle à 2048 Mo
  RAM_SIZE="2048"
  
  # Définit le pont réseau à utiliser pour la machine virtuelle à "vmbr0"
  BRG="vmbr0"
  
  # Attribue l'adresse MAC générée à la variable MAC
  MAC="$GEN_MAC"
  
  # Laisse la variable VLAN vide, ce qui signifie que le VLAN par défaut sera utilisé
  VLAN=""
  
  # Laisse la variable MTU vide, ce qui signifie que la taille MTU par défaut sera utilisée
  MTU=""
  
  # Définit si la machine virtuelle doit être démarrée automatiquement à "yes"
  START_VM="yes"
  
  # Affiche les paramètres par défaut qui seront utilisés pour créer la machine virtuelle
  echo -e "${DGN}Using Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${DGN}Using Machine Type: ${BGN}i440fx${CL}"
  echo -e "${DGN}Using Disk Cache: ${BGN}None${CL}"
  echo -e "${DGN}Using Hostname: ${BGN}${HN}${CL}"
  echo -e "${DGN}Using CPU Model: ${BGN}KVM64${CL}"
  echo -e "${DGN}Allocated Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${DGN}Allocated RAM: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${DGN}Using Bridge: ${BGN}${BRG}${CL}"
  echo -e "${DGN}Using MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${DGN}Using VLAN: ${BGN}Default${CL}"
  echo -e "${DGN}Using Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${DGN}Start VM when completed: ${BGN}no${CL}"
  
  # Informe l'utilisateur qu'une machine virtuelle Debian 11 sera créée avec les paramètres par défaut
  echo -e "${BL}Creating a Debian 11 VM using the above default settings${CL}"
}


# Définir la fonction advanced_settings qui permet à l'utilisateur de configurer les paramètres avancés pour une machine virtuelle
function advanced_settings() {
  
  # Boucle indéfiniment pour garantir une entrée utilisateur valide
  while true; do
    
    # Inviter l'utilisateur à entrer un ID de machine virtuelle, en utilisant $NEXTID comme valeur par défaut
    if VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 $NEXTID --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      
      # Vérifier si l'entrée est vide et, si c'est le cas, assigner la valeur par défaut $NEXTID à VMID
      if [ -z "$VMID" ]; then
        VMID="$NEXTID"
      fi
      
      # Vérifier si le VMID entré est déjà utilisé par un conteneur ou une machine virtuelle
      if pct status "$VMID" &>/dev/null || qm status "$VMID" &>/dev/null; then
        
        # Afficher un message d'erreur et attendre 2 secondes avant de continuer la boucle
        echo -e "${CROSS}${RD} ID $VMID is already in use${CL}"
        sleep 2
        continue
      fi
      
      # Afficher l'ID de machine virtuelle choisi
      echo -e "${DGN}Virtual Machine ID: ${BGN}$VMID${CL}"
      break
    else
      # Quitter le script si l'utilisateur annule la boîte de saisie
      exit-script
    fi
  done

  # Inviter l'utilisateur à choisir le type de machine (i440fx ou q35)
  if MACH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "MACHINE TYPE" --radiolist --cancel-button Exit-Script "Choose Type" 10 58 2 \
    "i440fx" "Machine i440fx" ON \
    "q35" "Machine q35" OFF \
    3>&1 1>&2 2>&3); then
    
    # Vérifier le type de machine choisi et définir les variables correspondantes
    if [ $MACH = q35 ]; then
      # Afficher le type de machine choisi et définir les variables FORMAT et MACHINE en conséquence
      echo -e "${DGN}Using Machine Type: ${BGN}$MACH${CL}"
      FORMAT=""
      MACHINE=" -machine q35"
    else
      # Afficher le type de machine choisi et définir les variables FORMAT et MACHINE en conséquence
      echo -e "${DGN}Using Machine Type: ${BGN}$MACH${CL}"
      FORMAT=",efitype=4m"
      MACHINE=""
    fi
  else
    # Quitter le script si l'utilisateur annule la sélection
    exit-script
  fi



  if DISK_CACHE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "DISK CACHE" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "None (Default)" ON \
    "1" "Write Through" OFF \
    3>&1 1>&2 2>&3); then
    if [ $DISK_CACHE = "1" ]; then
      echo -e "${DGN}Using Disk Cache: ${BGN}Write Through${CL}"
      DISK_CACHE="cache=writethrough,"
    else
      echo -e "${DGN}Using Disk Cache: ${BGN}None${CL}"
      DISK_CACHE=""
    fi
  else
    exit-script
  fi

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 debian --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VM_NAME ]; then
      HN="debian"
      echo -e "${DGN}Using Hostname: ${BGN}$HN${CL}"
    else
      HN=$(echo ${VM_NAME,,} | tr -d ' ')
      echo -e "${DGN}Using Hostname: ${BGN}$HN${CL}"
    fi
  else
    exit-script
  fi

  if CPU_TYPE1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CPU MODEL" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "KVM64 (Default)" ON \
    "1" "Host" OFF \
    3>&1 1>&2 2>&3); then
    if [ $CPU_TYPE1 = "1" ]; then
      echo -e "${DGN}Using CPU Model: ${BGN}Host${CL}"
      CPU_TYPE=" -cpu host"
    else
      echo -e "${DGN}Using CPU Model: ${BGN}KVM64${CL}"
      CPU_TYPE=""
    fi
  else
    exit-script
  fi

  if CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 2 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $CORE_COUNT ]; then
      CORE_COUNT="2"
      echo -e "${DGN}Allocated Cores: ${BGN}$CORE_COUNT${CL}"
    else
      echo -e "${DGN}Allocated Cores: ${BGN}$CORE_COUNT${CL}"
    fi
  else
    exit-script
  fi

  if RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 2048 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $RAM_SIZE ]; then
      RAM_SIZE="2048"
      echo -e "${DGN}Allocated RAM: ${BGN}$RAM_SIZE${CL}"
    else
      echo -e "${DGN}Allocated RAM: ${BGN}$RAM_SIZE${CL}"
    fi
  else
    exit-script
  fi

  if BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $BRG ]; then
      BRG="vmbr0"
      echo -e "${DGN}Using Bridge: ${BGN}$BRG${CL}"
    else
      echo -e "${DGN}Using Bridge: ${BGN}$BRG${CL}"
    fi
  else
    exit-script
  fi

  if MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a MAC Address" 8 58 $GEN_MAC --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $MAC1 ]; then
      MAC="$GEN_MAC"
      echo -e "${DGN}Using MAC Address: ${BGN}$MAC${CL}"
    else
      MAC="$MAC1"
      echo -e "${DGN}Using MAC Address: ${BGN}$MAC1${CL}"
    fi
  else
    exit-script
  fi

  if VLAN1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Vlan(leave blank for default)" 8 58 --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VLAN1 ]; then
      VLAN1="Default"
      VLAN=""
      echo -e "${DGN}Using Vlan: ${BGN}$VLAN1${CL}"
    else
      VLAN=",tag=$VLAN1"
      echo -e "${DGN}Using Vlan: ${BGN}$VLAN1${CL}"
    fi
  else
    exit-script
  fi

  if MTU1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Interface MTU Size (leave blank for default)" 8 58 --title "MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $MTU1 ]; then
      MTU1="Default"
      MTU=""
      echo -e "${DGN}Using Interface MTU Size: ${BGN}$MTU1${CL}"
    else
      MTU=",mtu=$MTU1"
      echo -e "${DGN}Using Interface MTU Size: ${BGN}$MTU1${CL}"
    fi
  else
    exit-script
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VIRTUAL MACHINE" --yesno "Start VM when completed?" 10 58); then
    echo -e "${DGN}Start VM when completed: ${BGN}yes${CL}"
    START_VM="yes"
  else
    echo -e "${DGN}Start VM when completed: ${BGN}no${CL}"
    START_VM="no"
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create a Debian 11 VM?" --no-button Do-Over 10 58); then
    echo -e "${RD}Creating a Debian 11 VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function start_script() {
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno "Use Default Settings?" --no-button Advanced 10 58); then
    header_info
    echo -e "${BL}Using Default Settings${CL}"
    default_settings
  else
    header_info
    echo -e "${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

check_root
arch_check
pve_check
ssh_check
start_script

# Afficher un message indiquant que la validation du stockage est en cours 
msg_info "Validating Storage"

# Boucle pour lire chaque ligne de la sortie de la commande pvesm status
while read -r line; do
  # Extraire le TAG, le TYPE et l'espace libre (FREE) à partir de chaque ligne
  TAG=$(echo $line | awk '{print $1}')
  TYPE=$(echo $line | awk '{printf "%-10s", $2}')
  FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
  
  # Construire la chaîne ITEM à afficher dans le menu
  ITEM="  Type: $TYPE Free: $FREE "
  
  # Définir l'OFFSET pour le formatage du message
  OFFSET=2
  
  # Vérifier si la longueur de l'ITEM dépasse la longueur maximale du message et la mettre à jour si nécessaire
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  
  # Ajouter le TAG et l'ITEM au menu de stockage
  STORAGE_MENU+=("$TAG" "$ITEM" "OFF")
done < <(pvesm status -content images | awk 'NR>1')  # Exécuter la commande pour obtenir le statut du stockage

# Vérifier si un stockage valide est détecté
VALID=$(pvesm status -content images | awk 'NR>1')
if [ -z "$VALID" ]; then
  # Afficher un message d'erreur si aucun stockage valide n'est détecté
  msg_error "Unable to detect a valid storage location."
  exit
elif [ $((${#STORAGE_MENU[@]} / 3)) -eq 1 ]; then
  # S'il n'y a qu'une seule option de stockage, l'attribuer automatiquement à STORAGE
  STORAGE=${STORAGE_MENU[0]}
else
  # Boucle jusqu'à ce que l'utilisateur choisisse un stockage
  while [ -z "${STORAGE:+x}" ]; do
    # Afficher une boîte de dialogue permettant à l'utilisateur de choisir un pool de stockage
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
      "Which storage pool you would like to use for ${HN}?\nTo make a selection, use the Spacebar.\n" \
      16 $(($MSG_MAX_LENGTH + 23)) 6 \
      "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3) || exit
  done
fi

msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."
msg_info "Retrieving the URL for the Debian 11 Qcow2 Disk Image"
URL=https://cloud.debian.org/images/cloud/bullseye/20231013-1532/debian-11-nocloud-amd64-20231013-1532.qcow2
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
wget -q --show-progress $URL
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

# Obtenir le type de stockage utilisé (par exemple, nfs, dir, btrfs) à partir de la sortie de la commande pvesm status
STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')

# Selon le type de stockage, définir les variables correspondantes pour la gestion des disques
case $STORAGE_TYPE in
  nfs | dir)  # Pour les types de stockage NFS ou DIR
    # Extension du fichier disque, référence du disque, options d'importation, et définir THIN comme une chaîne vide
    DISK_EXT=".qcow2"
    DISK_REF="$VMID/"
    DISK_IMPORT="-format qcow2"
    THIN=""
    ;;
  btrfs)  # Pour le type de stockage BTRFS
    # Extension du fichier disque, référence du disque, options d'importation, formatage, et définir THIN comme une chaîne vide
    DISK_EXT=".raw"
    DISK_REF="$VMID/"
    DISK_IMPORT="-format raw"
    FORMAT=",efitype=4m"
    THIN=""
    ;;
esac

# Boucle pour créer les noms de disque et les références pour deux disques (DISK0 et DISK1)
for i in {0,1}; do
  # Construire la variable disk (par exemple, DISK0, DISK1)
  disk="DISK$i"
  
  # Évaluer et construire le nom du disque (par exemple, vm-100-disk-0.qcow2)
  eval DISK${i}=vm-${VMID}-disk-${i}${DISK_EXT:-}
  
  # Évaluer et construire la référence du disque (par exemple, STORAGE:100/vm-100-disk-0.qcow2)
  eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
done


# Afficher un message indiquant que la création d'une VM Debian 11 est en cours
msg_info "Creating a Debian 11 VM"

# Créer une nouvelle machine virtuelle (VM) avec les paramètres spécifiés
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags proxmox-helper-scripts -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci

# Allouer de l'espace pour le disque 0 dans le stockage spécifié
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null

# Importer un disque dans la VM à partir d'un fichier
qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null

# Configurer la VM avec les disques spécifiés, l'ordre de démarrage et ajouter une description
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=2G \
  -boot order=scsi0 \
  -description "# Debian 11 VM
### https://github.com/tteck/Proxmox
[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/D1D7EP4GF)" >/dev/null

# Afficher un message indiquant que la VM Debian 11 a été créée avec succès
msg_ok "Created a Debian 11 VM ${CL}${BL}(${HN})"

# Vérifier si la VM doit être démarrée immédiatement
if [ "$START_VM" == "yes" ]; then
  # Afficher un message indiquant que la VM Debian 11 est en train de démarrer
  msg_info "Starting Debian 11 VM"
  
  # Démarrer la VM
  qm start $VMID
  
  # Afficher un message indiquant que la VM Debian 11 a démarré avec succès
  msg_ok "Started Debian 11 VM"
fi

# Afficher un message indiquant que le processus s'est terminé avec succès
msg_ok "Completed Successfully!\n"


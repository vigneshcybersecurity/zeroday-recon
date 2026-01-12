#!/bin/bash

# ==================================================
#  ZERODAY-RECON FRAMEWORK
#  Author : Vignesh
#  Version: 1.0
#  Purpose: Bug Bounty / VAPT Automation
# ==================================================

# -------------------------------
# Colors
# -------------------------------
RED="\e[31m"
GREEN="\e[32m"
CYAN="\e[36m"
RESET="\e[0m"

DOMAIN=$1
DATE=$(date +%F)
OUTDIR="recon-$DOMAIN-$DATE"

# -------------------------------
# Banner
# -------------------------------
clear
echo -e "${CYAN}"
echo "███████╗███████╗██████╗  ██████╗ ██████╗  █████╗ ██╗   ██╗"
echo "╚══███╔╝██╔════╝██╔══██╗██╔═══██╗██╔══██╗██╔══██╗╚██╗ ██╔╝"
echo "  ███╔╝ █████╗  ██████╔╝██║   ██║██████╔╝███████║ ╚████╔╝ "
echo " ███╔╝  ██╔══╝  ██╔══██╗██║   ██║██╔══██╗██╔══██║  ╚██╔╝  "
echo "███████╗███████╗██║  ██║╚██████╔╝██║  ██║██║  ██║   ██║   "
echo "╚══════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   "
echo "        Z E R O D A Y   R E C O N"
echo "              Author: Vignesh"
echo -e "${RESET}"
sleep 1

# -------------------------------
# Usage Check
# -------------------------------
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Usage: $0 example.com${RESET}"
    exit 1
fi

# -------------------------------
# Auto Installer
# -------------------------------
install_go() {
    if ! command -v go &>/dev/null; then
        echo -e "${CYAN}[+] Installing Go...${RESET}"
        sudo apt update
        sudo apt install -y golang
    fi
}

install_tool() {
    TOOL=$1
    CMD=$2

    if ! command -v $TOOL &>/dev/null; then
        echo -e "${CYAN}[+] Installing $TOOL...${RESET}"
        eval $CMD
    else
        echo -e "${GREEN}[✔] $TOOL already installed${RESET}"
    fi
}

echo -e "${CYAN}[+] Checking & installing required tools...${RESET}"
install_go

sudo apt install -y jq ffuf seclists unzip chromium amass

install_tool subfinder "go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
install_tool assetfinder "go install github.com/tomnomnom/assetfinder@latest"
install_tool httpx "go install github.com/projectdiscovery/httpx/cmd/httpx@latest"
install_tool naabu "go install github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
install_tool nuclei "go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
install_tool dnsx "go install github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
install_tool alterx "go install github.com/projectdiscovery/alterx/cmd/alterx@latest"
install_tool gowitness "go install github.com/sensepost/gowitness@latest"

# PATH Fix
if ! echo $PATH | grep -q "$HOME/go/bin"; then
    echo "export PATH=\$PATH:\$HOME/go/bin" >> ~/.bashrc
    source ~/.bashrc
fi

# -------------------------------
# Setup Directories
# -------------------------------
mkdir -p $OUTDIR/{enum,live,ports,screenshots,vulns}
cd $OUTDIR || exit

# -------------------------------
# Subdomain Enumeration
# -------------------------------
echo -e "${CYAN}[+] Subdomain enumeration...${RESET}"

subfinder -d $DOMAIN -all -recursive -o enum/subfinder.txt
assetfinder --subs-only $DOMAIN > enum/assetfinder.txt
amass enum -passive -d $DOMAIN > enum/amass.txt

curl -s "https://crt.sh/?q=%25.$DOMAIN&output=json" |
jq -r '.[].name_value' |
sed 's/\*\.//' | sort -u > enum/crtsh.txt

cat enum/*.txt | sort -u > enum/all_subdomains.txt

# -------------------------------
# Subdomain Permutation
# -------------------------------
echo -e "${CYAN}[+] Subdomain permutation (alterx)...${RESET}"
echo $DOMAIN | alterx | dnsx -silent > enum/alterx.txt

cat enum/all_subdomains.txt enum/alterx.txt |
sort -u > enum/final_subdomains.txt

# -------------------------------
# Live Host Detection
# -------------------------------
echo -e "${CYAN}[+] Live host detection (httpx)...${RESET}"
cat enum/final_subdomains.txt |
httpx -silent -status-code -title -tech-detect -o live/httpx.txt

cut -d ' ' -f1 live/httpx.txt > live/live_hosts.txt

# -------------------------------
# Port Scanning
# -------------------------------
echo -e "${CYAN}[+] Port scanning (naabu)...${RESET}"
naabu -list live/live_hosts.txt -top-ports 1000 -o ports/naabu.txt

# -------------------------------
# Screenshotting
# -------------------------------
echo -e "${CYAN}[+] Screenshotting (gowitness)...${RESET}"
gowitness file -f live/live_hosts.txt -P screenshots/

# -------------------------------
# Vulnerability Chaining
# -------------------------------
echo -e "${CYAN}[+] Vulnerability scan (nuclei)...${RESET}"
nuclei -l live/live_hosts.txt \
-severity low,medium,high,critical \
-o vulns/nuclei.txt

# -------------------------------
# FFUF Subdomain Bruteforce
# -------------------------------
echo -e "${CYAN}[+] FFUF subdomain bruteforce...${RESET}"
ffuf -u "https://FUZZ.$DOMAIN" \
-w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt \
-mc 200,301,302 -of json -o enum/ffuf.json

# -------------------------------
# Completion
# -------------------------------
echo -e "${GREEN}[✔] RECON COMPLETED SUCCESSFULLY${RESET}"
echo -e "${GREEN}[✔] Results saved in: $OUTDIR${RESET}"


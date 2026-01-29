#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# ZERODAY-RECON | Industry-Level All-in-One
# Author : Vignesh
# Version: 2.2 (Fully Fixed & Stable)
# ==================================================

# ---------------- COLORS ----------------
RED="\e[31m"; GREEN="\e[32m"; CYAN="\e[36m"; YELLOW="\e[33m"; RESET="\e[0m"

# ---------------- INPUT ----------------
DOMAIN="${1:-}"
MODE="${2:-passive}"   # passive | active | aggressive
DATE=$(date +"%Y-%m-%d_%H-%M")
OUTDIR="recon-$DOMAIN-$DATE"

# ---------------- USAGE ----------------
if [[ -z "$DOMAIN" ]]; then
  echo -e "${RED}Usage: $0 example.com [passive|active|aggressive]${RESET}"
  exit 1
fi

# ---------------- PATH FIX ----------------
export PATH="$PATH:$HOME/go/bin"

# ---------------- LOGGING ----------------
LOGDIR="$OUTDIR/logs"
log(){ echo -e "$(date '+%T') $1" | tee -a "$LOGDIR/main.log"; }

# ---------------- INSTALLERS ----------------
install_go(){
  command -v go &>/dev/null || sudo apt install -y golang
}

install_tool(){
  command -v "$1" &>/dev/null || eval "$2"
}

# ---------------- SETUP ----------------
clear
echo -e "${CYAN}ZERODAY-RECON | MODE: $MODE${RESET}"

mkdir -p "$OUTDIR"/{enum,live,ports,screenshots,vulns,reports,logs}
cd "$OUTDIR"

# ---------------- DEPENDENCIES ----------------
log "[+] Installing dependencies"
install_go
sudo apt install -y jq ffuf seclists amass chromium >/dev/null 2>&1

install_tool subfinder "go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
install_tool assetfinder "go install github.com/tomnomnom/assetfinder@latest"
install_tool httpx "go install github.com/projectdiscovery/httpx/cmd/httpx@latest"
install_tool naabu "go install github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
install_tool nuclei "go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
install_tool dnsx "go install github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
install_tool alterx "go install github.com/projectdiscovery/alterx/cmd/alterx@latest"
install_tool gowitness "go install github.com/sensepost/gowitness@latest"

# ---------------- ENUMERATION ----------------
log "[+] Subdomain enumeration started"
subfinder -d "$DOMAIN" -silent > enum/subfinder.txt
assetfinder --subs-only "$DOMAIN" > enum/assetfinder.txt
amass enum -passive -d "$DOMAIN" > enum/amass.txt

curl -s "https://crt.sh/?q=%25.$DOMAIN&output=json" |
jq -r '.[].name_value' | sed 's/\*\.//' | sort -u > enum/crtsh.txt

cat enum/*.txt | sort -u > enum/all_subdomains.txt

# ---------------- PERMUTATION ----------------
log "[+] Subdomain permutations"
alterx -l enum/all_subdomains.txt | dnsx -silent > enum/alterx.txt
cat enum/all_subdomains.txt enum/alterx.txt | sort -u > enum/final_subdomains.txt

# ---------------- LIVE HOSTS ----------------
log "[+] Live host detection"
httpx -l enum/final_subdomains.txt -silent > live/live_urls.txt

# clean URLs -> hosts (for naabu)
sed 's|https\?://||' live/live_urls.txt | cut -d/ -f1 | sort -u > live/live_hosts.txt

if [[ ! -s live/live_hosts.txt ]]; then
  log "[!] No live hosts found"
  exit 1
fi

# ---------------- PORT SCAN ----------------
if [[ "$MODE" != "passive" ]]; then
  log "[+] Port scanning (naabu)"
  naabu -list live/live_hosts.txt -top-ports 1000 -silent > ports/naabu.txt
fi

# ---------------- SCREENSHOTS ----------------
log "[+] Taking screenshots"
gowitness scan file -f live/live_urls.txt --destination screenshots/ >/dev/null 2>&1

# ---------------- VULNERABILITY SCAN ----------------
if [[ "$MODE" != "passive" ]]; then
  log "[+] Vulnerability scanning (nuclei)"
  nuclei -l live/live_urls.txt \
  -severity low,medium,high,critical \
  -o vulns/nuclei.txt
fi

# ---------------- AGGRESSIVE MODE ----------------
if [[ "$MODE" == "aggressive" ]]; then
  log "[!] Aggressive DNS brute force (FFUF)"
  ffuf -u "FUZZ.$DOMAIN" \
  -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt \
  -of json -o enum/ffuf.json
fi

# ---------------- REPORT ----------------
log "[+] Generating summary report"

SUBS=$(wc -l < enum/final_subdomains.txt)
LIVE=$(wc -l < live/live_hosts.txt)
PORTS=$( [[ -f ports/naabu.txt ]] && wc -l < ports/naabu.txt || echo 0 )
VULNS=$( [[ -f vulns/nuclei.txt ]] && wc -l < vulns/nuclei.txt || echo 0 )

cat <<EOF > reports/summary.txt
ZERODAY-RECON REPORT
-------------------
Target          : $DOMAIN
Mode            : $MODE
Subdomains      : $SUBS
Live Hosts      : $LIVE
Open Ports      : $PORTS
Vulnerabilities : $VULNS
Date            : $DATE
EOF

log "${GREEN}[✔] Recon completed successfully${RESET}"
log "${GREEN}[✔] Results saved in: $OUTDIR${RESET}"

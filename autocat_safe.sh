#!/bin/bash
set -euo pipefail

##################################################
############## AUTOCAT SECURE VERSION ############
##################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'
LIGHT_MAGENTA="\033[1;95m"
LIGHT_CYAN="\033[1;96m"

emoji_check="\u2714"
emoji_cat="\U1F431"
emoji_cross="\u274C"

printf "${LIGHT_CYAN}Welcome to Autocat${RESET} $emoji_cat\n"
logger -p user.notice "Autocat used by $USER with args: $*"

mask_total="?1?2?2?2?2?2?2?3?3?3?3?d?d?d?d"

config_file="config.json"

if [ ! -r "$config_file" ]; then
  printf "${RED}Missing or unreadable config file${RESET}\n"
  exit 1
fi

# Chargement des chemins depuis le JSON
cracking_sequence_path=$(jq -r '.cracking_sequence_path' "$config_file")
clem9669_wordlists_path=$(jq -r '.clem9669_wordlists_path' "$config_file")
clem9669_rules_path=$(jq -r '.clem9669_rules_path' "$config_file")
Hob0Rules_path=$(jq -r '.Hob0Rules_path' "$config_file")
OneRuleToRuleThemAll_rules_path=$(jq -r '.OneRuleToRuleThemAll_rules_path' "$config_file")

cracking_sequence="cracking_sequence.txt"
script_args=("$@")

# Sanity check
[ -f "$cracking_sequence" ] || { echo "Missing $cracking_sequence"; exit 1; }

find_path() {
  local rule="$1"
  for path in \
    "$clem9669_rules_path" \
    "$Hob0Rules_path" \
    "$OneRuleToRuleThemAll_rules_path" \
    "/usr/share/hashcat/rules"; do

    if [ -f "$path/$rule" ]; then
      echo "$path/$rule"
      return
    fi
  done

  printf "${RED}$rule still missing :(...${RESET}\n"
  exit 1
}

run_hashcat() {
  local potfile_number=1
  readarray -t lines < "$cracking_sequence"

  for line in "${lines[@]}"; do

    if [[ $line == *"brute-force"* ]]; then
      nb_digits=$(echo "$line" | grep -oE '(0|1?[0-9]|20)')
      mask="${mask_total:0:($nb_digits)*2}"

      printf "${LIGHT_MAGENTA}hashcat ${script_args[*]} -a 3 -1 ?l?d?u -2 ?l?d -3 tool/3_default.hcchr $mask -O -w 3${RESET}\n"
      hashcat "${script_args[@]}" -a 3 -1 ?l?d?u -2 ?l?d -3 tool/3_default.hcchr "$mask" -O -w 3

    elif [[ $line == *"potfile"* ]]; then
      rule=$(echo "$line" | cut -d " " -f 2)
      rule_path=$(find_path "$rule")

      tmp_potfile=$(mktemp --tmpdir autocat_potfile.XXXXXX)
      cat ~/.local/share/hashcat/hashcat.potfile | rev | cut -d':' -f1 | rev > "$tmp_potfile"

      printf "${LIGHT_MAGENTA}hashcat ${script_args[*]} $tmp_potfile -r $rule_path -O -w 3${RESET}\n"
      hashcat "${script_args[@]}" "$tmp_potfile" -r "$rule_path" -O -w 3
      rm -f "$tmp_potfile"
      potfile_number=$((potfile_number + 1))

    else
      wordlist=$(echo "$line" | cut -d " " -f 1)
      rule=$(echo "$line" | cut -d " " -f 2)

      # Validation simple noms
      [[ "$wordlist" =~ ^[a-zA-Z0-9._/-]+$ ]] || { echo "Invalid wordlist: $wordlist"; exit 1; }
      [[ "$rule" =~ ^[a-zA-Z0-9._/-]+$ ]] || { echo "Invalid rule: $rule"; exit 1; }

      rule_path=$(find_path "$rule")
      wordlist_path="$clem9669_wordlists_path/$wordlist"

      [ -f "$wordlist_path" ] || { echo "Missing wordlist: $wordlist_path"; exit 1; }

      printf "${LIGHT_MAGENTA}hashcat ${script_args[*]} $wordlist_path -r $rule_path -O -w 3${RESET}\n"
      hashcat "${script_args[@]}" "$wordlist_path" -r "$rule_path" -O -w 3
    fi
  done
}

check_for_wordlist() {
  local missing=0
  for dir in "$clem9669_wordlists_path" "$clem9669_rules_path" "$Hob0Rules_path" "$OneRuleToRuleThemAll_rules_path"; do
    if [ ! -d "$dir" ]; then
      printf "${RED}$emoji_cross Directory missing: $dir${RESET}\n"
      missing=1
    fi
  done

  if (( missing )); then
    printf "${YELLOW}Some required resources are missing. Please ask an admin to download them in /opt/Autocat.${RESET}\n"
    exit 1
  fi
}

check_for_wordlist
run_hashcat
#!/bin/bash
set -uo pipefail

##################################################
############## AUTOCAT IMPROVED ##################
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

mask_total="?1?2?2?2?2?2?2?3?3?3?3?d?d?d?d"
config_file="/opt/Autocat/config.json"

printf "${LIGHT_CYAN}Welcome to Autocat${RESET} $emoji_cat\n"
logger -p user.notice "Autocat started by $USER with args: $*"

# Defaults from config
if [ ! -r "$config_file" ]; then
  echo "Missing config file at $config_file"
  exit 1
fi

default_sequence=$(jq -r '.cracking_sequence_path' "$config_file")
clem9669_wordlists_path=$(jq -r '.clem9669_wordlists_path' "$config_file")
clem9669_rules_path=$(jq -r '.clem9669_rules_path' "$config_file")
Hob0Rules_path=$(jq -r '.Hob0Rules_path' "$config_file")
OneRuleToRuleThemAll_rules_path=$(jq -r '.OneRuleToRuleThemAll_rules_path' "$config_file")

script_args=()
custom_sequence=""
resume_step=1
force_mode=false

usage() {
  echo "Usage: autocat [hashcat options] [--sequence FILE] [--resume N] [--force]"
  echo ""
  echo "Options:"
  echo "  -s, --sequence FILE   Use a custom cracking sequence file"
  echo "  -r, --resume N        Resume at step N (default: 1)"
  echo "  -f, --force           Skip steps with missing files instead of exiting"
  echo "  -h, --help            Show this help message"
}

# Parse custom options
while [[ $# -gt 0 ]]; do
  case $1 in
    --sequence|-s)
      custom_sequence="$2"
      shift 2
      ;;
    --resume|-r)
      resume_step="$2"
      shift 2
      ;;
    --force|-f)
      force_mode=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      script_args+=("$1")
      shift
      ;;
  esac
done

cracking_sequence="${custom_sequence:-$default_sequence}"

if [ ! -f "$cracking_sequence" ]; then
  echo "Cracking sequence file not found: $cracking_sequence"
  exit 1
fi

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
  return 1
}

run_hashcat() {
  readarray -t lines < "$cracking_sequence"
  local total=${#lines[@]}

  for ((i=resume_step-1; i<total; i++)); do
    local line="${lines[i]}"
    local step=$((i+1))

    printf "${YELLOW}Step $step/$total:${RESET} $line\n"
    logger -p user.notice "Autocat step $step/$total: $line"

    if [[ $line == *"brute-force"* ]]; then
      nb_digits=$(echo "$line" | grep -oE '(0|1?[0-9]|20)')
      mask="${mask_total:0:($nb_digits)*2}"

      hashcat "${script_args[@]}" -a 3 -1 ?l?d?u -2 ?l?d -3 tool/3_default.hcchr "$mask" -O -w 3 || echo "Brute-force exited non-zero"

    elif [[ $line == *"potfile"* ]]; then
      rule=$(echo "$line" | cut -d " " -f 2)
      rule_path=$(find_path "$rule") || {
        if $force_mode; then
          echo "Missing rule $rule, skipping..."
          continue
        else
          echo "Missing rule $rule"
          exit 1
        fi
      }

      tmp_potfile=$(mktemp --tmpdir autocat_potfile.XXXXXX)
      cat ~/.local/share/hashcat/hashcat.potfile | rev | cut -d':' -f1 | rev > "$tmp_potfile"

      hashcat "${script_args[@]}" "$tmp_potfile" -r "$rule_path" -O -w 3 || echo "Potfile step failed"
      rm -f "$tmp_potfile"

    else
      wordlist=$(echo "$line" | cut -d " " -f 1)
      rule=$(echo "$line" | cut -d " " -f 2)

      rule_path=$(find_path "$rule") || {
        if $force_mode; then
          echo "Missing rule $rule, skipping..."
          continue
        else
          echo "Missing rule $rule"
          exit 1
        fi
      }

      wordlist_path="$clem9669_wordlists_path/$wordlist"
      if [ ! -f "$wordlist_path" ]; then
        if $force_mode; then
          echo "Missing wordlist $wordlist_path, skipping..."
          continue
        else
          echo "Missing wordlist $wordlist_path"
          exit 1
        fi
      fi

      hashcat "${script_args[@]}" "$wordlist_path" -r "$rule_path" -O -w 3 || echo "Wordlist step failed"
    fi
  done
}

check_for_files() {
  local missing_files=()

  # Lire chaque ligne de la cracking sequence
  while read -r line; do

    # brute-force → pas besoin de fichiers
    if [[ "$line" == *"brute-force"* ]]; then
      continue
    fi

    # potfile → on check seulement la règle
    if [[ "$line" == *"potfile"* ]]; then
      rule=$(echo "$line" | cut -d " " -f 2)
      rule_path=$(find_path "$rule") || missing_files+=("rule:$rule")
      continue
    fi

    # ligne classique : wordlist + rule
    wordlist=$(echo "$line" | cut -d " " -f 1)
    rule=$(echo "$line"    | cut -d " " -f 2)

    [ -f "$clem9669_wordlists_path/$wordlist" ] || missing_files+=("wordlist:$wordlist")
    find_path "$rule" >/dev/null 2>&1 || missing_files+=("rule:$rule")

  done < "$cracking_sequence"

  if ((${#missing_files[@]} > 0)); then
    if $force_mode; then
      echo "Warning: some wordlists or rules are missing: ${missing_files[*]}. Continuing due to --force."
      return
    fi

    echo -e "${YELLOW}Some files referenced in $cracking_sequence are missing:${RESET}"
    for f in "${missing_files[@]}"; do
      echo "  - $f"
    done
    read -p "Do you want to continue anyway? (y/N): " rep
    if [[ ! "$rep" =~ ^[Yy]$ ]]; then
      echo "Aborting."
      exit 1
    fi
  fi
}

check_for_files
run_hashcat
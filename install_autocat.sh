#!/bin/bash
set -e

DEST_DIR="/opt/Autocat"
BIN_LINK="/usr/local/bin/autocat"
CONFIG_FILE="$DEST_DIR/config.json"

echo "[+] Installing Autocat..."

# Créer /opt/Autocat si nécessaire
if [ ! -d "$DEST_DIR" ]; then
  sudo mkdir -p "$DEST_DIR"
  echo "[+] Created $DEST_DIR"
fi

# Copier le script
sudo cp autocat.sh "$DEST_DIR/"
sudo chmod 755 "$DEST_DIR/autocat.sh"
sudo chown root:root "$DEST_DIR/autocat.sh"

# Créer config.json par défaut si absent
if [ ! -f "$CONFIG_FILE" ]; then
cat <<EOF | sudo tee "$CONFIG_FILE" > /dev/null
{
  "cracking_sequence_path": "/opt/Autocat/cracking_sequence.txt",
  "clem9669_wordlists_path": "/opt/Autocat/wordlists",
  "clem9669_rules_path": "/opt/Autocat/rules/clem9669",
  "Hob0Rules_path": "/opt/Autocat/rules/Hob0Rules",
  "OneRuleToRuleThemAll_rules_path": "/opt/Autocat/rules/OneRuleToRuleThemAll"
}
EOF
  sudo chmod 644 "$CONFIG_FILE"
  echo "[+] Default config.json created"
fi

# Créer un lien dans /usr/local/bin
if [ ! -L "$BIN_LINK" ]; then
  sudo ln -s "$DEST_DIR/autocat.sh" "$BIN_LINK"
  echo "[+] Linked $BIN_LINK"
fi

echo "[+] Installation complete."
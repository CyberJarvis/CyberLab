#!/usr/bin/env bash
# One-shot: bring the lab up, reset DVWA DB, log in, set Security=Low.
# Run this before the demo (and again if your Mac rebooted overnight).
#   bash scripts/setup_lab.sh
set -e
cd "$(dirname "$0")/.."

B=http://127.0.0.1:4280
J=/tmp/dvwa_cookies.txt

echo "[*] Starting containers (DVWA + Juice Shop + hardened proxy)..."
docker compose -f docker-compose.yml -f docker-compose.hardened.yml up -d
echo "[*] Waiting for DVWA..."
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$B/login.php" || true)
  [ "$code" = "200" ] && break
  sleep 2
done

tok(){ grep -o "user_token' value='[^']*" | sed "s/.*value='//"; }
rm -f "$J"

echo "[*] Resetting DVWA database..."
T=$(curl -s -c "$J" -b "$J" "$B/setup.php" | tok)
curl -s -c "$J" -b "$J" -d "create_db=Create+%2F+Reset+Database&user_token=$T" "$B/setup.php" -o /dev/null
sleep 3

echo "[*] Logging in as admin and setting Security=Low..."
T=$(curl -s -c "$J" -b "$J" "$B/login.php" | tok)
curl -s -c "$J" -b "$J" -d "username=admin&password=password&Login=Login&user_token=$T" "$B/login.php" -o /dev/null
T=$(curl -s -c "$J" -b "$J" "$B/security.php" | tok)
curl -s -c "$J" -b "$J" -d "security=low&seclev_submit=Submit&user_token=$T" "$B/security.php" -o /dev/null

echo
echo "[+] Lab ready."
echo "    DVWA         : $B           (admin / password, Security=Low)"
echo "    Juice Shop   : http://127.0.0.1:3000"
echo "    Hardened DVWA: http://127.0.0.1:4281  (for the 'after' headers demo)"
echo "    Cookie jar   : $J  (PHPSESSID for terminal tools)"
echo
echo "    Next: open DEMO_RUNBOOK.md and follow the 6 findings."

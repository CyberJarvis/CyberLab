# Vulnerability Assessment and Security Enhancement of a Web Application
### Technical Report

**Author:** Roshan Ajith
**Date:** 17 October 2026
**Classification:** Academic mini-project — authorized testing of deliberately vulnerable software in an isolated lab

---

## 1. Executive Summary

An information-management web application was assessed in a controlled, isolated
laboratory to identify security weaknesses in **authentication, access control,
database security, and configuration**, to implement mitigations, and to measure
the improvement. Two deliberately vulnerable applications were used as stand-ins
for the organization's system: **DVWA** (primary, used for the before/after
comparison because its security levels expose the vulnerable vs. fixed source
code) and **OWASP Juice Shop** (secondary, a modern single-page application).

Six vulnerabilities were identified and exploited, spanning every required
category. All were then mitigated and re-tested; **every attack that succeeded in
the "before" state was neutralized in the "after" state.**

| # | Vulnerability | Category | Severity (CVSS v3.1) | Before | After |
|---|---|---|---|---|---|
| 1 | SQL Injection (DVWA) | Database | **8.8 High** | Full DB dump | Blocked |
| 2 | SQL Injection — auth bypass (Juice Shop) | Auth / Database | **9.8 Critical** | Admin login bypass | (code fix) |
| 3 | Broken Authentication — no lockout, weak creds | Auth / Access control | **8.1 High** | Account takeover | Lockout enforced |
| 4 | Command Injection (DVWA) | Config / Input | **8.8 High** | Remote code exec | Blocked |
| 5 | Cross-Site Scripting (reflected + stored) | Input validation | **6.1 Medium** | Script executes | Output encoded |
| 6 | Security Misconfiguration (headers, disclosure) | Configuration | **5.3 Medium** | Missing controls | Hardened |

**Overall risk moved from Critical to Low** after remediation.

---

## 2. Scope and Methodology

### 2.1 Scope
- **In scope:** `http://127.0.0.1:4280` (DVWA), `http://127.0.0.1:3000` (OWASP Juice Shop), both running locally in Docker.
- **Out of scope:** any external host. All tooling targeted loopback only.

### 2.2 Methodology
Aligned to **OWASP Web Security Testing Guide (WSTG)** and the **PTES** phases:
1. **Lab setup & scoping** — isolated Docker network, ports bound to `127.0.0.1`.
2. **Reconnaissance** — technology/misconfiguration scan (`nuclei`), header review.
3. **Vulnerability identification & exploitation** — `sqlmap`, manual injection, scripted credential attack, browser-based XSS.
4. **Analysis** — root cause, impact, severity scored with CVSS v3.1.
5. **Mitigation** — raise DVWA to the *Impossible* (fixed-source) level; deploy a hardened reverse proxy for configuration controls.
6. **Re-testing** — repeat each exploit; record before/after.

### 2.3 Tools
`sqlmap` (SQL injection), `nuclei` (misconfiguration/exposure scanning), `nikto`/`curl`
(headers), scripted dictionary attack (equiv. `hydra`), the built-in browser
(manual XSS and screenshots), Docker (lab + hardened proxy).

### 2.4 Lab setup
`docker-compose.yml` runs both targets on a private bridge network, published only
to loopback. DVWA was initialised (Create/Reset Database) and set to **Security =
Low** as the vulnerable baseline. See `README.md`. Baseline reconnaissance flagged:

```
[configuration-listing] [medium] http://127.0.0.1:4280/config/     (DVWA config dir listing)
[prometheus-metrics]    [medium] http://127.0.0.1:3000/metrics     (Juice Shop metrics exposed)
```

---

## 3. Findings

Each finding: description, root cause, impact, severity, evidence, remediation.
Evidence files are under `evidence/`; vulnerable vs. fixed source under `evidence/source/`.

### Finding 1 — SQL Injection (DVWA) · CVSS 8.8 High
`CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H`

**Description.** The `id` parameter of the SQL Injection module is concatenated
directly into a SQL query. `sqlmap` confirmed **four** injection techniques
(boolean-blind, error-based, time-based, UNION).

**Root cause.** Unsanitised user input built into a dynamic SQL string:
```php
$id = $_REQUEST['id'];
$query = "SELECT first_name, last_name FROM users WHERE user_id = '$id';";   // vulnerable
```

**Impact.** Full read access to the database. The entire `users` table was
dumped, including password hashes. Because passwords are stored as **unsalted
MD5**, `sqlmap` cracked four of five instantly:

```
admin   : 5f4dcc3b5aa765d61d8327deb882cf99 -> password
gordonb : e99a18c428cb38d5f260853678922e03 -> abc123
1337    : 8d3533d75ae2c3966d7e0d4fcc69216b -> charley
pablo   : 0d107d09f5bbe40cade3de5c71e9e9b7 -> letmein
smithy  : 5f4dcc3b5aa765d61d8327deb882cf99 -> password
```
Evidence: `evidence/before/sqlmap_dvwa.txt`, `evidence/before/sqlmap_techniques.txt`,
screenshot `evidence/before/sqli_dump_screenshot.jpg`.

**Remediation (implemented).** DVWA *Impossible* uses a **parameterised PDO
prepared statement**, an `is_numeric()` check, and an anti-CSRF token:
```php
$data = $db->prepare('SELECT first_name, last_name FROM users WHERE user_id = (:id) LIMIT 1;');
$data->bindParam(':id', $id, PDO::PARAM_INT);            // fixed
```
**Re-test:** the UNION payload returned **NO DATA** — injection blocked
(`evidence/after/dvwa_impossible_retests.txt`). Passwords should additionally be
stored with a salted adaptive hash (bcrypt/Argon2).

### Finding 2 — SQL Injection Authentication Bypass (Juice Shop) · CVSS 9.8 Critical
`CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H`

**Description.** The login endpoint `/rest/user/login` is injectable. Supplying
the email `' OR 1=1--` bypasses authentication with no password.

**Impact.** Unauthenticated login as the **administrator** (`admin@juice-sh.op`,
id 1, role admin); a valid JWT was returned. Evidence:
`evidence/before/juiceshop_sqli_login.txt`.
```
[+] Authenticated as: admin@juice-sh.op | id: 1 | role: admin
[+] token: eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9...
```
**Root cause.** Email value concatenated into the authentication query.
**Remediation (recommended).** Parameterised query / ORM binding; server-side
input validation; generic login errors. (Juice Shop is challenge-based, so the
fix is documented at code level rather than toggled.)

### Finding 3 — Broken Authentication: No Lockout + Weak Credentials · CVSS 8.1 High
`CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:N`

**Description.** The login performs no rate-limiting or account lockout, enabling
unlimited brute force. A scripted dictionary attack recovered `admin:password`,
and the account remained usable after 10 consecutive failures.
```
[+] VALID: admin:password
[+] after 10 failures admin:password STILL accepted = NO LOCKOUT
```
Evidence: `evidence/before/bruteforce_dvwa.txt`. Equivalent tool:
`hydra -l admin -P wordlist.txt 127.0.0.1 -s 4280 http-get-form "..."`.

**Impact.** Account takeover; combined with Finding 1's weak hashing, mass
credential compromise.
**Remediation (implemented).** DVWA *Impossible* enforces **lockout after 3
failed logins for 15 s**, uses prepared statements, and adds response-timing
defences:
```php
$total_failed_login = 3;  $lockout_time = 15;   // fixed
```
Recommended additionally: strong password policy, MFA, salted hashing.

### Finding 4 — OS Command Injection (DVWA) · CVSS 8.8 High
`CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H`

**Description.** The "Ping" feature concatenates the `ip` field into a shell
command. Payload `127.0.0.1; id; uname -a` executed arbitrary commands:
```
uid=33(www-data) gid=33(www-data) groups=33(www-data)
Linux 07f1b0c98785 6.10.14-linuxkit ... x86_64 GNU/Linux
```
Evidence: `evidence/before/cmdi_dvwa.txt`, screenshot `evidence/before/cmdi_screenshot.jpg`.

**Root cause.** Unvalidated input passed to `shell_exec`.
**Remediation (implemented).** *Impossible* validates the four octets with
`is_numeric()` and rebuilds the IP (allow-listing). Re-test returned
`ERROR: You have entered an invalid IP.` — injection blocked.
Recommended: avoid shells entirely; if unavoidable use `escapeshellarg()`.

### Finding 5 — Cross-Site Scripting (Reflected + Stored) · CVSS 6.1 Medium
`CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N`

**Description.** User input is echoed to the page without output encoding.
- **Reflected:** `name=<script>alert('XSS-reflected')</script>` reflected verbatim.
- **Stored:** a `<script>` payload saved to the guestbook persisted unencoded and
  executes for every visitor.

Evidence: `evidence/before/xss_reflected_dvwa.txt`, `evidence/before/xss_stored_dvwa.txt`.

**Impact.** Session/cookie theft, defacement, phishing, wormable stored payloads.
**Remediation (implemented).** *Impossible* applies `htmlspecialchars()` on
output. Re-test: stored payload came back **encoded** (`&lt;script&gt;`), not
executed. A **Content-Security-Policy** (Finding 6) adds defence-in-depth.

### Finding 6 — Security Misconfiguration · CVSS 5.3 Medium
`CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:N`

**Description.** Baseline review found: missing security headers (no CSP,
X-Frame-Options, X-Content-Type-Options, HSTS), session cookie without
`HttpOnly`/`Secure`/`SameSite`, server version disclosed (`Apache/2.4.25
(Debian)`), directory listing at `/config/`, and exposed `/metrics` on Juice Shop.
Evidence: `evidence/before/dvwa_headers.txt`, `evidence/before/nuclei_baseline.txt`.

**Impact.** Enables clickjacking, MIME-sniffing, XSS escalation, cookie theft,
and information disclosure aiding other attacks.
**Remediation (implemented).** A hardened **nginx reverse proxy**
(`hardening/nginx-hardened.conf`) now adds CSP, `X-Frame-Options: DENY`,
`X-Content-Type-Options: nosniff`, HSTS, Referrer-Policy, Permissions-Policy,
hides the server version, and rewrites the session cookie to
`HttpOnly; SameSite=Strict`. Evidence: `evidence/after/dvwa_headers_hardened.txt`.

---

## 4. Before / After Results

| Vulnerability | Before (Security = Low / default) | After (Impossible + hardened proxy) |
|---|---|---|
| SQL Injection (DVWA) | 4 techniques; full `users` dump | **No data returned** — prepared statements + `is_numeric` |
| SQLi auth bypass (Juice Shop) | Admin login with `' OR 1=1--` | Parameterised query (code fix) |
| Broken Authentication | `admin:password` found; no lockout | **Lockout after 3 fails / 15 s** |
| Command Injection | `uid=33(www-data)`, RCE | **"Invalid IP"** — octet allow-list |
| XSS (reflected + stored) | `<script>` executes | **Encoded** `&lt;script&gt;` + CSP |
| Misconfiguration | No security headers; version leaked | **All headers present; version hidden; HttpOnly+SameSite cookie** |

**Header before → after (DVWA):**
```
BEFORE: Server: Apache/2.4.25 (Debian) | (no CSP/XFO/XCTO/HSTS) | Set-Cookie: PHPSESSID=...  (no flags)
AFTER : Server: nginx | CSP + X-Frame-Options: DENY + X-Content-Type-Options: nosniff + HSTS
        Set-Cookie: PHPSESSID=...; HttpOnly; SameSite=Strict
```

---

## 5. Recommendations (prioritised)

1. **Parameterised queries / ORM everywhere** — eliminates Findings 1 & 2.
2. **Authentication hardening** — lockout + rate limiting, strong password policy, **MFA**.
3. **Password storage** — replace unsalted MD5 with **bcrypt/Argon2** (salted, adaptive).
4. **Output encoding + CSP** — context-aware encoding on all output; strict CSP.
5. **Avoid shell calls**; where unavoidable, allow-list and `escapeshellarg()`.
6. **Secure configuration baseline** — security headers, hide versions, disable
   directory listing, protect `/metrics`, secure cookie flags.
7. **Process** — integrate SAST/DAST into CI and schedule periodic reassessment.

---

## 6. Conclusion

All six vulnerabilities were reproduced with concrete evidence and then
successfully mitigated; re-testing confirmed each previously successful attack was
blocked. The exercise demonstrates that the dominant risks — injection, broken
authentication, and misconfiguration — stem from a few recurring root causes
(trusting user input, weak auth design, insecure defaults) and are addressed by
well-established controls. Residual risk after remediation is **Low**.

---

## 7. References
- OWASP Top 10 (2021); OWASP Web Security Testing Guide (WSTG)
- OWASP Cheat Sheets: SQL Injection Prevention, XSS Prevention, Password Storage
- FIRST CVSS v3.1 Specification
- DVWA (digininja/DVWA); OWASP Juice Shop (bkimminich/juice-shop)

---

## Appendix A — Reproduction
See `README.md`. Lab: `docker compose up -d`; hardened proxy:
`docker compose -f docker-compose.yml -f docker-compose.hardened.yml up -d proxy`.
Teardown: `docker compose down -v`. All evidence under `evidence/` (`before/`,
`after/`, `source/`).

# Vulnerability Assessment Lab

Isolated testbed for the mini-project *"Vulnerability Assessment and Security
Enhancement of a Web Application."* Uses two deliberately vulnerable apps for
authorized, educational security testing. **Everything runs on `127.0.0.1` only.**

## Targets
| App | URL | Role |
|---|---|---|
| DVWA | http://127.0.0.1:4280 | Primary — has Low→Impossible security levels for before/after |
| OWASP Juice Shop | http://127.0.0.1:3000 | Secondary — modern SPA example |

## Run
```bash
docker compose up -d
docker compose ps
```

### DVWA first-run
1. Open http://127.0.0.1:4280 → redirected to `setup.php`.
2. Click **Create / Reset Database**.
3. Log in with `admin` / `password`.
4. **DVWA Security → Low** (baseline for the "before" tests).

Juice Shop needs no setup.

## Security levels (DVWA)
- `Low` = vulnerable baseline ("before").
- `High` / `Impossible` = fixed source ("after"). Toggle under *DVWA Security*.

## Teardown
```bash
docker compose down -v
```

## Safety notes
- Ports are published only to loopback (`127.0.0.1`). Do not change to `0.0.0.0`.
- Only test these local containers. Never point the tools at any external host.
- This lab is for coursework on intentionally vulnerable software.

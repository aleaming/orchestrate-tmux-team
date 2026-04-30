---
name: security-audit
description: Use when reviewing code for security issues, before opening a PR that touches authentication, input handling, or external I/O, or when the user asks for a "security review", "vulnerability scan", or "audit". Provides a structured checklist covering OWASP Top 10, secret exposure, and dependency hygiene.
---

# Security Audit

A repeatable checklist for reviewing code changes (and the surrounding repo) for security issues.

## Run order

1. **Secret scan** — quick automated pass for high-signal leaks.
2. **Input boundaries** — every place untrusted data enters the system.
3. **Authentication & authorization** — who can do what.
4. **Dependency hygiene** — known-vulnerable packages.
5. **Operational posture** — logging, error handling, file permissions.

## 1. Secret scan

```bash
git ls-files | grep -E '(^|/)(\.env(\.[a-z]+)?|credentials\.json|secrets\.json|.*\.(pem|key|p12|pfx))$' && echo "TRACKED SECRETS DETECTED"

git grep -nE '(AKIA[0-9A-Z]{16}|sk-(ant|live|test)-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{36}|-----BEGIN [A-Z ]*PRIVATE KEY-----)'
```

If anything matches, **stop and rotate the credential** — `git rm --cached` is not enough; the secret is in history.

## 2. Input boundaries (OWASP A03 — Injection)

For every external input (HTTP body, query param, env var, file upload, MCP tool input):

- [ ] Validated against an allowlist or schema?
- [ ] Parameterized when reaching SQL / shell / LDAP / NoSQL?
- [ ] Auto- or explicitly-escaped if rendered to HTML?
- [ ] If a file path, constrained to an allowed root (`pathlib.resolve()` + `relative_to()`)?

**Red flags:** `f"... {user_input} ..."` interpolated into shell/SQL, `eval()`, `exec()`, `subprocess.run(..., shell=True)`.

## 3. Auth (OWASP A01, A07)

- [ ] Every authenticated endpoint verifies the token on every request.
- [ ] Authorization is checked *after* authentication, on every action — not just at login.
- [ ] Password handling uses a slow KDF (`bcrypt`/`scrypt`/`argon2`) — never raw MD5/SHA1/SHA256.
- [ ] Tokens have explicit expiry and a revocation path.

## 4. Dependencies (OWASP A06)

```bash
npm audit --audit-level=high
pip-audit
safety check
```

Pin versions in lockfiles. Don't blindly `npm audit fix --force`.

## 5. Operational posture

- [ ] Errors don't leak stack traces or SQL to end users.
- [ ] Logs don't print secrets or full request bodies.
- [ ] File permissions on `.env`, key files, SSH config are `600`.
- [ ] CORS allowlist is explicit, not `*`.
- [ ] Rate limiting on auth endpoints.

## Output format

```
## Findings

### HIGH — <title>
File: path/to/file.ext:LINE
Risk: <one sentence>
Remediation: <one sentence + diff or code snippet>

### MEDIUM — ...
### LOW — ...
```

Severity: HIGH = exploitable today by an external attacker; MEDIUM = exploitable with prerequisites or insider; LOW = defense-in-depth.

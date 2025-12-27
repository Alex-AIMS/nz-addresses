# Security Policy

## Supported Versions

Currently, only the latest version on the `main` branch is actively supported with security updates.

| Version | Supported          |
| ------- | ------------------ |
| main    | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to the repository maintainers. You can find the maintainer email in the GitHub repository settings or commit history.

### What to Include

When reporting a vulnerability, please include:

- Type of vulnerability (e.g., SQL injection, XSS, authentication bypass)
- Full paths of affected source file(s)
- Location of the affected code (tag/branch/commit)
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the vulnerability

### What to Expect

- **Acknowledgment**: Within 48 hours
- **Initial Assessment**: Within 1 week
- **Fix Timeline**: Depends on severity, but we aim for:
  - Critical: 1-7 days
  - High: 1-2 weeks
  - Medium: 2-4 weeks
  - Low: Next release cycle

### Security Best Practices for Users

When deploying this service:

1. **Protect your config.env file:**
   ```bash
   chmod 600 config.env
   ```

2. **Don't expose PostgreSQL port publicly:**
   - Only expose port 8080 (API)
   - Keep port 5432 internal or use firewall rules

3. **Use strong database passwords:**
   ```bash
   # In config.env
   POSTGRES_PASSWORD=$(openssl rand -base64 32)
   ```

4. **Run behind a reverse proxy:**
   - Use Nginx or Traefik
   - Enable HTTPS with Let's Encrypt
   - Implement rate limiting

5. **Keep Docker images updated:**
   ```bash
   docker pull postgis/postgis:16-3.4
   # Rebuild your image regularly
   ```

6. **Monitor logs:**
   ```bash
   docker logs -f nz-addresses
   ```

7. **API key security:**
   - Never commit config.env to git
   - Rotate API keys periodically
   - Use environment variables in production

### Known Security Considerations

- **SQL Injection**: All queries use parameterized queries via Dapper/EF Core
- **API Rate Limiting**: Not implemented by default - add at reverse proxy level
- **Authentication**: Not included - add OAuth2/JWT if needed for your use case
- **Input Validation**: Address inputs are validated, but add additional layers for production

### Disclosure Policy

- We will coordinate disclosure timing with you
- Credit will be given to reporters (unless you prefer anonymity)
- CVE IDs will be requested for serious vulnerabilities
- Security advisories will be published on GitHub

## Contact

For security concerns, please contact the repository maintainers through GitHub.

Thank you for helping keep NZ Addresses secure! 🛡️

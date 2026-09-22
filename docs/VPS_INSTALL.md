# One-command VPS installation

ASM can be installed as a standalone, single-database service on a fresh Debian
or Ubuntu VPS. The installer creates a local PostgreSQL database, initializes
the ASM tables, disables the guest login, configures Apache, and obtains a
Let's Encrypt certificate.

## Requirements

- A fresh Debian or Ubuntu VPS with at least 2 GB RAM.
- Root or `sudo` access.
- A DNS `A`/`AAAA` record already pointing your hostname at the VPS.
- Inbound TCP ports 80 and 443 open.
- A clone of this repository on the VPS.

## Install

From the repository root, run:

```bash
sudo ./scripts/install-vps.sh \
  --domain asm.example.org \
  --email admin@example.org
```

That is the only installation command. Database and initial administrator
passwords are generated automatically. The administrator password is printed
at the end and saved in `/root/asm3-install-credentials.txt`, readable only by
root.

For a private test server without TLS, use `--no-tls`. Do not use that option
for an internet-facing production system.

The installer intentionally refuses to overwrite `/etc/asm3.conf` or
`/opt/asm3`. It is intended for a new installation, not an in-place upgrade.

## What is installed

- Application: `/opt/asm3`
- Configuration: `/etc/asm3.conf`
- Uploaded media: `/var/lib/asm3/media`
- Disk cache: `/var/cache/asm3`
- Apache site: `/etc/apache2/sites-available/asm3.conf`
- Daily maintenance: `/etc/cron.daily/asm3`
- Generated credentials: `/root/asm3-install-credentials.txt`

The PostgreSQL server listens locally and is not published by the installer.
Only Apache should be exposed publicly.

## Backups

Back up both the database and media directory. For example:

```bash
sudo -u postgres pg_dump asm3 | gzip > asm3-$(date +%F).sql.gz
sudo tar -C /var/lib -czf asm3-media-$(date +%F).tar.gz asm3/media
```

Copy backups off the VPS and regularly test restoring them. The installer does
not configure remote backup storage or SMTP because those credentials and
providers are deployment-specific.

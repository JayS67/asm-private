#!/usr/bin/env python3
"""Create or update a user in an existing ASM SQLite database.

Intended for local development and disposable test environments. Production
accounts should be managed through ASM's Users screen so normal auditing and
permission controls are applied.
"""

import argparse
import base64
import hashlib
import os
import sqlite3


def hash_password(password: str) -> str:
    """Return a password in the PBKDF2 format accepted by ASM."""
    salt = base64.b64encode(os.urandom(16)).decode("ascii")
    iterations = 10_000
    digest = hashlib.pbkdf2_hmac("sha1", password.encode("utf-8"), salt.encode("utf-8"), iterations).hex()
    return f"pbkdf2:sha1:{salt}:{iterations}:{digest}"


def upsert_user(database: str, username: str, password: str, real_name: str, superuser: bool) -> None:
    with sqlite3.connect(database) as connection:
        existing = connection.execute(
            "SELECT ID FROM users WHERE LOWER(UserName) = LOWER(?)", (username,)
        ).fetchone()
        values = (real_name, hash_password(password), int(superuser), username)
        if existing:
            connection.execute(
                "UPDATE users SET RealName=?, Password=?, SuperUser=?, DisableLogin=0 "
                "WHERE LOWER(UserName)=LOWER(?)", values
            )
        else:
            next_id = connection.execute("SELECT COALESCE(MAX(ID), 0) + 1 FROM users").fetchone()[0]
            connection.execute(
                "INSERT INTO users (ID, UserName, RealName, EmailAddress, Password, EnableTOTP, "
                "OTPSecret, SuperUser, OwnerID, SecurityMap, IPRestriction, Signature, LocaleOverride, "
                "ThemeOverride, SiteID, DisableLogin, LocationFilter, RecordVersion) "
                "VALUES (?, ?, ?, '', ?, 0, '', ?, 0, 'dummy', '', '', '', '', 0, 0, '', 0)",
                (next_id, username, real_name, hash_password(password), int(superuser)),
            )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", help="Path to an existing ASM SQLite database")
    parser.add_argument("--username", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--real-name", default="")
    parser.add_argument("--standard-user", action="store_true", help="Do not grant superuser access")
    args = parser.parse_args()
    if not os.path.isfile(args.database):
        parser.error(f"database does not exist: {args.database}")
    upsert_user(args.database, args.username, args.password, args.real_name or args.username, not args.standard_user)
    print(f"User '{args.username}' is ready in {args.database}")


if __name__ == "__main__":
    main()

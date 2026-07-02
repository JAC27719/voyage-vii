#!/bin/sh
set -eu

: "${POSTGRES_PASSWORD_FILE:?POSTGRES_PASSWORD_FILE is required}"
test -r "${POSTGRES_PASSWORD_FILE}"

if [ ! -s "${PGDATA}/PG_VERSION" ]; then
    initdb \
        --pgdata="${PGDATA}" \
        --username=postgres \
        --pwfile="${POSTGRES_PASSWORD_FILE}" \
        --auth-host=scram-sha-256 \
        --auth-local=trust
    {
        printf "\nlisten_addresses = '*'\n"
        printf "password_encryption = 'scram-sha-256'\n"
    } >> "${PGDATA}/postgresql.conf"
    printf "host all all 0.0.0.0/0 scram-sha-256\n" >> "${PGDATA}/pg_hba.conf"
fi

exec postgres -D "${PGDATA}"

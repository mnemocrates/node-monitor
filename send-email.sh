#!/usr/bin/env bash

set -euo pipefail

SUBJECT="$1"
BODY="$2"

source /usr/local/node-monitor/config.sh

if [ "${EMAIL_ENABLED}" != "true" ]; then
    exit 0
fi

python3 <<EOF
import smtplib
from email.mime.text import MIMEText

msg = MIMEText("""${BODY}""")
msg["Subject"] = "${SUBJECT}"
msg["From"] = "${EMAIL_FROM}"
msg["To"] = "${EMAIL_TO}"

with smtplib.SMTP("${SMTP_SERVER}", ${SMTP_PORT}) as server:
    server.starttls()
    server.login("${SMTP_USERNAME}", "${SMTP_PASSWORD}")
    server.send_message(msg)
EOF

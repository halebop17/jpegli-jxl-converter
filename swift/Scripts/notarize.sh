#!/usr/bin/env bash
# notarize.sh — submit a signed app to Apple's notary service, wait for
# the verdict, and staple the ticket to the bundle on success.
#
# Required env vars (or pass as arguments):
#   AC_USERNAME — Apple ID email
#   AC_PASSWORD — app-specific password
#   AC_TEAM_ID  — team identifier (10 chars)
#
# Usage:  notarize.sh <path/to/JPG\ Master.app>
set -euo pipefail

APP="${1:?usage: notarize.sh <app.bundle>}"
: "${AC_USERNAME:?AC_USERNAME not set}"
: "${AC_PASSWORD:?AC_PASSWORD not set}"
: "${AC_TEAM_ID:?AC_TEAM_ID not set}"

ZIP="${APP%.app}-notarize.zip"

echo "Compressing…"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Submitting to notary service…"
xcrun notarytool submit "$ZIP" \
    --apple-id "$AC_USERNAME" \
    --password "$AC_PASSWORD" \
    --team-id "$AC_TEAM_ID" \
    --wait

echo "Stapling ticket…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

rm -f "$ZIP"
echo "Notarized: $APP"

#!/bin/bash
set -euo pipefail
: "${CERTIFICATE:?Missing IOS_CERTIFICATE_P12_BASE64}"
: "${CERT_PASSWORD:?Missing IOS_CERTIFICATE_PASSWORD}"
: "${PROFILE:?Missing IOS_PROVISION_PROFILE_BASE64}"
: "${TEAM:?Missing IOS_TEAM_ID}"
printf '%s' "$CERTIFICATE" | base64 --decode > "$RUNNER_TEMP/certificate.p12"
printf '%s' "$PROFILE" | base64 --decode > "$RUNNER_TEMP/profile.mobileprovision"
security cms -D -i "$RUNNER_TEMP/profile.mobileprovision" > "$RUNNER_TEMP/profile.plist"
uuid=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$RUNNER_TEMP/profile.plist")
profile_team=$(/usr/libexec/PlistBuddy -c 'Print TeamIdentifier:0' "$RUNNER_TEMP/profile.plist")
app_id=$(/usr/libexec/PlistBuddy -c 'Print Entitlements:application-identifier' "$RUNNER_TEMP/profile.plist")
[[ "$profile_team" == "$TEAM" ]] || { echo 'Profile team does not match IOS_TEAM_ID'; exit 1; }
[[ "$app_id" == "$TEAM.$BUNDLE_ID" ]] || { echo 'Use an explicit App ID profile matching IOS_BUNDLE_ID'; exit 1; }
password=$(openssl rand -hex 24)
keychain="$RUNNER_TEMP/pitchee.keychain-db"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$RUNNER_TEMP/certificate.p12" -P "$CERT_PASSWORD" -A -t cert -f pkcs12 -k "$keychain"
security set-key-partition-list -S apple-tool:,apple: -k "$password" "$keychain"
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
identity=$(security find-identity -v -p codesigning "$keychain" | sed -n 's/.*"\(.*\)".*/\1/p' | head -1)
[[ -n "$identity" ]] || { echo 'No valid signing identity in certificate'; exit 1; }
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$RUNNER_TEMP/profile.mobileprovision" "$HOME/Library/MobileDevice/Provisioning Profiles/$uuid.mobileprovision"
echo "PROFILE_UUID=$uuid" >> "$GITHUB_ENV"
echo "SIGNING_IDENTITY=$identity" >> "$GITHUB_ENV"
export PROFILE_UUID="$uuid"
python3 - <<'PY'
import os, plistlib
with open('build/ExportOptions.plist', 'wb') as f:
    plistlib.dump(dict(method=os.environ['EXPORT_METHOD'], teamID=os.environ['TEAM'],
                      signingStyle='manual', provisioningProfiles={os.environ['BUNDLE_ID']: os.environ['PROFILE_UUID']},
                      manageAppVersionAndBuildNumber=False), f)
PY

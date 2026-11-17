#!/usr/bin/env bash
# Host a built IPA on GitHub: upload it to this repository's Releases and point
# the SideStore/AltStore source (docs/source.json) at the uploaded file.
#
#   GH_TOKEN=github_pat_… Tools/publish-ipa.sh Outputs/IPAS/Iayxify-6.7.0-9.1.0.ipa
#
# The token needs "Contents: read and write" on the repository
# (GitHub → Settings → Developer settings → Personal access tokens).
#
# Options:
#   --repo owner/name   repository to publish to (default: the `iba` remote,
#                       falling back to iba2222/spotiffuyyyy)
#   --remote NAME       git remote holding docs/source.json (default: whichever
#                       remote points at --repo, else `origin`)
#   --tag TAG           release tag (default: v<tweak version>-<spotify version>)
#   --notes TEXT        release notes text
#   --no-commit         upload only; leave docs/source.json untouched
#   --no-push           commit docs/source.json but do not push it
#
# Runs on the macOS CI runner too — it is how the build workflow publishes.

set -euo pipefail

DEFAULT_REPO="iba2222/spotiffuyyyy"
PAGES_BASE="https://iba2222.github.io/spotiffuyyyy"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

IPA=""
REPO=""
REMOTE=""
TAG=""
NOTES=""
COMMIT=1
PUSH=1

die() { printf '\033[1;31m==> %s\033[0m\n' "$*" >&2; exit 1; }
say() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }

usage() { sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)      REPO="${2:-}"; shift 2 ;;
        --remote)    REMOTE="${2:-}"; shift 2 ;;
        --tag)       TAG="${2:-}"; shift 2 ;;
        --notes)     NOTES="${2:-}"; shift 2 ;;
        --no-commit) COMMIT=0; shift ;;
        --no-push)   PUSH=0; shift ;;
        -h|--help)   usage; exit 0 ;;
        -*)          die "unknown option: $1" ;;
        *)           IPA="$1"; shift ;;
    esac
done

[ -n "$IPA" ] || { usage; exit 1; }
[ -f "$IPA" ] || die "IPA not found: $IPA"
case "$IPA" in *.ipa) ;; *) die "not an .ipa: $IPA" ;; esac

if [ -z "$REPO" ]; then
    REPO=$(git remote get-url iba 2>/dev/null \
        | sed -E 's|.*github\.com[:/]([^/]+/[^/.]+)(\.git)?$|\1|') || REPO=""
    [ -n "$REPO" ] || REPO="$DEFAULT_REPO"
fi

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
[ -n "$TOKEN" ] || die "set GH_TOKEN (a token with Contents: read and write) and run again"

# The commit that refreshes docs/source.json has to land on the remote this
# repository lives on, not whatever `origin` happens to be.
if [ -z "$REMOTE" ]; then
    for candidate in $(git remote); do
        case "$(git remote get-url "$candidate" 2>/dev/null)" in
            *"$REPO"*) REMOTE="$candidate"; break ;;
        esac
    done
    [ -n "$REMOTE" ] || REMOTE="origin"
fi

BASE_NAME=$(basename "$IPA" .ipa)
# Iayxify-6.7.0-9.1.0[-anything].ipa -> 6.7.0 / 9.1.0
if [[ "$BASE_NAME" =~ ^Iayxify-([0-9][^-]*)-([0-9][^-]*) ]]; then
    TWEAK_VERSION="${BASH_REMATCH[1]}"
    SPOT_VERSION="${BASH_REMATCH[2]}"
else
    TWEAK_VERSION=$(grep -E '^Version:' control | awk '{print $2}')
    SPOT_VERSION="unknown"
fi
[ -n "$TAG" ] || TAG="v${TWEAK_VERSION}-${SPOT_VERSION}"

FILE_NAME=$(basename "$IPA")
SIZE=$(wc -c < "$IPA" | tr -d ' ')
SHA=$(sha256sum "$IPA" | awk '{print $1}')
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
[ -n "$NOTES" ] || NOTES="Iayxify ${TWEAK_VERSION} on Spotify ${SPOT_VERSION}."

API="https://api.github.com/repos/${REPO}"
AUTH=(-H "Authorization: Bearer ${TOKEN}" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

# ── 1. Find or create the release ────────────────────────────────────────────
say "Release ${TAG} in ${REPO}"
RELEASE_JSON=$(curl -sS --max-time 60 "${AUTH[@]}" "${API}/releases/tags/${TAG}" || true)

if printf '%s' "$RELEASE_JSON" | grep -q '"tag_name"'; then
    say "Release already exists, reusing it"
else
    say "Creating release"
    RELEASE_JSON=$(curl -sS --max-time 60 -X POST "${AUTH[@]}" \
        -H "Content-Type: application/json" \
        "${API}/releases" \
        -d "{\"tag_name\":\"${TAG}\",\"name\":\"Iayxify ${TWEAK_VERSION} - Spotify ${SPOT_VERSION}\",\"body\":\"$(json_escape "$NOTES")\",\"draft\":false,\"prerelease\":false}")
    printf '%s' "$RELEASE_JSON" | grep -q '"tag_name"' \
        || die "could not create release: ${RELEASE_JSON}"
fi

# The API pretty-prints its JSON, so the colon is followed by a space.
RELEASE_ID=$(printf '%s' "$RELEASE_JSON" | grep -o '"id": *[0-9]\+' | head -1 | tr -cd '0-9')
[ -n "$RELEASE_ID" ] || die "could not read release id from: ${RELEASE_JSON}"

# ── 2. Upload the IPA ────────────────────────────────────────────────────────
upload_asset() {
    local name="$1"
    curl -sS --max-time 900 -o /dev/null -w '%{http_code}' \
        -X POST "${AUTH[@]}" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@${IPA}" \
        "https://uploads.github.com/repos/${REPO}/releases/${RELEASE_ID}/assets?name=${name}"
}

say "Uploading ${FILE_NAME} (${SIZE} bytes)"
CODE=$(upload_asset "$FILE_NAME" || echo "000")
if [ "$CODE" != "201" ]; then
    # Same name already on the release: keep both instead of overwriting.
    SUFFIX=$(date -u +%Y%m%d-%H%M%S)
    FILE_NAME="${BASE_NAME}-${SUFFIX}.ipa"
    say "Asset already present (HTTP ${CODE}), uploading as ${FILE_NAME}"
    CODE=$(upload_asset "$FILE_NAME" || echo "000")
    [ "$CODE" = "201" ] || die "upload failed (HTTP ${CODE})"
fi

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${FILE_NAME}"
say "Published: ${DOWNLOAD_URL}"

# ── 3. Point the AltStore/SideStore source at the new build ──────────────────
if [ "$COMMIT" -eq 1 ]; then
    say "Updating docs/source.json"
    mkdir -p docs
    cat > docs/source.json <<EOF
{
  "name": "Iayxify",
  "identifier": "com.iayxify.source",
  "subtitle": "Spotify with Premium unlocked",
  "description": "IPA builds of Iayxify, a Spotify tweak. Every build is unsigned; SideStore or AltStore sign it with your own Apple ID when you install it.",
  "iconURL": "${PAGES_BASE}/icon.png",
  "headerURL": "${PAGES_BASE}/icon.png",
  "website": "${PAGES_BASE}/",
  "tintColor": "#1ED760",
  "featuredApps": [
    "com.spotify.client"
  ],
  "apps": [
    {
      "name": "Iayxify",
      "bundleIdentifier": "com.spotify.client",
      "developerName": "iayxify",
      "subtitle": "Spotify with Premium unlocked",
      "localizedDescription": "Spotify ${SPOT_VERSION} with the Iayxify tweak (${TWEAK_VERSION}) injected: Premium features unlocked, theming, and the usual lyric and download extras. Installing replaces the Spotify app on the device.",
      "iconURL": "${PAGES_BASE}/icon.png",
      "tintColor": "#1ED760",
      "category": "utilities",
      "versions": [
        {
          "version": "${TWEAK_VERSION}",
          "buildVersion": "${SPOT_VERSION}",
          "date": "${DATE}",
          "downloadURL": "${DOWNLOAD_URL}",
          "localizedDescription": "Iayxify ${TWEAK_VERSION} on Spotify ${SPOT_VERSION}.",
          "size": ${SIZE},
          "minOSVersion": "15.0"
        }
      ],
      "appPermissions": {
        "entitlements": [],
        "privacy": {}
      }
    }
  ],
  "news": []
}
EOF

    git add docs/source.json
    if git diff --cached --quiet; then
        say "docs/source.json already up to date"
    else
        git -c user.name="iayxify release bot" \
            -c user.email="iayxify@users.noreply.github.com" \
            commit -m "Point the install source at ${FILE_NAME}" >/dev/null
        say "Committed docs/source.json"

        BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        if [ "$PUSH" -eq 1 ] && [ -n "$BRANCH" ] && [ "$BRANCH" != "HEAD" ]; then
            git push "$REMOTE" "HEAD:${BRANCH}" || say "push failed — push manually to update the install page"
        else
            say "Left the commit local (push it to update the SideStore source)"
        fi
    fi
fi

say "Done"
printf '  IPA     %s\n  Source  %s/source.json\n  sha256  %s\n' "$DOWNLOAD_URL" "$PAGES_BASE" "$SHA"

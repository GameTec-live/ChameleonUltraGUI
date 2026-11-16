# Picks the marketing version (CFBundleShortVersionString) for the next Apple
# build from `app-store-connect apps app-store-versions --json` output.
#
# External TestFlight testers only need Apple's beta review for the first build
# of each version; later builds of an approved version are cleared on their own.
# So builds reuse the version that is still open on the App Store, and the patch
# number only moves on once that version has been approved. $floor (the pubspec
# version) lets a manual major/minor bump take over.
#
# Usage: jq -er --arg floor 1.4.0 -f app-store-version.jq versions.json
def semver: split(".") | map(tonumber) | (. + [0, 0, 0])[:3];

map(.attributes) as $versions
| [$versions[] | select(.appVersionState | IN(
    "PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW",
    "REJECTED", "METADATA_REJECTED", "DEVELOPER_REJECTED", "INVALID_BINARY"
  ))] as $open
| if ($open | length) > 1 then error("Expected at most one open App Store version") else . end
| [
    ($floor | semver),
    if $open == [] then $versions | map(.versionString | semver) | max // empty | .[2] += 1
    else $open[0].versionString | semver end
  ]
| max | map(tostring) | join(".")

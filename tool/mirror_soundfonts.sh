#!/usr/bin/env bash
#
# Mirror the auto-download SoundFont catalog to a GitHub release WE control, so
# `bin/rendersong.dart --sf2 <id>` pulls from a host we own — for reliability
# (upstream mirrors rot: the original catalog's archive.org URL vanished) and
# licence-hosting hygiene (we ship each font next to its licence file).
#
# Only VERIFIED-PERMISSIVE fonts are mirrored (matching lib/core/audio/sf2/
# soundfont_store.dart). The original Frank-Wen FluidR3 is deliberately EXCLUDED
# — its own readme is "All Rights Reserved … you may not redistribute" — so we
# mirror the MIT re-releases (FluidR3Mono, MuseScore_General) instead.
#
# Assets are named "<id>.<ext>" — exactly what SoundFontStore.urlFor() expects
# under COMET_SOUNDFONT_MIRROR.
#
#   REPO=CrispStrobe/soundfonts TAG=v1 tool/mirror_soundfonts.sh
#   # then run the printed `gh release create …`, and:
#   export COMET_SOUNDFONT_MIRROR=https://github.com/$REPO/releases/download/$TAG
#
set -euo pipefail
REPO="${REPO:-CrispStrobe/soundfonts}"
TAG="${TAG:-v1}"
DIR="${DIR:-/tmp/cometbeat-sf-mirror}"
mkdir -p "$DIR"; cd "$DIR"

# id | ext | url | licence
fonts=(
  "generaluser_gs|sf2|https://github.com/mrbumpy409/GeneralUser-GS/raw/main/GeneralUser-GS.sf2|GeneralUser GS License v2.0 (permissive: private/commercial use + redistribution + modification)"
  "fluidr3mono|sf3|https://github.com/musescore/MuseScore/raw/2.1/share/sound/FluidR3Mono_GM.sf3|MIT (Michael Cowgill, from Frank Wen's FluidR3)"
  "musescore_general_sf3|sf3|https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/MuseScore_General.sf3|MIT (S. Christian Collins)"
  "musescore_general|sf2|https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/MuseScore_General.sf2|MIT (S. Christian Collins)"
)

assets=()
for row in "${fonts[@]}"; do
  IFS='|' read -r id ext url note <<<"$row"
  out="$id.$ext"
  echo "→ $out  — $note"
  curl -fSL --retry 3 -o "$out" "$url"
  # every .sf2/.sf3 is a RIFF container — reject an HTML error page masquerading.
  head -c4 "$out" | grep -q RIFF || { echo "!! $out is not RIFF (bad download)"; exit 1; }
  assets+=("$DIR/$out")
done

# Ship the licence texts alongside the banks.
curl -fSL -o GeneralUser-GS-LICENSE.txt \
  "https://raw.githubusercontent.com/mrbumpy409/GeneralUser-GS/main/documentation/LICENSE.txt"
curl -fSL -o MuseScore_General-LICENSE.md \
  "https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/MuseScore_General_License.md"
assets+=("$DIR/GeneralUser-GS-LICENSE.txt" "$DIR/MuseScore_General-LICENSE.md")

echo
echo "Downloaded to $DIR. Create the release (review first — this publishes to $REPO):"
echo
echo "  gh release create $TAG -R $REPO \\"
echo "    -t 'Permissive General-MIDI SoundFonts (CometBeat mirror)' \\"
echo "    -n 'Verified-permissive GM banks mirrored for CometBeat auto-download. Licences in the *-LICENSE.* assets.' \\"
for a in "${assets[@]}"; do echo "    '$a' \\"; done | sed '$ s/ \\$//'
echo
echo "Then point the CLI at it:"
echo "  export COMET_SOUNDFONT_MIRROR=https://github.com/$REPO/releases/download/$TAG"

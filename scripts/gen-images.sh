#!/usr/bin/env bash
# Generate landing imagery for the B2B brand site via Replicate
# google/nano-banana. Idempotent: skips existing webp files (jpgs are
# converted to webp and deleted). Usage: REPLICATE_API_KEY=... ./scripts/gen-images.sh
set -u
KEY=$(printf %s "${REPLICATE_API_KEY:-${REPLICATE_TOKEN:?REPLICATE_API_KEY not set}}" | tr -d '[:space:]')
DEST="$(cd "$(dirname "$0")/.." && pwd)/public/images"
mkdir -p "$DEST"

STYLE="Photorealistic, editorial quality, professional photography, cool restrained color grade with slate blue and cobalt accents, shallow depth of field. No text, no logos, no watermarks, no readable writing anywhere."

gen() {
  local slug=$1 aspect=$2 prompt=$3 dest="$DEST/$1.jpg"
  { [ -s "$dest" ] || [ -s "$DEST/$slug.webp" ]; } && { echo "[$slug] exists, skip"; return 0; }
  local body
  body=$(jq -n --arg p "$prompt $STYLE" --arg ar "$aspect" \
    '{input:{prompt:$p, aspect_ratio:$ar, output_format:"jpg"}}')
  for attempt in 1 2 3; do
    local resp url
    resp=$(printf %s "$body" | curl -s -X POST "https://api.replicate.com/v1/models/google/nano-banana/predictions" \
      -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
      -H "Prefer: wait" --data-binary @-)
    url=$(echo "$resp" | jq -r 'if (.output|type)=="array" then .output[0] else .output end // empty')
    if [ -n "$url" ]; then
      curl -s -o "$dest" "$url" && echo "[$slug] done ($(stat -c%s "$dest") bytes)" && return 0
    fi
    echo "[$slug] attempt $attempt failed: $(echo "$resp" | jq -r '.error // .status // "unknown"' | head -c 160)"
    sleep 5
  done
  echo "[$slug] FAILED"; return 1
}

gen hero-workshop "21:9" "A brand strategy workshop in a bright modern studio at golden-blue morning hour: a long oak table with large printed wordless color and typography specimen boards laid out in a neat grid, three professionals standing around it in mid-discussion seen from behind at a distance, one huge window with cool daylight, a deep cobalt-blue wall panel, cinematic wide composition."
gen identity-detail "4:3" "Close still life of a corporate identity system: blind-embossed blank marks on thick cotton paper, stacked business cards with a wordless geometric symbol, a navy portfolio box and a cobalt fabric swatch, raking cool light, macro editorial photography, no people."
gen system-grid "4:3" "A large wall of neatly pinned wordless brand system boards: blank grids, color chips in slate and cobalt, spacing diagrams drawn as simple lines, photography crop frames, viewed straight-on in soft even studio light, no people."
gen strategy-room "4:3" "A glass-walled meeting room in a calm office: two professionals reviewing large printed wordless charts at a standing table, cool northern daylight, a cobalt-blue chair as the single color accent, documentary editorial photography, shallow depth of field."

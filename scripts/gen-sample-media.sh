#!/usr/bin/env bash
# Generate the Astrid Berg sample-kit media via Replicate: same-person
# headshots and a film poster from the existing portrait (google/nano-banana
# with image_input), fictional project stills, and an 8s brand-film clip
# (alibaba/happyhorse-1.0 text-to-video).
# Idempotent: skips existing files. Convert jpg -> webp afterward (sharp).
# Usage: REPLICATE_API_KEY=... ./scripts/gen-sample-media.sh
set -u
KEY=$(printf %s "${REPLICATE_API_KEY:-${REPLICATE_TOKEN:?REPLICATE_API_KEY not set}}" | tr -d '[:space:]')
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMG="$ROOT/public/images"
MEDIA="$ROOT/public/media"
REF="$IMG/portrait-architect.webp"

STYLE="Photorealistic, editorial quality, professional photography, rich but restrained Nordic color grade, shallow depth of field. No text, no logos, no watermarks, no readable writing."
SAME="The exact same woman as in the reference photo: a Scandinavian architect in her early 40s with long blonde hair, identical face and features, wearing dark clothing."
VIDEO_VER="d867e39d045d6449a05b8dd3bc10ea3acca69b99aebc34b831809c09cd523527"  # alibaba/happyhorse-1.0

# The data URI is ~130KB — far past ARG_MAX for --arg, so it goes through
# a temp file and jq --rawfile.
REF_B64=$(mktemp)
{ printf 'data:image/webp;base64,'; base64 -w0 "$REF"; } > "$REF_B64"
trap 'rm -f "$REF_B64"' EXIT

gen() { # slug aspect use_ref prompt
  local slug=$1 aspect=$2 use_ref=$3 prompt=$4 dest="$IMG/$1.jpg" body
  [ -s "$dest" ] && { echo "[$slug] exists, skip"; return 0; }
  if [ "$use_ref" = ref ]; then
    body=$(jq -n --arg p "$prompt $STYLE" --arg ar "$aspect" --rawfile r "$REF_B64" \
      '{input:{prompt:$p, aspect_ratio:$ar, output_format:"jpg", image_input:[$r]}}')
  else
    body=$(jq -n --arg p "$prompt $STYLE" --arg ar "$aspect" \
      '{input:{prompt:$p, aspect_ratio:$ar, output_format:"jpg"}}')
  fi
  for attempt in 1 2 3; do
    local resp url
    resp=$(printf %s "$body" | curl -s -X POST "https://api.replicate.com/v1/models/google/nano-banana/predictions" \
      -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
      -H "Prefer: wait" --data-binary @-)
    url=$(echo "$resp" | jq -r 'if (.output|type)=="array" then .output[0] else .output end // empty')
    if [ -n "$url" ]; then
      curl -s -o "$dest" "$url" && echo "[$slug] done ($(stat -c%s "$dest") bytes)" && return 0
    fi
    echo "[$slug] attempt $attempt failed: $(echo "$resp" | jq -r '.error // .status // "unknown"' | head -c 200)"
    sleep 5
  done
  echo "[$slug] FAILED"; return 1
}

# --- brand film: submit first, poll after the stills ---------------------
FILM="$MEDIA/astrid-film.mp4"
FILM_ID=""
if [ -s "$FILM" ]; then echo "[astrid-film] exists, skip"; else
  FILM_PROMPT="Cinematic documentary film, photorealistic, ultra-high-definition, shallow depth of field, editorial quality, warm restrained Nordic color grade, subtle film grain. A Scandinavian female architect in her early 40s with long blonde hair, wearing a fine black sweater, working alone in a calm concrete-and-oak studio in Copenhagen: she leans over a large pale-wood architectural model of courtyard housing, adjusts a tiny timber block, then looks up toward tall industrial windows with soft harbor light, thinking. Slow gentle push-in camera, dust motes in the light, plants at the window. Her face stays sharp and consistent throughout, natural candid energy, nobody else in frame. No text, no logos, no readable writing anywhere."
  RESP=$(jq -n --arg v "$VIDEO_VER" --arg p "$FILM_PROMPT" \
    '{version:$v, input:{prompt:$p, duration:8, resolution:"1080p", aspect_ratio:"16:9"}}' |
    curl -sS -X POST "https://api.replicate.com/v1/predictions" \
      -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" --data-binary @-)
  FILM_ID=$(jq -r '.id // empty' <<<"$RESP")
  [ -n "$FILM_ID" ] && echo "[astrid-film] submitted ($FILM_ID)" \
    || echo "[astrid-film] submit failed: $(jq -rc '.detail // .error // .' <<<"$RESP" | head -c 200)"
fi

# --- headshot set (same person via reference) ----------------------------
gen headshot-press "3:4" ref "$SAME A formal press headshot: head and shoulders, facing camera with a calm confident expression, seamless dark charcoal studio backdrop, dramatic soft key light, black fine-knit sweater."
gen headshot-speaker "4:5" ref "$SAME Speaking on a conference stage, mid-gesture at waist height, warm stage light against a deep neutral background softly out of focus, dark blazer over black top, candid documentary angle from slightly below."
gen headshot-editorial "4:5" ref "$SAME An environmental editorial portrait outdoors at a construction site by the Copenhagen harbor on an overcast day, wearing a long dark wool coat, wind in her hair, holding rolled drawings, low-rise timber housing scaffolding softly blurred behind."

# --- fictional project stills --------------------------------------------
gen project-koge "4:3" none "Danish courtyard housing at golden hour: a calm residential courtyard enclosed by three-storey limewashed buildings in warm off-white, timber window frames, young birch trees and bicycles in the courtyard, long soft shadows, architectural photography, no people."
gen project-limewash "4:3" none "A quiet row of Danish terraced houses with pale limewash facades and oak doors, morning light raking across the textured plaster, small front gardens with wild grasses, overcast-to-sun sky, architectural photography, straight-on elevation, no people."
gen project-harbor "4:3" none "Scandinavian waterside apartment buildings in pale brick and oak, stepping gently down toward calm water, a wooden boardwalk in the foreground, soft morning light, gentle reflections, architectural photography, no people."

# --- film poster (same person, matches the film scene) -------------------
gen astrid-film-poster "16:9" ref "$SAME A cinematic film still: she leans over a large pale-wood architectural model in a concrete-and-oak Copenhagen studio, adjusting a tiny timber block, tall industrial windows with soft harbor light behind her, dust motes in the light."

# --- poll the film --------------------------------------------------------
if [ -n "$FILM_ID" ]; then
  for i in $(seq 1 60); do
    RESP=$(curl -s -H "Authorization: Bearer $KEY" "https://api.replicate.com/v1/predictions/$FILM_ID")
    ST=$(jq -r .status <<<"$RESP")
    if [ "$ST" = succeeded ]; then
      URL=$(jq -r 'if (.output|type)=="array" then .output[0] else .output end' <<<"$RESP")
      curl -s -o "$FILM" "$URL" && echo "[astrid-film] done ($(stat -c%s "$FILM") bytes)"
      break
    elif [ "$ST" = failed ] || [ "$ST" = canceled ]; then
      echo "[astrid-film] $ST: $(jq -rc '.error // empty' <<<"$RESP" | head -c 200)"; break
    fi
    echo "[astrid-film] $ST ($((i*10))s)"; sleep 10
  done
fi

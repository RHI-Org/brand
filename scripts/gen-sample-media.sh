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
# The "before" shots must look like what a client actually uploads — an
# amateur phone snapshot, deliberately NOT the editorial style above.
RAW="Authentic amateur smartphone snapshot, unedited, flat mediocre indoor lighting, slightly awkward framing with too much headroom, everyday realistic phone-camera quality, mundane setting. Photorealistic. No text, no logos, no watermarks, no readable writing."
SAME="The exact same woman as in the reference photo: a Scandinavian architect in her early 40s with long blonde hair, identical face and features, wearing dark clothing."
VIDEO_VER="d867e39d045d6449a05b8dd3bc10ea3acca69b99aebc34b831809c09cd523527"  # alibaba/happyhorse-1.0

# The data URIs are ~130KB — far past ARG_MAX for --arg, so they go through
# temp files and jq --rawfile. One reference per sample client; gen() reads
# whichever CURREF points at.
mkb64(){ local f; f=$(mktemp); { printf 'data:image/webp;base64,'; base64 -w0 "$1"; } > "$f"; printf %s "$f"; }
REF_B64=$(mkb64 "$REF")
REF_B64_F=$(mkb64 "$IMG/portrait-founder.webp")
REF_B64_C=$(mkb64 "$IMG/portrait-chef.webp")
CURREF=$REF_B64
trap 'rm -f "$REF_B64" "$REF_B64_F" "$REF_B64_C"' EXIT

gen() { # slug aspect use_ref(ref|refraw|none) prompt
  local slug=$1 aspect=$2 use_ref=$3 prompt=$4 dest="$IMG/$1.jpg" body sty="$STYLE"
  [ "$use_ref" = refraw ] && sty="$RAW"
  # The jpg is converted to webp and deleted after generation, so treat an
  # existing webp as done too — otherwise every re-run re-shoots everything.
  { [ -s "$dest" ] || [ -s "$IMG/$slug.webp" ]; } && { echo "[$slug] exists, skip"; return 0; }
  if [ "$use_ref" = ref ] || [ "$use_ref" = refraw ]; then
    body=$(jq -n --arg p "$prompt $sty" --arg ar "$aspect" --rawfile r "$CURREF" \
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

# --- brand films: submit first, poll after the stills --------------------
FILM_STYLE="Cinematic documentary film, photorealistic, ultra-high-definition, shallow depth of field, editorial quality, subtle film grain. Face stays sharp and consistent throughout, natural candid energy, nobody else in frame. No text, no logos, no readable writing anywhere."
declare -A FILM_PROMPTS FILM_IDS
FILM_PROMPTS[astrid-film]="Warm restrained Nordic color grade. A Scandinavian female architect in her early 40s with long blonde hair, wearing a fine black sweater, working alone in a calm concrete-and-oak studio in Copenhagen: she leans over a large pale-wood architectural model of courtyard housing, adjusts a tiny timber block, then looks up toward tall industrial windows with soft harbor light, thinking. Slow gentle push-in camera, dust motes in the light, plants at the window. $FILM_STYLE"
FILM_PROMPTS[amara-film]="Clean gallery-white color grade with one cobalt accent. A Black female technology founder in her late 30s with natural curly hair in an elegant updo, wearing a long navy coat over a white silk blouse, walking slowly and confidently through a bright gallery-like office corridor past a huge abstract cobalt-blue painting, pausing to look toward a skylight, composed and thoughtful. Slow lateral tracking camera. $FILM_STYLE"
FILM_PROMPTS[mateo-film]="Warm ember-lit color grade. A Mediterranean male chef in his mid 40s with dark curly hair and a salt-and-pepper beard, linen apron over dark workwear, alone at the pass of a modern rustic kitchen at dusk: he plates a seasonal dish with tweezers, wipes the rim, steam rising through warm side light, then looks up satisfied toward the open flame grill. Slow gentle push-in camera, embers glowing behind. $FILM_STYLE"
for f in astrid-film amara-film mateo-film; do
  if [ -s "$MEDIA/$f.mp4" ]; then echo "[$f] exists, skip"; continue; fi
  RESP=$(jq -n --arg v "$VIDEO_VER" --arg p "${FILM_PROMPTS[$f]}" \
    '{version:$v, input:{prompt:$p, duration:8, resolution:"1080p", aspect_ratio:"16:9"}}' |
    curl -sS -X POST "https://api.replicate.com/v1/predictions" \
      -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" --data-binary @-)
  FILM_IDS[$f]=$(jq -r '.id // empty' <<<"$RESP")
  [ -n "${FILM_IDS[$f]}" ] && echo "[$f] submitted (${FILM_IDS[$f]})" \
    || echo "[$f] submit failed: $(jq -rc '.detail // .error // .' <<<"$RESP" | head -c 200)"
done

# --- headshot set (same person via reference) ----------------------------
gen headshot-press "3:4" ref "$SAME A formal press headshot: head and shoulders, facing camera with a calm confident expression, seamless dark charcoal studio backdrop, dramatic soft key light, black fine-knit sweater."
gen headshot-speaker "4:5" ref "$SAME Speaking on a conference stage, mid-gesture at waist height, warm stage light against a deep neutral background softly out of focus, dark blazer over black top, candid documentary angle from slightly below."
gen headshot-editorial "4:5" ref "$SAME An environmental editorial portrait outdoors at a construction site by the Copenhagen harbor on an overcast day, wearing a long dark wool coat, wind in her hair, holding rolled drawings, low-rise timber housing scaffolding softly blurred behind."

# --- fictional project stills --------------------------------------------
gen project-koge "4:3" none "Danish courtyard housing at golden hour: a calm residential courtyard enclosed by three-storey limewashed buildings in warm off-white, timber window frames, young birch trees and bicycles in the courtyard, long soft shadows, architectural photography, no people."
gen project-limewash "4:3" none "A quiet row of Danish terraced houses with pale limewash facades and oak doors, morning light raking across the textured plaster, small front gardens with wild grasses, overcast-to-sun sky, architectural photography, straight-on elevation, no people."
gen project-harbor "4:3" none "Scandinavian waterside apartment buildings in pale brick and oak, stepping gently down toward calm water, a wooden boardwalk in the foreground, soft morning light, gentle reflections, architectural photography, no people."

# --- "before" client uploads (same person, deliberately amateur) ---------
gen before-snap-1 "3:4" refraw "The exact same woman as in the reference photo, identical face: a casual snapshot taken by a friend at a kitchen table at home, gray sweater, coffee mug nearby, plain wall and cluttered counter behind, mild motion blur, ordinary and unflattering but friendly."
gen before-snap-2 "4:3" refraw "The exact same woman as in the reference photo, identical face: an amateur outdoor snapshot on an overcast street, practical rain jacket, squinting slightly, distracting parked bicycles and a bin in the background, centered tourist-photo composition."

# --- film poster (same person, matches the film scene) -------------------
gen astrid-film "16:9" ref "$SAME A cinematic film still: she leans over a large pale-wood architectural model in a concrete-and-oak Copenhagen studio, adjusting a tiny timber block, tall industrial windows with soft harbor light behind her, dust motes in the light."

# --- client: Amara Osei, technology founder (reference: portrait-founder) --
SAMEF="The exact same woman as in the reference photo: a Black female technology founder in her late 30s with natural curly hair in an elegant updo, identical face and features, refined dark tailoring."
CURREF=$REF_B64_F
gen f-headshot-press "3:4" ref "$SAMEF A formal press headshot: head and shoulders, facing camera with calm authority, seamless dark charcoal studio backdrop, dramatic soft key light, navy blazer over a white silk blouse."
gen f-headshot-speaker "4:5" ref "$SAMEF Speaking on a minimal conference stage, mid-gesture at waist height, warm stage light against a deep neutral background softly out of focus, candid documentary angle from slightly below."
gen f-headshot-editorial "4:5" ref "$SAMEF An environmental editorial portrait in a bright gallery-like office atrium with a skylight, standing relaxed with hands loosely folded, a large abstract cobalt-blue painting softly blurred behind."
gen f-before-1 "3:4" refraw "The exact same woman as in the reference photo, identical face: a casual snapshot taken by a coworker at a cluttered office desk, two monitors and coffee cups behind, flat fluorescent light, mid-laugh, slightly unflattering angle."
gen f-before-2 "4:3" refraw "The exact same woman as in the reference photo, identical face: an amateur outdoor snapshot on a gray London street, practical puffer jacket, squinting slightly, holding a takeaway cup, distracting road works and cones in the background, centered composition."
gen f-project-1 "4:3" none "A bright minimal technology office interior with glass meeting rooms and long oak tables, morning light through tall windows, one abstract cobalt-blue artwork on a white wall, no people."
gen f-project-2 "4:3" none "A quiet corner of a design studio: pale oak shelving with ceramic vessels and a small olive plant, a large abstract cobalt-blue canvas leaning against the wall, soft diffuse window light, interior editorial photography, no people."
gen f-project-3 "4:3" none "A minimal empty conference stage bathed in warm amber light, a single wooden lectern under a soft spotlight, dark velvet curtain behind, cinematic, no people, no readable text anywhere."
gen amara-film "16:9" ref "$SAMEF A cinematic film still: walking slowly through a bright gallery-white office corridor past a huge abstract cobalt-blue painting, long navy coat, composed and thoughtful, skylight glow."

# --- client: Mateo Ferrer, chef (reference: portrait-chef) -----------------
SAMEC="The exact same man as in the reference photo: a Mediterranean chef in his mid 40s with dark curly hair and a salt-and-pepper beard, identical face and features, natural linen apron over dark workwear."
CURREF=$REF_B64_C
gen c-headshot-press "3:4" ref "$SAMEC A formal press headshot: head and shoulders, facing camera with a warm settled expression, seamless dark charcoal studio backdrop, dramatic soft key light."
gen c-headshot-speaker "4:5" ref "$SAMEC Talking to a small unseen audience across a chef's-table counter, mid-gesture with open hands, warm tungsten kitchen light, copper pans softly blurred behind, candid documentary angle."
gen c-headshot-editorial "4:5" ref "$SAMEC An environmental editorial portrait at a morning produce market, holding a wooden crate of vegetables, overcast soft light, market awnings and crates softly blurred behind."
gen c-before-1 "3:4" refraw "The exact same man as in the reference photo, identical face: a casual snapshot taken by a colleague in a cramped busy stainless-steel kitchen, harsh overhead fluorescent light, towel over shoulder, caught mid-sentence."
gen c-before-2 "4:3" refraw "The exact same man as in the reference photo, identical face: an amateur snapshot on a sunny sidewalk terrace, squinting in bright midday light, stacked cafe chairs and a bicycle in the background, awkward centered tourist-photo composition."
gen c-project-1 "4:3" none "A warm rustic-modern restaurant dining room at dusk, empty, candlelight on small oak tables, limewashed walls and ceramic pendants, embers visible in an open kitchen beyond, no people."
gen c-project-2 "4:3" none "A plated seasonal dish on hand-thrown ceramic: charred leeks, herb oil and flowers, dark oak table, single warm side light, fine-dining photography, no text."
gen c-project-3 "4:3" none "An open flame grill with glowing embers and gentle sparks in a modern rustic kitchen, cast-iron grate, dramatic warm light, shallow depth of field, no people."
gen mateo-film "16:9" ref "$SAMEC A cinematic film still: plating a seasonal dish with tweezers at the pass of a modern rustic kitchen at dusk, steam rising through warm side light, embers glowing behind."
CURREF=$REF_B64

# --- poll the films -------------------------------------------------------
for f in astrid-film amara-film mateo-film; do
  ID=${FILM_IDS[$f]:-}
  [ -n "$ID" ] || continue
  for i in $(seq 1 60); do
    RESP=$(curl -s -H "Authorization: Bearer $KEY" "https://api.replicate.com/v1/predictions/$ID")
    ST=$(jq -r .status <<<"$RESP")
    if [ "$ST" = succeeded ]; then
      URL=$(jq -r 'if (.output|type)=="array" then .output[0] else .output end' <<<"$RESP")
      curl -s -o "$MEDIA/$f.mp4" "$URL" && echo "[$f] done ($(stat -c%s "$MEDIA/$f.mp4") bytes)"
      break
    elif [ "$ST" = failed ] || [ "$ST" = canceled ]; then
      echo "[$f] $ST: $(jq -rc '.error // empty' <<<"$RESP" | head -c 200)"; break
    fi
    echo "[$f] $ST ($((i*10))s)"; sleep 10
  done
done

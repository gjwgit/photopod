# PhotoPod Face Analyser

A headless Python service that runs on the Solid server and finds the faces
in the photos a PhotoPod user chooses, when they tap **Identify People**. It
works through Pod sharing alone, as HealthPod's blood pressure analyser does:
the user's Pod shares a folder holding those photos with the **Analyser Pod**
(`https://solid.dev.empwr.au/Analyser/profile/card#me`), the service finds the
faces in them and writes the results back into the user's Pod.

- No port, no HTTP interface, nothing the app calls. The service only talks to
  the Solid server it sits beside, logged in as the Analyser.
- It never looks at a user's Pod on a timer. Sharing the folder is the request:
  the server notifies the service the moment it happens (Solid Notifications),
  and the service reads that folder then, and only then.
- Photos move only between the user's Pod and this service on the same
  server, and are decrypted only in its memory.
- Finds and recognises faces with InsightFace's **buffalo_l** models (SCRFD-10GF
  and ArcFace ResNet-50), the set Immich uses, run through ONNX Runtime. See
  [Models and licence](#models-and-licence).
- Lives at `photopod/analyser/face_analyser`, laid out like
  `healthpod/analyser/bp_analyser`.

## Contents

- [How it works](#how-it-works)
- [What PhotoPod does](#what-photopod-does)
- [Preparing the Analyser Pod](#preparing-the-analyser-pod)
- [Installing on the Solid server](#installing-on-the-solid-server)
- [Running it](#running-it)
- [Models and licence](#models-and-licence)
- [Privacy and security](#privacy-and-security)
- [Development](#development)

## How it works

```text
┌──────────────────────────── Solid server ────────────────────────────┐
│                                                                      │
│  Alice's Pod                                                         │
│    photopod/data/<photos, renditions, faces.json>   (not shared)     │
│    photopod/data/.faces-inbox/   while asked: shared with Analyser   │
│        <key>.enc.ttl         a photo, left by PhotoPod               │
│        <key>.faces.enc.ttl   its faces, written by the Analyser      │
│        done                  every photo answered                    │
│              ▲   │                                                   │
│     answer   │   │ read, decrypt                                     │
│              │   ▼                                                   │
│        ┌────────────────────┐        Analyser's Pod                  │
│        │  face_analyser     │ ◄───── photopod/shared/shared-keys.ttl │
│        │  (this service)    │ notified (the inbox's folder key)      │
│        └────────────────────┘                                        │
└──────────────────────────────────────────────────────────────────────┘
```

1. **Asking.** The user selects photos and taps **Identify People**.
   PhotoPod creates `photopod/data/.faces-inbox/` with a folder key of its
   own, leaves the selected photos in it, and only then shares the folder
   with the Analyser for Read and Write (solidpod `grantPermission`, as
   HealthPod shares its blood pressure folder). solidpod seals the folder key
   into the Analyser's `photopod/shared/shared-keys.ttl`.
2. **Hearing.** The service subscribes to that file through the server's
   WebSocketChannel2023 (`notify.py`), so the server tells it at once. It
   reads the file and finds the inbox newly shared, and only that one: an
   inbox it has already answered is not read again until it is shared again.
3. **Analysing.** For each photo waiting there, `<key>.enc.ttl`, it reads and
   decrypts it with the folder key, in memory, and finds the faces.
4. **Answering.** It writes the result beside the photo as
   `<key>.faces.enc.ttl`, encrypted with the same folder key in exactly the
   form solidpod's `writePod(inheritKeyFrom:)` writes, so PhotoPod reads it
   with `readPod()` like any file of its own. Then it removes the photo. Once
   every photo is answered it writes `done`.
5. **Filing.** PhotoPod files each answer in the user's
   `faces.json.enc.ttl` and the catalog, deletes it, and on `done` revokes the
   share and removes the inbox.

Nothing about any user is kept by the Analyser, neither in its Pod nor on this
host. Requests made while the service was stopped are answered when it starts.

### The files in the inbox

`<key>` is the random part of the photo's stored name (32 hex digits), or a
digest of its path for a photo stored before random names. It says nothing
about the photo.

A photo, inside its encryption:

```json
{"format": "photopod-face-request", "version": 1, "image": "<base64 JPEG>"}
```

the 2048 px large rendition, with its EXIF, XMP and IPTC blocks taken out by
PhotoPod first (`withoutMetadata` in `lib/services/face_inbox.dart`), so that
it says nothing of where or when it was taken.

An answer, inside its encryption:

```json
{"format": "photopod-face-result", "version": 1,
 "model": "buffalo_l:scrfd-10g+arcface-w600k-r50", "analysed": "2026-11-10T09:00:00.000+00:00",
 "width": 1054, "height": 1280,
 "faces": [{"box": [0.5403, 0.2819, 0.1801, 0.2101], "score": 0.935,
            "embedding": "<base64 of 512 little-endian float32, unit length>",
            "image": "<base64 96x96 JPEG>"}]}
```

or `"failed": "<why>"` in place of the faces for a photo that could not be
read, which would fail the same way again. A photo the shared key cannot open
is not answered at all, since it is the key and not the photo that is wrong.
`model` must equal `faceModelId` in PhotoPod's `lib/models/face_book.dart`.

The modules `crypto.py`, `turtle.py`, `pod_paths.py`, `solid_client.py` and
`keys.py` are taken from HealthPod's analyser, and `tests/test_crypto.py`
with them: its vectors were generated by solidpod's own Dart libraries, so a
failure there is a compatibility break, not a test to adjust.

## What PhotoPod does

- **Identify People** (the selection toolbar): creates the inbox, leaves the
  selected photos in it, shares it with the Analyser, files the answers as
  they come, and on `done` revokes the share and removes the inbox
  (`lib/services/face_inbox.dart`, `lib/services/people_analyser.dart`).
  Nothing is shared at any other time, and nothing is sent unasked: adding
  photos sends nothing.
- **Entering the Pod**: the user's own `faces.json.enc.ttl` is read as soon as
  the security key is entered. It is the record of every photo already looked
  at.
- **Opening People**: a request cut short, as by the app closing, is finished
  and closed.
- **Filing**: answers are saved to the faces file **before** they are deleted,
  so a crash loses nothing. The people named in each photo are listed in the
  catalog, where Get Info shows them and the filter bar finds them.
- **Deleting a photo** deletes its faces from the faces file, and its photo or
  answer from the inbox if either is still there.
- **Before login**, the sample album uses `assets/demo/faces.json`, worked out
  once with `./run.sh analyse --full` (see [Development](#development)).

## Preparing the Analyser Pod

The same Pod and account as HealthPod's analyser. It needs the **PhotoPod**
folder structure as well as HealthPod's.

1. **Initialise it with PhotoPod.** Log in to PhotoPod as the Analyser account
   **once** and enter its security key. PhotoPod creates
   `Analyser/photopod/encryption/`, `sharing/public-key.ttl`, `shared/` and
   `logs/`. Until then PhotoPod cannot share an inbox with it ("The Analyser
   Pod is not set up for PhotoPod yet"), and `./run.sh check` reports that
   `photopod/encryption/enc-keys.ttl` does not exist. Check with:

   ```bash
   curl -sI \
     https://solid.dev.empwr.au/Analyser/photopod/sharing/public-key.ttl
   ```

2. **Client credentials.** The pair issued for HealthPod's analyser works,
   since both log in as the same WebID. A pair of its own is better, so that
   either can be revoked alone: see `healthpod/analyser/bp_analyser/README.md`,
   section "Issue client credentials", with `"name": "face-analyser"`.

## Installing on the Solid server

Outside the Solid server's storage root (`/opt/solid/server`), for the reasons
given in HealthPod's analyser README: anything under it would become a Pod
resource.

From the PhotoPod folder on your own machine:

```bash
rsync -av --exclude='.venv' --exclude='var' --exclude='config.yaml' \
      --exclude='__pycache__' --exclude='.DS_Store' \
      analyser/face_analyser/ you@solid.dev.empwr.au:/tmp/face_analyser/
```

On the server:

```bash
sudo useradd --system --home /opt/solid/analyser \
    --shell /usr/sbin/nologin photopod
sudo mkdir -p /opt/solid/analyser
sudo rsync -a /tmp/face_analyser/ /opt/solid/analyser/face_analyser/
sudo chown -R photopod:photopod /opt/solid/analyser/face_analyser
sudo -u photopod bash /opt/solid/analyser/face_analyser/setup.sh   # 275 MB of models

sudo cp /opt/solid/analyser/face_analyser/systemd/photopod-face-analyser.env \
        /etc/photopod-face-analyser.env
sudo chmod 600 /etc/photopod-face-analyser.env
sudo nano /etc/photopod-face-analyser.env    # security key, client credentials

sudo systemd-run --pipe --wait -p User=photopod \
    -p EnvironmentFile=/etc/photopod-face-analyser.env \
    -p WorkingDirectory=/opt/solid/analyser/face_analyser \
    /opt/solid/analyser/face_analyser/run.sh check

sudo cp \
    /opt/solid/analyser/face_analyser/systemd/photopod-face-analyser.service \
        /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now photopod-face-analyser
journalctl -u photopod-face-analyser -f
```

No firewall rule, reverse proxy or certificate is needed: the service opens no
port. It needs outbound HTTPS to the Solid server only, plus PyPI and GitHub
while `setup.sh` runs.

### Updating

```bash
sudo systemctl stop photopod-face-analyser
sudo rsync -a /tmp/face_analyser/ /opt/solid/analyser/face_analyser/
sudo chown -R photopod:photopod /opt/solid/analyser/face_analyser
sudo -u photopod bash /opt/solid/analyser/face_analyser/setup.sh
sudo systemctl start photopod-face-analyser
```

`config.yaml` and `/etc/photopod-face-analyser.env` are never overwritten.

## Running it

```bash
./run.sh check                 # models, Analyser Pod, notifications
./run.sh watch                 # what systemd runs: answer requests as made
./run.sh run-once              # answer the requests waiting, then stop
./run.sh run-once WEBID        # answer one Pod's inbox now, asked or not
./run.sh analyse PHOTO...      # the faces in local photos, no Pod involved
./run.sh test                  # the offline test suite
```

Each request answered logs one line, for example
`solid.dev.empwr.au-alice: 3 analysed, 0 failed`. `check` fails when the
server offers no WebSocketChannel2023 subscription, which `watch` needs.

## Models and licence

`./run.sh fetch-models` (run by `setup.sh`) downloads InsightFace's
`buffalo_l.zip` once (275 MB), checks its SHA-256, and keeps the two models
used, each checked again, in `var/models`:

- `det_10g.onnx`: **SCRFD-10GF**, which finds each face and five landmarks
  (eyes, nose tip, corners of the mouth);
- `w600k_r50.onnx`: **ArcFace ResNet-50** trained on WebFace600K, which
  describes each face, aligned by those landmarks to 112 x 112, as 512
  numbers.

They are run directly with ONNX Runtime, following InsightFace's own code,
rather than through the `insightface` package, which needs a C compiler to
install.

On PhotoPod's sample photos it finds every portrait (YuNet, used before,
missed one) and nothing in the landscapes. The same person scores 0.64 to
0.84 and strangers at most 0.07; PhotoPod files faces together at 0.40
(`faceMatchThreshold` in `lib/models/face_book.dart`).

**Licence.** InsightFace's code is MIT, but its pretrained models are released
"for non-commercial research purposes only"
(<https://github.com/deepinsight/insightface#license>). That suits research
use; a commercial deployment needs a licence from InsightFace, or other
models. Changing models means changing `MODEL_ID` in `face_analyser/__init__.py`
and `faceModelId` in PhotoPod, and choosing a new threshold; PhotoPod then
starts every faces file afresh.

## Privacy and security

- **What is shared:** only the face inbox, holding only the photos the user
  selected, without where they were taken, and only once they tap
  **Identify People**. The photos themselves, their renditions, names, albums
  and everything else in PhotoPod stay as private as they were.
- **How long:** the share lasts until the photos are answered, usually
  seconds, and PhotoPod then revokes it and removes the inbox.
- **When:** the service reads a user's Pod only when notified that the user
  has just shared their inbox. It never looks on a timer.
- **Where:** everything happens on the Solid server's host. Photos are
  decrypted only in this process's memory, never written to disk and never
  logged; the log records how many photos each request held.
- **No exposure:** the service listens on no port, so there is nothing to
  reach it by but the Pods themselves.
- **The Analyser's security key** unlocks every key shared with the Analyser
  Pod. Keep it in `/etc/photopod-face-analyser.env` (mode 600), not in
  `config.yaml`.

## Development

```bash
./setup.sh
./run.sh test
```

- `tests/test_pipeline.py`: requests answered against an in-memory Pod
  (photo in, answer written into the user's inbox in solidpod's form and
  opened with the user's folder key, photo removed, `done` written,
  unreadable photos answered, a photo the key cannot open left alone, each
  request answered once, a Pod that has not asked never read, a closed inbox
  passed over, answering on each notification, the shared keys opened once).
  The WebSocket itself is not exercised; `./run.sh check` and the journal
  show it working against the server.
- `tests/test_engine.py`: SCRFD and ArcFace on PhotoPod's sample photos
  (needs the models; skipped without them).
- `tests/test_crypto.py`: solidpod compatibility vectors.

When the models or the sample album change, regenerate PhotoPod's
`assets/demo/faces.json` from the PhotoPod folder and check it with
`flutter test test/face_engine_test.dart`:

```bash
A=analyser/face_analyser
$A/.venv/bin/python -I - "$A" assets/demo <<'PY'
import json, pathlib, subprocess, sys
a, demo = sys.argv[1], pathlib.Path(sys.argv[2])
photos = sorted(p for p in demo.glob('*.jpg') if not p.stem.endswith('_poster'))
out = subprocess.run([f'{a}/run.sh', 'analyse', '--full',
                      *[str(p.resolve()) for p in photos]],
                     capture_output=True, text=True, check=True).stdout
results = json.loads(out)
data = {'format': 'photopod-demo-faces', 'version': 1,
        'model': next(iter(results.values()))['model'],
        'faces': {pathlib.Path(k).name: v['faces']
                  for k, v in results.items() if v['faces']}}
(demo / 'faces.json').write_text(json.dumps(data, separators=(',', ':')))
PY
```

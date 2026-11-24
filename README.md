# PhotoPod

PhotoPod stores, organises and views your photos and videos in your own
[Solid](https://solidproject.org) Pod. Everything lives under
`photopod/data/` on your own server, in ordinary image and video files
that any other Solid application can read.

## Sections

The navigation rail down the left hand side offers six ways to look at
the same album.

- **Library** — every photo and video in the folder you are looking at,
  mixed together as a wall of tiles, with the subfolders alongside them.
  This is the only section that browses folders, and the only one that
  adds, copies, moves or renames anything.
- **Favourites** — everything you have put a heart on, gathered from
  every folder in the album.
- **Albums** — the albums you have made and those shared with you, each
  opening out into a row of its photos and videos.
- **People** — your photos by who is in them, found by the PhotoPod
  Analyser.
- **Tags** — your photos grouped by what they show, such as beaches,
  mountains or dogs, worked out by the PhotoPod Analyser.
- **Maps** — the photos that carry GPS coordinates, shown where they
  were taken, on an [OpenStreetMap](https://www.openstreetmap.org) map.

## Features

- Sign in with the standard Solid-OIDC flow through
  [solidui](https://pub.dev/packages/solidui)'s login screen.
- Photos: JPG, JPEG, PNG, GIF and TIFF. Videos: MP4 and MOV.
- Tiles carry no file names — an album is looked at, not read. The name
  is a hover away, and **Get Info** writes out everything else: the
  size, the dates, the pixel dimensions, the camera, the exposure and
  the place the photo was taken.
- Put a heart on any photo or video, from its tile, from the toolbar or
  from the preview. Hearts are kept in your Pod, so they follow you from
  one device to the next.
- A detailed list is still a tap away in **View**, for when the name,
  the size and the date matter more than the picture. **View** also sets
  how big the tiles are and how many items appear on a page.
- Add, delete, duplicate and rename photos and videos. A duplicate sits
  beside its original as `beach_copy.jpg`, then `beach_copy_1.jpg` and
  so on. A heart, and a place in an album, follow a photo through a
  rename.
- Gather photos and videos into albums with **Add to album**, whose
  menu ends in **Create new album...**. The **Albums** section lists your
  albums, A to Z, then those shared with you, each as a row you open to
  scroll sideways through its photos; each album can be renamed or deleted
  from its title bar. Favourites has a section of its own. It is offered
  in **Add to album** too, as a system album that can be neither renamed
  nor deleted.
- Share any file or folder with other WebIDs using Solid's own access
  control, including the permissions each recipient is granted.
- Files are encrypted at rest with your Solid security key.
- Sort by file name or by date, in either direction, or by location: the
  city or region each photo was taken in, such as Canberra, Australia, with
  the photos that do not say where under Others. The regions are bundled
  with the app from [GeoNames](https://www.geonames.org/) (CC BY 4.0), so
  where your photos were taken is never sent anywhere to name it.
- Preview a photo full size, or play a video, in a modal dialogue.

## Storage

Photos and videos are written under `photopod/data/` through solidpod's
`writePod`, the same way every app in this family stores its data: the
content is encrypted, wrapped in Turtle and given an access control list.
Each file is stored under a random name that keeps only its extension, so
a photo added as `beach.jpg` is stored as `3f9c…e1.jpg.enc.ttl` alongside
`3f9c…e1.jpg.enc.ttl.acl`. Its own name is written inside the file, ahead
of the picture, and encrypted with it, so the server never sees it while
anyone it is shared with does. Folders have random names too.

Storing media this way keeps it visible to the shared Solid file browsers,
which list only `.ttl` resources, and gives each file the access control
list that sharing works through. The cost is that a photo cannot be shown
without fetching and decrypting it, which takes far too long for a camera
original in every tile. So PhotoPod stores two smaller copies of each
photo when it is added, a small one for the grid, carrying the photo's
EXIF details, and a large one for the preview, encrypted in the hidden
`.thumbnails` folder. They are cached in memory once fetched. Only
downloading fetches the original.

PhotoPod's own bookkeeping is encrypted JSON, each file stored as
`<name>.json.enc.ttl` in `photopod/data/`: the catalog of names, places and
people (`catalog.json`), the favourites (`favourites.json`), the faces and
tags the Analyser found (`faces.json`, `tags.json`), and what has been
shared (`album-shares.json`, `shared-names.json`). Each album is a file of
its own in `photopod/data/albums/`, under a random name with the album's
name inside it, so there are exactly as many albums as files there. The
Library hides the `albums` folder.

Reading still copes with a plain, unencrypted resource, so anything
already in the album, or put there by another tool or an earlier build,
stays visible. Plain bookkeeping files from earlier builds are moved to
their encrypted form the first time they are written.

### Resource names

Because files, folders and albums are stored under random names, the name
the user gives one never reaches a URL and may be in any script, with any
punctuation. It only has to be one a file system will take, since a
downloaded photo carries its name onto the user's own machine, so
`/ \ : * ? " < > |` and control characters are refused.

The random names also sidestep a solidpod problem. solidpod files a
resource's encryption key under a URL it rebuilds from the resource's own
URL, and the two halves of that round trip disagree about escaping: the
path is taken out of the URL with `Uri.pathSegments`, which decodes each
segment, and the URL is put back together by joining the segments
verbatim, which does not encode them again. A photo stored as
`my%20photo.jpg.enc.ttl` would have its key filed under
`.../my photo.jpg.enc.ttl`, where nothing ever looks for it, and the key
file left holding a subject IRI with a raw space in it — which is not valid
Turtle, and which costs every key written after it when that file is next
read back. A random name uses only characters a URL carries unescaped, so
the round trip is the identity.

## Photo details and the map

The size, dates and address of a file come from the Solid server. The
dimensions, the camera, the exposure and the coordinates come from the
photo's own EXIF block, which means the file has to be fetched,
decrypted and decoded before any of it is known.

That decode is the same one that produces the grid thumbnail, and both
results are cached together, so a photo already looked at in the Library
costs nothing to describe or to place on the map, and vice versa.

The Favourites and Maps sections are views over the whole album
rather than over one folder, so they walk the folders once and share the
result. The walk stops after 400 folders or 12 levels, and says so when
it has.

## Sample album

PhotoPod does not ask anyone to log in before they can look around. A
visitor goes straight into the app and finds every section filled with a
sample album bundled in `assets/demo/`:

- **Maps** — landscapes from six continents, from the Grand Canyon to
  Milford Sound, and the portraits below, each carrying GPS coordinates
  in its EXIF block.
- **Library** — photos dated across many years, so sorting by date and
  the timeline both have something to show.
- **People** — recent portraits of the Nobel laureates in physics John
  Mather, David Wineland and Adam Riess, several of each, dated and
  placed on the map. The faces
  are found and grouped on the device, exactly as for a real album; each
  group is then named after whoever is in most of its photos.
- **A video** — a short clip of the Birch Building at ANU, in the
  Library and placed on the map too.
- **Favourites** and **Albums** — a few hearts and two albums to start
  with. Changes to them last until the app is closed.

Every sample photo is from Wikimedia Commons and is in the public domain
or released under CC0, so none needs attribution. The video is the
authors' own.

Nothing in the sample album is stored in a Pod, so adding, deleting,
renaming and sharing ask the visitor to log in instead. Logging in, from
the banner above each section or from the profile menu, replaces the
samples with the user's own album.

## People and Tags: where photos are looked at

Faces and tags are worked out only for the photos the user chooses, with
**Identify People** or **Tag Photos**, by whichever of two analysers the
user chooses. Both run the same models (InsightFace buffalo_l for faces,
SigLIP ViT-B/16 for tags), and their answers are filed the same way, so
People and Tags do not care which one did the work.

The first time photos are to be looked at, PhotoPod asks which analyser to
use, and says how private each keeps the photos: TeePod gives **higher
privacy**, the Solid Community analyser **limited privacy**. The choice is
kept on the device (`lib/models/analyser_choice.dart`) and can be changed
at any time with the shield in the People or Tags status line
(`lib/dialogs/analyser_choice_dialog.dart`). When TeePod is chosen and
cannot be reached, PhotoPod reports it rather than quietly sending the
photos to the other analyser.

- **TeePod** (higher privacy), on the desktop and Android builds. TeePod
  is an image analyser running in a trusted execution environment, a Google Cloud
  Confidential Space virtual machine whose memory its host cannot read.
  PhotoPod connects to it directly, over mutual TLS, and before it sends a
  single photo it checks an attestation token signed by Google: that TeePod
  runs the exact container image named in `assets/config/teepod.json`, in
  Confidential Space, and holds the private key of the TLS certificate
  PhotoPod is connected to. Nothing is left in the Pod and nothing is
  shared. See `lib/services/teepod/` and
  [`assets/config/teepod/README.md`](assets/config/teepod/README.md), which
  explains the client certificate the build needs.
- **The Pod Analyser** (`analyser/face_analyser`) on the Solid Community
  server (limited privacy), in every build, and the only choice on the web,
  which cannot reach TeePod (see
  [`support/teepod/WEB.md`](support/teepod/WEB.md)), and in any build
  without TeePod's client certificate. The photos are left, encrypted, in a
  folder of the user's Pod shared with the Analyser for as long as it
  takes, and the Analyser writes its answers back there. The Analyser runs
  on an ordinary server, so whoever operates it could see the photos while
  they are looked at.

Either way, a photo is sent as its large rendition, without its EXIF block
or anything else saying where and when it was taken.

TeePod's tag vocabulary is not the Pod Analyser's, so its phrases are
filed under the Pod Analyser's tag names and categories wherever the two
mean the same (`lib/services/teepod/tag_answers.dart`), and photos tagged on
the web and on the desktop sit together in Tags.

When TeePod is redeployed, its image digest changes and
`expectedImageDigest` must be updated to match; until it is, PhotoPod
refuses to send it anything, and says why. The deployed TeePod is currently
a Confidential Space *debug* image, which its operator can look inside, so
`allowDebugImage` is true; set it to false once TeePod runs on a
production image.

## Getting started

```bash
flutter pub get
flutter run
```

Before submitting a pull request:

```bash
make prep
```

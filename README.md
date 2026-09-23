# PhotoPod

PhotoPod stores, organises and views your photos and videos in your own
[Solid](https://solidproject.org) Pod. Everything lives under
`photopod/data/` on your own server, in ordinary image and video files
that any other Solid application can read.

## Sections

The navigation rail down the left hand side offers four ways to look at
the same album.

- **Library** — every photo and video in the folder you are looking at,
  mixed together as a wall of tiles, with the subfolders alongside them.
  This is the only section that browses folders, and the only one that
  adds, copies, moves or renames anything.
- **Favourites** — everything you have put a heart on, gathered from
  every folder in the album.
- **Videos** — every video in the album, wherever it is filed.
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
- Add, delete, copy, move and rename files and folders. A copy or move
  destination ending in a file name renames the file on the way, and a
  folder that is not there yet can be created from the same dialogue.
  A heart follows its photo through a move or a rename.
- Share any file or folder with other WebIDs using Solid's own access
  control, including the permissions each recipient is granted.
- Files are encrypted at rest with your Solid security key.
- Sort by file name or by date, in either direction.
- Preview a photo full size, or play a video, in a modal dialogue.

## Storage

Photos and videos are written under `photopod/data/` through solidpod's
`writePod`, the same way every app in this family stores its data: the
content is encrypted, wrapped in Turtle and given an access control list.
A photo added as `beach.jpg` is stored as `beach.jpg.enc.ttl` alongside
`beach.jpg.enc.ttl.acl`, and PhotoPod shows the name without the suffix.

Storing media this way keeps it visible to the shared Solid file browsers,
which list only `.ttl` resources, and gives each file the access control
list that sharing works through. The cost is that a thumbnail cannot be
read without decrypting the photo first, so thumbnails are cached in
memory and fetched only for the page on screen.

Reading still copes with a plain, unencrypted resource, so anything
already in the album, or put there by another tool, stays visible.

The hearts live in `photopod/data/favourites.json`, a small list of the
Pod-relative paths that carry one. It is deliberately not encrypted:
asking for the security key merely to find out which photos are
favourites would put a password prompt in front of an album that may
hold nothing yet, and the file names it holds are already plain to see in
the container listing.

## Photo details and the map

The size, dates and address of a file come from the Solid server. The
dimensions, the camera, the exposure and the coordinates come from the
photo's own EXIF block, which means the file has to be fetched,
decrypted and decoded before any of it is known.

That decode is the same one that produces the grid thumbnail, and both
results are cached together, so a photo already looked at in the Library
costs nothing to describe or to place on the map, and vice versa.

The Favourites, Videos and Maps sections are views over the whole album
rather than over one folder, so they walk the folders once and share the
result. The walk stops after 400 folders or 12 levels, and says so when
it has.

## Getting started

```bash
flutter pub get
flutter run
```

Before submitting a pull request:

```bash
make prep
```

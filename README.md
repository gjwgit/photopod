# PhotoPod

PhotoPod stores, organises and views your photos and videos in your own
[Solid](https://solidproject.org) Pod. Everything lives under
`photopod/data/` on your own server, in ordinary image and video files
that any other Solid application can read.

## Features

- Sign in with the standard Solid-OIDC flow through
  [solidui](https://pub.dev/packages/solidui)'s login screen.
- Separate **Photos** and **Videos** sections in the navigation bar.
- Photos: JPG, JPEG, PNG, GIF and TIFF. Videos: MP4 and MOV.
- Browse folders, with thumbnails or a detailed list, a page at a time.
- Add, delete, copy, move and rename files and folders. A copy or move
  destination ending in a file name renames the file on the way, and a
  folder that is not there yet can be created from the same dialogue.
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

## Getting started

```bash
flutter pub get
flutter run
```

Before submitting a pull request:

```bash
make prep
```

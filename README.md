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
- Add, delete, copy, move and rename files and folders.
- Share any file or folder with other WebIDs using Solid's own access
  control, including the permissions each recipient is granted.
- Sort by file name or by date, in either direction.
- Preview a photo full size, or play a video, in a modal dialogue.

## Storage

Photos and videos are written as plain binary resources under
`photopod/data/`, each keeping its own name and media type, rather than
being wrapped in an encrypted Turtle envelope. That is what lets the grid
build thumbnails cheaply, lets videos play, and lets a shared photo be
opened directly from its URL by whoever it was shared with. Anything you
put in PhotoPod is therefore readable by anyone you grant access to, and
by nobody else.

## Getting started

```bash
flutter pub get
flutter run
```

Before submitting a pull request:

```bash
make prep
```

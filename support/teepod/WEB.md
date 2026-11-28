# TeePod and the web build

The web build of PhotoPod cannot use TeePod. It offers only the Solid
Community analyser (`analyser/face_analyser`). The native builds connect
to TeePod as `lib/services/teepod/teepod_io.dart` describes:

1. They open a TLS connection that presents PhotoPod's client
   certificate, which TeePod requires of anyone who connects.
2. They trust TeePod's certificate, and no other, by its SHA-256 digest.
   TeePod creates that certificate inside the enclave each time it starts,
   so no certificate authority can vouch for it.
3. They ask TeePod for a Confidential Space attestation token that names
   a fresh nonce and that digest, and check that Google signed it.
4. They send photos over that same pinned gRPC channel.

The browser does the TLS for a web app, and the app has no say in it:

- A page cannot present a client certificate of its own choosing.
- A page cannot trust a server by its digest, or see the certificate of
  the server it is talking to. The browser accepts only certificates that
  chain to an authority it trusts.
- A page cannot speak native gRPC, which needs HTTP/2 trailers that the
  browser's `fetch` does not expose. It can speak only gRPC-Web.

## What it would take

Since a page cannot tell which server its TLS connection ends at, the
web build could not rely on TLS to reach the enclave and nothing else.
TeePod would have to:

- serve gRPC-Web, or a plain HTTPS API, with a certificate that a public
  authority issued for its domain name, perhaps through a proxy;
- name a public key in its attestation token, one that it generated
  inside the enclave, so that PhotoPod could encrypt each photo to that
  key before sending it. Then neither a proxy nor whoever holds the TLS
  certificate could see the photos;
- stop asking for the client certificate, or accept another way for
  PhotoPod to identify itself. As `assets/config/teepod/README.md` notes,
  the certificate only keeps casual clients away, since every installed
  copy carries its key.

Until then, `lib/services/teepod/teepod_stub.dart` gives the web build a
TeePod that is never available.

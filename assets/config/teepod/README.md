# TeePod client certificate

PhotoPod's desktop and Android builds find faces and tags with TeePod, an
image analyser running in a trusted execution environment (Google Cloud
Confidential Space). TeePod only accepts connections that present a client
certificate issued by its own certificate authority, so the build needs two
files here:

- `client-cert.pem` — the signed client certificate (TeePod's
  `photopod-signed.pem`)
- `client-key.pem` — its private key (TeePod's `photopod-key.pem`)

Both are kept out of git (see `.gitignore`), since this repository is public.
Ask the TeePod maintainers for them, or copy them from
`teepod/docs/client-certs/` if you have that repository beside this one:

```bash
cp ../teepod/docs/client-certs/photopod-signed.pem assets/config/teepod/client-cert.pem
cp ../teepod/docs/client-certs/photopod-key.pem    assets/config/teepod/client-key.pem
```

Only the native builds bundle this folder (see `platforms:` in
`pubspec.yaml`): a web build never carries the key, and offers only the
Solid Community analyser (see `support/teepod/WEB.md`). A build without the
two files does the same, and its analyser choice dialogue says why TeePod
is not available.

Bear in mind that every installed copy of PhotoPod carries the key, and
anyone determined can take it out. It keeps casual clients away from TeePod;
it does not prove that a request came from PhotoPod. What protects the
photos is the attestation PhotoPod checks before it sends any of them: see
`lib/services/teepod/attestation.dart`.

The certificate expires. When TeePod issues a new one, replace both files
and rebuild. When TeePod is redeployed, its container image digest changes
too, and `expectedImageDigest` in `assets/config/teepod.json` must be updated
to match, or PhotoPod will refuse to send it anything.

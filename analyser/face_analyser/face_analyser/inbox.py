"""The face inbox: the folder in each user's Pod shared with the Analyser.

Copyright (C) 2026, Software Innovation Institute, ANU.

Licensed under the GNU General Public License, Version 3 (the "License").

License: https://opensource.org/license/gpl-3-0.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public License along with
this program. If not, see https://opensource.org/license/gpl-3-0.

Authors: Tony Chen
"""

# PhotoPod leaves each photo to be looked at as one file in the user's own Pod:
#
#     <pod>/photopod/data/.faces-inbox/<key>.enc.ttl
#
# where <key> is the random part of the photo's stored name, so the name says
# nothing about the photo. Every file in the folder is encrypted with the
# folder's own key (solidpod's `inheritKeyFrom`), and the folder is shared with
# the Analyser once, for reading and writing: the share puts the folder key in
# the Analyser's shared-keys.ttl, which is how this service can read every
# photo left there, and writing is what lets it remove each one once it has
# been analysed. Inside the encryption is
#
#     {"format": "photopod-face-request", "version": 1, "image": "<base64 JPEG>"}
#
# the photo's large rendition, which carries no EXIF block.

from __future__ import annotations

import base64
import json
from dataclasses import dataclass

from . import crypto, pod_paths as paths, turtle
from .config import Config
from .keys import SharedResource

REQUEST_FORMAT = 'photopod-face-request'
_SUFFIX = '.enc.ttl'


class RequestError(ValueError):
    """Raised when an inbox file is not a request this service understands."""


@dataclass(frozen=True)
class InboxItem:
    url: str
    key: str


def inbox_url(web_id: str, config: Config) -> str:
    """The face inbox of the Pod [web_id] names."""

    return paths.data_url(web_id, config.analyser.app_dir_name,
                          config.inbox.folder.strip('/')) + '/'


def shared_inboxes(shared: list[SharedResource],
                   config: Config) -> dict[str, SharedResource]:
    """The face inboxes shared with the Analyser, by URL."""

    fragment = config.inbox.fragment
    return {
        item.resource_url: item
        for item in shared
        if item.is_container
        and item.resource_url.endswith(fragment)
        and not item.resource_url.startswith(config.analyser.pod_root)
    }


def items_in(members: list[str]) -> list[InboxItem]:
    """The requests among the URLs listed in an inbox, oldest name first."""

    found = []
    for url in members:
        name = url.rsplit('/', 1)[-1]
        if url.endswith('/') or not name.endswith(_SUFFIX) or name.startswith('.'):
            continue
        found.append(InboxItem(url=url, key=name[: -len(_SUFFIX)]))
    return sorted(found, key=lambda item: item.key)


def decrypt_document(text: str, file_url: str,
                     keys: dict[str, bytes], config: Config) -> str:
    """The plaintext of a solidpod-encrypted turtle document.

    The same rules as HealthPod's analyser: the folder the document names
    (`inheritKeyFrom`) wins, then a key shared for the file itself, then one
    for its folder.
    """

    triples = turtle.triple_map(text, base=file_url)
    record = triples.get(file_url)
    if record is None:
        record = next((r for r in triples.values()
                       if paths.APPS_TERMS + 'encData' in r), None)
    if record is None:
        raise RequestError('not a solidpod encrypted document')

    enc_data = turtle.single(record.get(paths.APPS_TERMS + 'encData'))
    iv_b64 = turtle.single(record.get(paths.APPS_TERMS + 'iv'))
    if not enc_data or not iv_b64:
        raise RequestError('the document carries no encrypted data')

    key = None
    inherit_from = turtle.single(record.get(paths.APPS_TERMS + 'inheritKeyFrom'))
    if inherit_from:
        root = paths.owner_pod_root(file_url, config.analyser.app_dir_name)
        inherited = root + inherit_from.lstrip('/')
        key = keys.get(inherited if inherited.endswith('/') else inherited + '/')
    if key is None:
        key = keys.get(file_url)
    if key is None:
        key = keys.get(file_url.rsplit('/', 1)[0] + '/')
    if key is None:
        raise crypto.DecryptionError('no key has been shared for this file')

    return crypto.aes_ctr_decrypt(enc_data, key, base64.b64decode(iv_b64))


def decode_request(plaintext: str) -> bytes:
    """The picture inside a decrypted inbox file."""

    try:
        data = json.loads(plaintext)
    except json.JSONDecodeError as e:
        raise RequestError(f'not JSON: {e}') from e
    if not isinstance(data, dict) or data.get('format') != REQUEST_FORMAT:
        raise RequestError('not a PhotoPod face request')
    try:
        return base64.b64decode(data['image'], validate=True)
    except (KeyError, TypeError, ValueError) as e:
        raise RequestError(f'no picture in the request: {e}') from e

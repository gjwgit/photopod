"""An in-memory Solid server and Pods, for the pipeline tests.

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

# Taken from HealthPod's analyser (tests/test_pipeline.py), whose fake server
# models the same solidpod layout; `delete` is added, since the face analyser
# empties the inbox it is shared.

from __future__ import annotations

import base64
import json

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from face_analyser import crypto, pod_paths as paths, turtle

class FakePod:
    """One Pod's key material, as it would sit on the server."""

    def __init__(self, web_id: str, security_key: str = 'pod-key') -> None:
        self.web_id = web_id
        self.security_key = security_key
        self.salt = b'0123456789abcdef'
        self.master_key, self.verification = crypto.derive_keys_v2(
            security_key, self.salt)
        self.private_key = rsa.generate_private_key(
            public_exponent=65537, key_size=2048)
        self.public_key = self.private_key.public_key()

    @property
    def private_pem(self) -> str:
        return self.private_key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.TraditionalOpenSSL,
            serialization.NoEncryption(),
        ).decode()

    @property
    def public_body(self) -> str:
        pem = self.public_key.public_bytes(
            serialization.Encoding.PEM,
            serialization.PublicFormat.PKCS1).decode()
        return ''.join(
            line for line in pem.splitlines() if not line.startswith('-----'))


class FakeResponse:
    def __init__(self, status_code: int, body: dict) -> None:
        self.status_code = status_code
        self._body = body
        self.text = json.dumps(body)

    def json(self) -> dict:
        return self._body


class FakeSolidClient:
    """A dictionary pretending to be a Solid server."""

    def __init__(self) -> None:
        self.resources: dict[str, str] = {}
        self.patched: list[tuple[str, str]] = []
        self.containers_created: list[str] = []
        self.private_urls: set[str] = set()
        self.deleted: list[str] = []
        self.subscriptions: list[tuple[str, str | None]] = []

    # -- Reading -----------------------------------------------------------

    def get_text(self, url: str, *, accept: str = 'text/turtle') -> str:
        from face_analyser.solid_client import ForbiddenError, NotFoundError

        if self._is_private(url):
            raise ForbiddenError(f'read {url}: access denied', 403)
        if url.endswith('/'):
            return self._container_document(url)
        if url not in self.resources:
            raise NotFoundError(f'read {url}: not found', 404)
        return self.resources[url]

    def get_text_or_none(self, url: str, *, accept: str = 'text/turtle') -> str | None:
        from face_analyser.solid_client import NotFoundError

        try:
            return self.get_text(url, accept=accept)
        except NotFoundError:
            return None

    # URLs the Analyser may neither read nor write, as a Pod's own containers
    # normally are. The server answers 403: the resource is there, but not for
    # us.

    def _is_private(self, url: str) -> bool:
        return url in self.private_urls

    def exists(self, url: str) -> bool:
        # A private resource still exists; the server just will not show it.
        if self._is_private(url):
            return True
        if url.endswith('/'):
            return any(key.startswith(url) for key in self.resources)
        return url in self.resources

    def list_container(self, url: str) -> list[str]:
        from face_analyser.solid_client import ForbiddenError

        if not url.endswith('/'):
            url += '/'
        if self._is_private(url):
            raise ForbiddenError(f'read {url}: access denied', 403)
        members = set()
        for key in self.resources:
            if not key.startswith(url) or key == url:
                continue
            remainder = key[len(url):]
            head = remainder.split('/')[0]
            members.add(url + head + ('/' if '/' in remainder else ''))
        return sorted(members)

    def _container_document(self, url: str) -> str:
        lines = [f'@prefix ldp: <{paths.LDP_NS}> .', f'<{url}>']
        members = self.list_container(url)
        if not members:
            return f'<{url}> a ldp:Container .\n'
        lines.append('    ldp:contains ' + ', '.join(
            f'<{member}>' for member in members) + ' .')
        return '\n'.join(lines) + '\n'

    # -- Writing -----------------------------------------------------------

    def put_text(self, url: str, content: str, *, content_type: str = 'text/turtle') -> None:
        from face_analyser.solid_client import ForbiddenError

        if self._is_private(url):
            raise ForbiddenError(f'write {url}: access denied', 403)
        self.resources[url] = content

    def ensure_container(self, url: str) -> None:
        from face_analyser.solid_client import ForbiddenError

        self.containers_created.append(url)
        # Walking up a path in somebody else's Pod runs into containers that
        # are theirs alone; the real client cannot create those.
        if self._is_private(url):
            raise ForbiddenError(f'create {url}: access denied', 403)

    def patch_sparql(self, url: str, query: str) -> None:
        """Apply the DELETE DATA and INSERT DATA blocks of a SPARQL update."""

        from face_analyser.solid_client import NotFoundError

        self.patched.append((url, query))
        if url not in self.resources:
            # A real server will not patch a resource that is not there.
            raise NotFoundError(f'patch {url}: not found', 404)

        graph = turtle.parse(self.resources[url])
        prefixes = '\n'.join(
            f'@prefix {declaration} .'
            for declaration in self._prefix_declarations(query)
        )

        for keyword, apply in (('DELETE DATA', graph.remove),
                               ('INSERT DATA', graph.add)):
            for block in self._blocks(query, keyword):
                # The final full stop is optional inside a SPARQL data block
                # but required by the turtle parser used here.
                body = block.strip()
                if not body.endswith('.'):
                    body += ' .'
                patch = turtle.parse(f'{prefixes}\n{body}')
                for triple in patch:
                    apply(triple)

        self.resources[url] = graph.serialize(format='turtle')

    @staticmethod
    def _prefix_declarations(query: str) -> list[str]:
        declarations = []
        for chunk in query.split('PREFIX ')[1:]:
            head = chunk.split('DELETE')[0].split('INSERT')[0].strip()
            if head:
                declarations.append(head)
        return declarations

    @staticmethod
    def _blocks(query: str, keyword: str) -> list[str]:
        """The braced bodies following each occurrence of [keyword]."""

        blocks = []
        position = query.find(keyword)
        while position != -1:
            start = query.index('{', position)
            depth, index = 0, start
            while index < len(query):
                if query[index] == '{':
                    depth += 1
                elif query[index] == '}':
                    depth -= 1
                    if depth == 0:
                        break
                index += 1
            blocks.append(query[start + 1:index])
            position = query.find(keyword, index)
        return blocks

    def delete(self, url: str) -> bool:
        from face_analyser.solid_client import ForbiddenError

        if self._is_private(url):
            raise ForbiddenError(f'delete {url}: access denied', 403)
        self.deleted.append(url)
        return self.resources.pop(url, None) is not None

    def request(self, method: str, url: str, *, content: bytes | None = None,
                content_type: str | None = None,
                headers: dict[str, str] | None = None) -> 'FakeResponse':
        """A subscription to a notification channel, the one request the
        service makes other than reading and writing resources."""

        body = json.loads(content or b'{}')
        self.subscriptions.append((url, body.get('topic')))
        return FakeResponse(200, {'receiveFrom': f'wss://server/ws/{len(self.subscriptions)}'})

    def close(self) -> None:
        return None

    def login(self) -> None:
        return None


def encrypted_resource(url: str, payload: dict, key: bytes,
                       inherit_from: str | None = None) -> str:
    """Write one file the way PhotoPod's `writePod()` would."""

    iv = crypto.random_iv()
    body = json.dumps(payload)
    document = (
        f'@prefix solidTerms: <{paths.APPS_TERMS}> .\n'
        f'<{url}>\n'
        f'    solidTerms:path "{url.split("/", 3)[-1]}";\n'
        f'    solidTerms:iv "{base64.b64encode(iv).decode()}";\n'
    )
    if inherit_from:
        document += f'    solidTerms:inheritKeyFrom "{inherit_from}";\n'
    document += (
        f'    solidTerms:encData "{crypto.aes_ctr_encrypt(body, key, iv)}".\n')
    return document

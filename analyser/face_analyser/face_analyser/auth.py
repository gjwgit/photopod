"""Who is asking: Solid-OIDC access tokens bound to a DPoP proof.

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

# PhotoPod sends the decrypted pictures of a user's photos, so the service only
# answers someone logged in to a Solid server it trusts. The app already holds
# what proves that: the access token its Solid server issued at login, which is
# bound to a key pair kept on the device (DPoP, RFC 9449). Each request carries
#
#     Authorization: DPoP <access token>
#     DPoP: <proof>
#
# exactly as a request to the user's own Pod does, the proof being made for
# this service's URL. The service checks
#
#   * the access token: signed by a key the issuer publishes, the issuer on
#     the configured list, not expired, meant for Solid, naming a WebID;
#   * the proof: signed by the key the token is bound to (`cnf.jkt`), for this
#     method and URL, recent, not seen before, and, when it says so, made for
#     this very token (`ath`).
#
# The token cannot be replayed to the user's Pod by anyone who sees it here,
# since each Pod request needs a fresh proof signed by the device's key.

from __future__ import annotations

import base64
import hashlib
import json
import logging
import threading
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Callable

import jwt

log = logging.getLogger(__name__)

# The algorithms accepted on either token. Symmetric ones are never accepted:
# the key would have to be shared with whoever signed.

_ALGORITHMS = ['RS256', 'RS384', 'RS512', 'PS256', 'PS384', 'PS512',
               'ES256', 'ES384', 'ES512', 'EdDSA']

# How long an issuer's signing keys are trusted before being fetched again,
# and how soon an unknown key id may trigger another fetch.

_JWKS_TTL = 3600.0
_JWKS_RETRY = 60.0


class AuthError(Exception):
    """Raised when a request does not prove who is making it."""


@dataclass(frozen=True)
class Caller:
    """Who a request came from."""

    web_id: str
    issuer: str
    client_id: str | None = None


@dataclass
class AuthConfig:
    """Which callers the service answers."""

    # Whether requests must be authenticated at all. Only ever turn this off
    # on a machine nobody else can reach, for development.

    required: bool = True

    # The Solid servers (OIDC issuers) whose users may use the service.

    issuers: list[str] = field(default_factory=list)

    # When not empty, only WebIDs starting with one of these may use it.

    web_id_prefixes: list[str] = field(default_factory=list)

    # How far the device's clock may be from this one, in seconds.

    clock_skew: int = 300

    def __post_init__(self) -> None:
        self.issuers = [_normal_issuer(i) for i in self.issuers if i]


def _normal_issuer(issuer: str) -> str:
    return issuer.rstrip('/')


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('ascii')


def jwk_thumbprint(jwk: dict[str, Any]) -> str:
    """The RFC 7638 thumbprint of a public [jwk], as `cnf.jkt` holds it."""

    members = {
        'RSA': ('e', 'kty', 'n'),
        'EC': ('crv', 'kty', 'x', 'y'),
        'OKP': ('crv', 'kty', 'x'),
    }.get(jwk.get('kty'))
    if members is None:
        raise AuthError(f'Unsupported key type {jwk.get("kty")!r}.')
    try:
        canonical = {name: jwk[name] for name in members}
    except KeyError as e:
        raise AuthError(f'The key lacks {e.args[0]!r}.') from None
    text = json.dumps(canonical, separators=(',', ':'), sort_keys=True)
    return _b64url(hashlib.sha256(text.encode('utf-8')).digest())


def normal_url(url: str) -> str:
    """[url] without query or fragment, with the scheme and host in lower
    case and a default port dropped, for comparing with a proof's `htu`."""

    parts = urllib.parse.urlsplit(url)
    scheme = parts.scheme.lower()
    host = (parts.hostname or '').lower()
    port = parts.port
    if port and not (
        (scheme == 'https' and port == 443) or (scheme == 'http' and port == 80)
    ):
        host = f'{host}:{port}'
    return urllib.parse.urlunsplit((scheme, host, parts.path or '/', '', ''))


def _fetch_json(url: str) -> dict[str, Any]:
    request = urllib.request.Request(url, headers={'Accept': 'application/json'})
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.loads(response.read().decode('utf-8'))


class IssuerKeys:
    """The signing keys of each trusted issuer, fetched through OIDC
    discovery and cached."""

    def __init__(self, fetch: Callable[[str], dict[str, Any]] = _fetch_json):
        self._fetch = fetch
        self._lock = threading.Lock()
        self._keys: dict[str, tuple[float, dict[str, Any]]] = {}

    def key(self, issuer: str, kid: str | None) -> jwt.PyJWK:
        keys = self._keys_of(issuer, refresh=False)
        found = self._pick(keys, kid)
        if found is None:
            # A rotated key: fetch again, but not on every bad request.
            keys = self._keys_of(issuer, refresh=True)
            found = self._pick(keys, kid)
        if found is None:
            raise AuthError(f'{issuer} has no signing key {kid!r}.')
        return jwt.PyJWK(found)

    def count(self, issuer: str) -> int:
        """How many keys [issuer] publishes, fetching them if need be."""

        return len(self._keys_of(issuer, refresh=False).get('keys', []))

    @staticmethod
    def _pick(keys: dict[str, Any], kid: str | None) -> dict[str, Any] | None:
        candidates = [k for k in keys.get('keys', []) if k.get('use', 'sig') == 'sig']
        if kid is not None:
            candidates = [k for k in candidates if k.get('kid') == kid]
            return candidates[0] if candidates else None

        # A token naming no key can only be checked against an issuer
        # that has just the one.

        return candidates[0] if len(candidates) == 1 else None

    def _keys_of(self, issuer: str, *, refresh: bool) -> dict[str, Any]:
        with self._lock:
            now = time.monotonic()
            cached = self._keys.get(issuer)
            if cached is not None:
                fetched, keys = cached
                age = now - fetched
                if age < _JWKS_TTL and not (refresh and age >= _JWKS_RETRY):
                    return keys
            try:
                discovery = self._fetch(f'{issuer}/.well-known/openid-configuration')
                if _normal_issuer(discovery.get('issuer', '')) != issuer:
                    raise AuthError(f'{issuer} names a different issuer.')
                keys = self._fetch(discovery['jwks_uri'])
            except AuthError:
                raise
            except Exception as e:  # noqa: BLE001 - any failure is the same to the caller
                if cached is not None:
                    log.warning('Keeping old keys of %s: %s', issuer, e)
                    return cached[1]
                raise AuthError(f'Could not fetch the keys of {issuer}: {e}') from e
            self._keys[issuer] = (now, keys)
            return keys


class _SeenProofs:
    """The `jti` of every proof accepted lately, so none is accepted twice."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._seen: dict[str, float] = {}

    def check_and_add(self, jti: str, ttl: float) -> None:
        with self._lock:
            now = time.monotonic()
            if len(self._seen) > 10_000:
                self._seen = {k: v for k, v in self._seen.items() if v > now}
            expiry = self._seen.get(jti)
            if expiry is not None and expiry > now:
                raise AuthError('The DPoP proof has been used before.')
            self._seen[jti] = now + ttl


class Authenticator:
    """Checks the Solid-OIDC credentials on each request."""

    def __init__(self, config: AuthConfig, keys: IssuerKeys | None = None,
                 clock: Callable[[], float] = time.time):
        self.config = config
        self._keys = keys or IssuerKeys()
        self._seen = _SeenProofs()
        self._clock = clock

    def authenticate(self, headers: Any, method: str, url: str) -> Caller | None:
        """The caller of a request to [url] by [method] with [headers], or
        None when authentication is switched off and none was offered.

        Raises AuthError when the request does not prove who made it.
        """

        authorisation = headers.get('Authorization') or ''
        proof = headers.get('DPoP') or ''
        if not authorisation and not self.config.required:
            return None

        scheme, _, token = authorisation.partition(' ')
        if scheme.lower() != 'dpop' or not token or not proof:
            raise AuthError('Log in to your Solid Pod to use this service.')

        claims = self._access_token(token.strip())
        self._proof(proof.strip(), token.strip(), claims, method, url)

        web_id = claims['webid']
        prefixes = self.config.web_id_prefixes
        if prefixes and not any(web_id.startswith(p) for p in prefixes):
            raise AuthError(f'{web_id} may not use this service.')
        return Caller(web_id=web_id, issuer=claims['iss'],
                      client_id=claims.get('client_id') or claims.get('azp'))

    def _access_token(self, token: str) -> dict[str, Any]:
        try:
            unverified = jwt.decode(token, options={'verify_signature': False})
            header = jwt.get_unverified_header(token)
        except jwt.PyJWTError as e:
            raise AuthError(f'The access token is not a JWT: {e}') from e

        issuer = _normal_issuer(str(unverified.get('iss', '')))
        if issuer not in self.config.issuers:
            raise AuthError(f'Users of {issuer or "that server"} may not use '
                            'this service.')

        key = self._keys.key(issuer, header.get('kid'))
        try:
            claims = jwt.decode(
                token,
                key=key,
                algorithms=_ALGORITHMS,
                audience='solid',
                leeway=self.config.clock_skew,
                options={'require': ['exp', 'iss', 'webid']},
            )
        except jwt.PyJWTError as e:
            raise AuthError(f'The access token was refused: {e}') from e

        jkt = (claims.get('cnf') or {}).get('jkt')
        if not jkt:
            raise AuthError('The access token is not bound to a DPoP key.')
        return claims

    def _proof(self, proof: str, token: str, claims: dict[str, Any],
               method: str, url: str) -> None:
        try:
            header = jwt.get_unverified_header(proof)
        except jwt.PyJWTError as e:
            raise AuthError(f'The DPoP proof is not a JWT: {e}') from e

        jwk = header.get('jwk')
        if header.get('typ') != 'dpop+jwt' or not isinstance(jwk, dict):
            raise AuthError('The DPoP proof is malformed.')
        if any(private in jwk for private in ('d', 'p', 'q', 'dp', 'dq', 'qi')):
            raise AuthError('The DPoP proof carries a private key.')
        if header.get('alg') not in _ALGORITHMS:
            raise AuthError('The DPoP proof uses an unsupported algorithm.')

        if jwk_thumbprint(jwk) != claims['cnf']['jkt']:
            raise AuthError('The DPoP proof is signed by the wrong key.')

        try:
            body = jwt.decode(
                proof,
                key=jwt.PyJWK(jwk),
                algorithms=[header['alg']],
                options={'verify_aud': False, 'verify_exp': False,
                         'verify_iat': False, 'require': ['iat', 'jti',
                                                          'htm', 'htu']},
            )
        except jwt.PyJWTError as e:
            raise AuthError(f'The DPoP proof was refused: {e}') from e

        if str(body['htm']).upper() != method.upper():
            raise AuthError('The DPoP proof is for another method.')
        if normal_url(str(body['htu'])) != normal_url(url):
            raise AuthError(f'The DPoP proof is for {body["htu"]}, not {url}.')

        skew = self.config.clock_skew
        if abs(self._clock() - float(body['iat'])) > skew:
            raise AuthError('The DPoP proof is too old, or the device clock '
                            'is wrong.')

        ath = body.get('ath')
        if ath is not None:
            expected = _b64url(hashlib.sha256(token.encode('ascii')).digest())
            if ath != expected:
                raise AuthError('The DPoP proof is for another access token.')

        self._seen.check_and_add(str(body['jti']), 2.0 * skew)

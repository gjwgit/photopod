"""Solid-OIDC and DPoP checks, against an issuer made up for the test.

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

from __future__ import annotations

import base64
import hashlib
import json
import time
import unittest
import uuid

import jwt
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from jwt.algorithms import ECAlgorithm, RSAAlgorithm

from face_analyser.auth import (
    AuthConfig,
    AuthError,
    Authenticator,
    IssuerKeys,
    jwk_thumbprint,
    normal_url,
)

ISSUER = 'https://pod.example.org/'
URL = 'https://faces.example.org/v1/faces'
WEB_ID = 'https://pod.example.org/alice/profile/card#me'


def _public_jwk(key, algorithm) -> dict:
    return json.loads(algorithm.to_jwk(key.public_key()))


class _Issuer:
    """A Solid server: it publishes a key and signs access tokens."""

    def __init__(self):
        self.key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        self.jwk = {**_public_jwk(self.key, RSAAlgorithm), 'kid': 'k1',
                    'use': 'sig', 'alg': 'RS256'}
        self.fetches = 0

    def fetch(self, url: str) -> dict:
        self.fetches += 1
        if url == 'https://pod.example.org/.well-known/openid-configuration':
            return {'issuer': ISSUER, 'jwks_uri': 'https://pod.example.org/jwks'}
        if url == 'https://pod.example.org/jwks':
            return {'keys': [self.jwk]}
        raise OSError(f'unexpected fetch of {url}')

    def token(self, jkt: str, **overrides) -> str:
        now = int(time.time())
        claims = {'iss': ISSUER, 'aud': ['solid', 'photopod'], 'webid': WEB_ID,
                  'client_id': 'photopod', 'iat': now, 'exp': now + 600,
                  'cnf': {'jkt': jkt}}
        claims.update(overrides)
        return jwt.encode(claims, self.key, algorithm='RS256',
                          headers={'kid': 'k1'})


class _Device:
    """PhotoPod: a DPoP key pair, and proofs made with it."""

    def __init__(self, curve: bool = False):
        if curve:
            self.key = ec.generate_private_key(ec.SECP256R1())
            self.jwk = _public_jwk(self.key, ECAlgorithm)
            self.alg = 'ES256'
        else:
            self.key = rsa.generate_private_key(public_exponent=65537,
                                                key_size=2048)
            self.jwk = _public_jwk(self.key, RSAAlgorithm)
            self.alg = 'RS256'

    @property
    def jkt(self) -> str:
        return jwk_thumbprint(self.jwk)

    def proof(self, token: str | None, *, htm='POST', htu=URL, iat=None,
              jti=None) -> str:
        claims = {'htm': htm, 'htu': htu, 'iat': iat or int(time.time()),
                  'jti': jti or str(uuid.uuid4())}
        if token is not None:
            digest = hashlib.sha256(token.encode('ascii')).digest()
            claims['ath'] = base64.urlsafe_b64encode(digest).rstrip(b'=').decode()
        return jwt.encode(claims, self.key, algorithm=self.alg,
                          headers={'typ': 'dpop+jwt', 'jwk': self.jwk})


class AuthTest(unittest.TestCase):
    def setUp(self):
        self.issuer = _Issuer()
        self.device = _Device()
        self.auth = Authenticator(AuthConfig(issuers=[ISSUER]),
                                  IssuerKeys(fetch=self.issuer.fetch))

    def headers(self, token, proof):
        return {'Authorization': f'DPoP {token}', 'DPoP': proof}

    def check(self, token, proof, url=URL, method='POST'):
        return self.auth.authenticate(self.headers(token, proof), method, url)

    def test_accepts_a_bound_token(self):
        token = self.issuer.token(self.device.jkt)
        caller = self.check(token, self.device.proof(token))
        self.assertEqual(caller.web_id, WEB_ID)
        self.assertEqual(caller.issuer, ISSUER)

    def test_accepts_an_elliptic_curve_device_key(self):
        device = _Device(curve=True)
        token = self.issuer.token(device.jkt)
        self.assertEqual(self.check(token, device.proof(token)).web_id, WEB_ID)

    def test_accepts_a_proof_without_ath(self):
        token = self.issuer.token(self.device.jkt)
        self.check(token, self.device.proof(None))

    def test_refuses_no_credentials(self):
        with self.assertRaises(AuthError):
            self.auth.authenticate({}, 'POST', URL)

    def test_refuses_a_bearer_token(self):
        token = self.issuer.token(self.device.jkt)
        with self.assertRaises(AuthError):
            self.auth.authenticate({'Authorization': f'Bearer {token}'},
                                   'POST', URL)

    def test_refuses_an_untrusted_issuer(self):
        token = self.issuer.token(self.device.jkt, iss='https://evil.example/')
        with self.assertRaisesRegex(AuthError, 'may not use'):
            self.check(token, self.device.proof(token))

    def test_refuses_a_forged_token(self):
        forger = _Issuer()
        token = forger.token(self.device.jkt)
        with self.assertRaises(AuthError):
            self.check(token, self.device.proof(token))

    def test_refuses_an_expired_token(self):
        now = int(time.time())
        token = self.issuer.token(self.device.jkt, iat=now - 7200,
                                  exp=now - 3600)
        with self.assertRaisesRegex(AuthError, 'expired'):
            self.check(token, self.device.proof(token))

    def test_refuses_a_token_not_for_solid(self):
        token = self.issuer.token(self.device.jkt, aud='someone-else')
        with self.assertRaises(AuthError):
            self.check(token, self.device.proof(token))

    def test_refuses_a_proof_from_another_key(self):
        token = self.issuer.token(self.device.jkt)
        thief = _Device()
        with self.assertRaisesRegex(AuthError, 'wrong key'):
            self.check(token, thief.proof(token))

    def test_refuses_a_proof_for_another_url(self):
        token = self.issuer.token(self.device.jkt)
        proof = self.device.proof(token, htu='https://pod.example.org/alice/')
        with self.assertRaisesRegex(AuthError, 'is for'):
            self.check(token, proof)

    def test_refuses_a_proof_for_another_method(self):
        token = self.issuer.token(self.device.jkt)
        with self.assertRaisesRegex(AuthError, 'method'):
            self.check(token, self.device.proof(token, htm='GET'))

    def test_refuses_an_old_proof(self):
        token = self.issuer.token(self.device.jkt)
        proof = self.device.proof(token, iat=int(time.time()) - 3600)
        with self.assertRaisesRegex(AuthError, 'too old'):
            self.check(token, proof)

    def test_refuses_a_replayed_proof(self):
        token = self.issuer.token(self.device.jkt)
        proof = self.device.proof(token)
        self.check(token, proof)
        with self.assertRaisesRegex(AuthError, 'used before'):
            self.check(token, proof)

    def test_refuses_a_proof_for_another_token(self):
        token = self.issuer.token(self.device.jkt)
        other = self.issuer.token(self.device.jkt, webid=WEB_ID + 'x')
        with self.assertRaisesRegex(AuthError, 'another access token'):
            self.check(token, self.device.proof(other))

    def test_refuses_a_web_id_outside_the_prefixes(self):
        auth = Authenticator(
            AuthConfig(issuers=[ISSUER],
                       web_id_prefixes=['https://pod.example.org/bob/']),
            IssuerKeys(fetch=self.issuer.fetch))
        token = self.issuer.token(self.device.jkt)
        with self.assertRaisesRegex(AuthError, 'may not use'):
            auth.authenticate(self.headers(token, self.device.proof(token)),
                              'POST', URL)

    def test_keys_are_cached(self):
        for _ in range(3):
            token = self.issuer.token(self.device.jkt)
            self.check(token, self.device.proof(token))
        self.assertEqual(self.issuer.fetches, 2)

    def test_anonymous_allowed_only_when_not_required(self):
        auth = Authenticator(AuthConfig(required=False),
                             IssuerKeys(fetch=self.issuer.fetch))
        self.assertIsNone(auth.authenticate({}, 'POST', URL))


class UrlTest(unittest.TestCase):
    def test_normal_url(self):
        self.assertEqual(normal_url('HTTPS://Faces.Example.org:443/v1/faces?x#y'),
                         'https://faces.example.org/v1/faces')
        self.assertEqual(normal_url('http://localhost:8765/v1/faces'),
                         'http://localhost:8765/v1/faces')

    def test_thumbprint_matches_rfc_7638(self):
        # The example in RFC 7638, section 3.1.
        jwk = {
            'kty': 'RSA', 'e': 'AQAB', 'alg': 'RS256',
            'kid': '2011-04-29',
            'n': '0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAt'
                 'VT86zwu1RK7aPFFxuhDR1L6tSoc_BJECPebWKRXjBZCiFV4n3oknjhMstn6'
                 '4tZ_2W-5JsGY4Hc5n9yBXArwl93lqt7_RN5w6Cf0h4QyQ5v-65YGjQR0_FD'
                 'W2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5hajrn1n9'
                 '1CbOpbISD08qNLyrdkt-bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINH'
                 'aQ-G_xBniIqbw0Ls1jF44-csFCur-kEgU8awapJzKnqDKgw',
        }
        self.assertEqual(jwk_thumbprint(jwk),
                         'NzbLsXh8uDCcd-6MNwXF4W_7noWXFZAfHkxZsRGC9Xs')


if __name__ == '__main__':
    unittest.main()

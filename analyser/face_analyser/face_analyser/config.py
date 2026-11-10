"""Configuration for the PhotoPod face analyser.

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

# Everything lives in one YAML file (see `config.example.yaml`), including the
# address of the Analyser Pod. Its secrets can instead be supplied through the
# environment, which is what the systemd unit does, so that they never sit in a
# readable file:
#
#     PHOTOPOD_FACE_ANALYSER_SECURITY_KEY   the Analyser Pod's security key
#     PHOTOPOD_FACE_ANALYSER_CLIENT_ID      client credentials issued by the
#     PHOTOPOD_FACE_ANALYSER_CLIENT_SECRET  server for the Analyser account
#
# The section and field names the modules shared with HealthPod's analyser
# read (`analyser`, `sharing`) are kept as they are there.

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

from . import pod_paths as paths
from .auth import AuthConfig
from .engine import EngineConfig

ENV_SECURITY_KEY = 'PHOTOPOD_FACE_ANALYSER_SECURITY_KEY'
ENV_CLIENT_ID = 'PHOTOPOD_FACE_ANALYSER_CLIENT_ID'
ENV_CLIENT_SECRET = 'PHOTOPOD_FACE_ANALYSER_CLIENT_SECRET'


class ConfigError(Exception):
    """Raised when the configuration file is missing or incoherent."""


@dataclass
class AnalyserConfig:
    """Identity and credentials of the Analyser Pod."""

    web_id: str
    app_dir_name: str = 'photopod'
    server_url: str = ''
    security_key: str = ''
    client_id: str = ''
    client_secret: str = ''
    request_timeout: float = 30.0

    def __post_init__(self) -> None:
        if not self.web_id:
            raise ConfigError('analyser.web_id must be set')
        if not self.server_url:
            self.server_url = paths.server_of(self.web_id)
        self.server_url = self.server_url.rstrip('/')

    @property
    def pod_root(self) -> str:
        """The Analyser Pod root URL, with a trailing slash."""

        return paths.pod_root(self.web_id)


@dataclass
class InboxConfig:
    """Where in each user's Pod PhotoPod leaves photos for the analyser."""

    # The folder inside PhotoPod's data folder. PhotoPod shares it, and only
    # it, with the Analyser. Must match `faceInboxFolderName` in PhotoPod's
    # lib/services/face_inbox.dart.

    folder: str = '.faces-inbox'

    # The most photos analysed in one run for one Pod, so that one large
    # backlog cannot hold up everybody else. The rest wait for the next run.

    max_per_run: int = 40

    @property
    def fragment(self) -> str:
        """What the URL of a shared inbox ends with."""

        return f'/{paths.DATA_DIR}/{self.folder.strip("/")}/'


@dataclass
class SharingConfig:
    """How results are written back to the contributing Pods."""

    # The folder inside the Analyser Pod's data folder holding one results
    # file per Pod.

    results_dir: str = 'faces'

    # A line in the recipient's permission log is how solidpod lists what was
    # shared with someone. PhotoPod finds the results by their address, and a
    # line there would only put the results file among the user's shared
    # photos, so it is off.

    write_permission_log: bool = False
    encrypt_results: bool = True


@dataclass
class ServiceConfig:
    """The HTTP interface PhotoPod calls to ask for a run."""

    host: str = '127.0.0.1'
    port: int = 8765

    # The URL PhotoPod calls the service at, as seen from outside, without
    # /v1/... The DPoP proof on each request names it, so it must be right
    # behind a reverse proxy. Blank: worked out from each request's headers.

    public_url: str = ''

    # Browser origins allowed to call the service, for PhotoPod's web build.

    cors_origins: list[str] = field(default_factory=lambda: ['*'])

    # How often, in seconds, every shared inbox is looked at for photos left
    # by an app that closed before asking. 0 turns the sweep off, leaving
    # only the runs apps ask for.

    poll_seconds: int = 300

    # The longest request body accepted, which only ever carries a list of
    # names.

    max_body_bytes: int = 256 * 1024


@dataclass
class Config:
    analyser: AnalyserConfig
    inbox: InboxConfig
    sharing: SharingConfig
    service: ServiceConfig
    auth: AuthConfig
    engine: EngineConfig
    source_path: Path | None = None
    warnings: list[str] = field(default_factory=list)

    def require_credentials(self) -> None:
        """Fail early, and with a useful message, when a secret is missing."""

        missing = []
        if not self.analyser.client_id:
            missing.append(f'analyser.credentials.client_id (${ENV_CLIENT_ID})')
        if not self.analyser.client_secret:
            missing.append(
                f'analyser.credentials.client_secret (${ENV_CLIENT_SECRET})')
        if not self.analyser.security_key:
            missing.append(f'analyser.security_key (${ENV_SECURITY_KEY})')
        if missing:
            raise ConfigError(
                'missing credentials: ' + ', '.join(missing)
                + '. See README.md, section "Preparing the Analyser Pod".')


def _section(data: dict[str, Any], name: str) -> dict[str, Any]:
    value = data.get(name) or {}
    if not isinstance(value, dict):
        raise ConfigError(f'{name} must be a mapping')
    return dict(value)


def _build(cls: type, values: dict[str, Any], name: str) -> Any:
    known = cls.__dataclass_fields__
    unknown = sorted(set(values) - set(known))
    if unknown:
        raise ConfigError(f'Unknown setting(s) in {name}: {", ".join(unknown)}')
    try:
        return cls(**values)
    except (TypeError, ValueError) as e:
        raise ConfigError(f'{name}: {e}') from e


def load(path: Path) -> Config:
    """The configuration in [path]. Relative paths in it are taken from the
    folder the file is in."""

    path = Path(path).expanduser()
    if not path.exists():
        raise ConfigError(
            f'{path} not found. Run ./setup.sh, or copy config.example.yaml.')
    try:
        data = yaml.safe_load(path.read_text()) or {}
    except yaml.YAMLError as e:
        raise ConfigError(f'{path} is not valid YAML: {e}') from e
    if not isinstance(data, dict):
        raise ConfigError(f'{path} must hold a mapping')

    base = path.resolve().parent

    analyser = _section(data, 'analyser')
    credentials = analyser.pop('credentials', None) or {}
    analyser['security_key'] = (os.environ.get(ENV_SECURITY_KEY)
                                or str(analyser.get('security_key') or ''))
    analyser['client_id'] = (os.environ.get(ENV_CLIENT_ID)
                             or str(credentials.get('client_id') or ''))
    analyser['client_secret'] = (os.environ.get(ENV_CLIENT_SECRET)
                                 or str(credentials.get('client_secret') or ''))

    engine = _section(data, 'engine')
    models_dir = Path(engine.get('models_dir') or 'var/models')
    engine['models_dir'] = (models_dir if models_dir.is_absolute()
                            else base / models_dir)

    config = Config(
        analyser=_build(AnalyserConfig, analyser, 'analyser'),
        inbox=_build(InboxConfig, _section(data, 'inbox'), 'inbox'),
        sharing=_build(SharingConfig, _section(data, 'sharing'), 'sharing'),
        service=_build(ServiceConfig, _section(data, 'service'), 'service'),
        auth=_build(AuthConfig, _section(data, 'auth'), 'auth'),
        engine=_build(EngineConfig, engine, 'engine'),
        source_path=path.resolve(),
    )
    if config.auth.required and not config.auth.issuers:
        raise ConfigError(
            'auth.issuers is empty, so no app could ask for a run. List the '
            'Solid servers whose users the analyser serves.')

    # A file holding the security key must not be readable by others.
    if config.analyser.security_key and not os.environ.get(ENV_SECURITY_KEY):
        mode = path.stat().st_mode & 0o777
        if mode & 0o077:
            config.warnings.append(
                f'{path} holds the security key and is readable by others '
                f'(mode {mode:o}); run chmod 600 {path}')
    return config

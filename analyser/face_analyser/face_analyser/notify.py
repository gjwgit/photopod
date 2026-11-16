"""Solid Notifications: being told when the Analyser's shared keys change.

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

Authors: Graham Williams
"""

# A user asks for the people in some photos by sharing their face inbox with
# the Analyser, and sharing writes into the Analyser's own shared-keys file.
# Rather than read that file on a timer, the service asks the Solid server to
# say when it changes, through the Solid Notifications Protocol
# (https://solidproject.org/TR/notifications-protocol):
#
#   1. the Analyser Pod's storage description, `<pod>/.well-known/solid`,
#      names the server's subscription services, one per kind of channel;
#   2. a POST to the WebSocketChannel2023 service, naming the shared-keys file
#      as the topic, returns `receiveFrom`, a WebSocket address;
#   3. the server sends a message down that socket each time the file
#      changes. What a message says is not needed: any change is a reason to
#      read the file again.
#
# Only the Analyser's own Pod is subscribed to. No user's Pod is read until
# that user has asked.

from __future__ import annotations

import json
from collections.abc import Iterator

from rdflib import URIRef

from . import turtle
from .solid_client import SolidClient, SolidError

NOTIFY = 'http://www.w3.org/ns/solid/notifications#'
WEBSOCKET_CHANNEL = NOTIFY + 'WebSocketChannel2023'


class NotificationError(SolidError):
    """Raised when the server offers no way to be told of changes."""


def subscription_service(client: SolidClient, storage_root: str) -> str:
    """The address to subscribe at for a WebSocket channel, from the storage
    description of the Pod rooted at [storage_root]."""

    url = storage_root.rstrip('/') + '/.well-known/solid'
    graph = turtle.parse(client.get_text(url), base=url)
    for service in graph.objects(None, URIRef(NOTIFY + 'subscription')):
        if (service, URIRef(NOTIFY + 'channelType'),
                URIRef(WEBSOCKET_CHANNEL)) in graph:
            return str(service)
    raise NotificationError(
        f'{url} offers no WebSocketChannel2023 subscription service')


def subscribe(client: SolidClient, storage_root: str, topic: str) -> str:
    """Ask to be told whenever [topic] changes, returning the WebSocket
    address the server will say so on."""

    service = subscription_service(client, storage_root)
    response = client.request(
        'POST', service,
        content=json.dumps({
            '@context': ['https://www.w3.org/ns/solid/notification/v1'],
            'type': WEBSOCKET_CHANNEL,
            'topic': topic,
        }).encode('utf-8'),
        content_type='application/ld+json',
        headers={'Accept': 'application/ld+json'},
    )
    if not 200 <= response.status_code < 300:
        raise NotificationError(
            f'subscribing to {topic}: HTTP {response.status_code}: '
            f'{response.text[:200]}', response.status_code)
    receive_from = response.json().get('receiveFrom')
    if not receive_from:
        raise NotificationError(f'subscribing to {topic}: no receiveFrom')
    return receive_from


def messages(receive_from: str) -> Iterator[str]:
    """Each message the server sends on [receive_from], until it closes."""

    from websockets.sync.client import connect

    with connect(receive_from, open_timeout=30) as socket:
        for message in socket:
            yield message if isinstance(message, str) else message.decode()

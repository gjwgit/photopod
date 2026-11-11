#!/usr/bin/env bash
#
# Run the PhotoPod face analyser from its virtual environment.
#
# Copyright (C) 2026, Software Innovation Institute, ANU.
#
# Licensed under the GNU General Public License, Version 3 (the "License").
#
# License: https://opensource.org/license/gpl-3-0.
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see https://opensource.org/license/gpl-3-0.
#
# Authors: Tony Chen
#
#   ./run.sh check            verify the models and the Analyser Pod
#   ./run.sh watch            look at the shared inboxes, for ever (systemd)
#   ./run.sh run-once [WEBID] one look at a Pod's inbox, or at every one
#   ./run.sh fetch-models     download the two models into var/models
#   ./run.sh analyse PHOTO... the faces in local photos, as JSON
#   ./run.sh test             the offline test suite
#
# Everything runs from this directory, the project root: it holds the
# `face_analyser` package, the configuration, the tests and the virtual
# environment, so the package resolves without any path juggling.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

if [ ! -x .venv/bin/python ]; then
  echo "The virtual environment is missing. Run ./setup.sh first." >&2
  exit 1
fi

if [ "${1:-}" = 'test' ]; then
  shift
  exec ./.venv/bin/python -m unittest discover -s tests -t . "$@"
fi

config="${PHOTOPOD_FACE_ANALYSER_CONFIG:-$here/config.yaml}"

exec ./.venv/bin/python -m face_analyser --config "$config" "$@"

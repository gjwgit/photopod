#!/usr/bin/env bash
#
# Create the virtual environment for the PhotoPod face analyser, fetch its two
# models and write config.yaml from the example.
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
# Run from the project root: it creates .venv, var/models and config.yaml
# beside the `face_analyser` package.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

python="${PYTHON:-python3}"

# A copy made over SFTP, or unpacked from an archive that does not carry
# permissions, arrives without the execute bit.

chmod +x run.sh setup.sh 2>/dev/null || \
  echo "Note: could not set the execute bit; invoke the scripts as 'bash run.sh'."

# A .venv that came with the copy belongs to whoever built it, not to this
# host, so one whose interpreter does not run here is rebuilt.

if [ -e .venv ] && ! ./.venv/bin/python -c '' 2>/dev/null; then
  echo "==> Discarding an unusable .venv (built elsewhere, or broken)"
  rm -rf .venv
fi

if [ -d .venv ]; then
  echo "==> Reusing the virtual environment in $here/.venv"
else
  echo "==> Creating the virtual environment in $here/.venv"
  "$python" -m venv .venv
fi

echo "==> Installing dependencies"
./.venv/bin/pip install --upgrade pip >/dev/null
./.venv/bin/pip install -r requirements.txt

find . -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true
find . -name '.DS_Store' -delete 2>/dev/null || true

if [ ! -f config.yaml ]; then
  echo "==> Creating config.yaml from the example"
  cp config.example.yaml config.yaml
  chmod 600 config.yaml
  echo "    Edit config.yaml: the Analyser's security key and client"
  echo "    credentials are required (or set them in the environment)."
fi

# The models are fetched now rather than on the first request, so that the
# service never has to reach GitHub while a user waits, and so that systemd's
# read-only sandbox has nothing to write.

echo "==> Fetching the face and tag models into var/models (275 MB and 372 MB, once)"
mkdir -p var/models
./.venv/bin/python -m face_analyser --config config.yaml fetch-models

echo
echo "Done. Verify the set-up with:"
echo "    ./run.sh check"

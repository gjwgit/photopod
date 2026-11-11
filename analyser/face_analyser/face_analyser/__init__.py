"""PhotoPod face analyser: finds and describes the faces in a photo.

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

__version__ = '0.1.0'

# Which models produce the embeddings: InsightFace's buffalo_l detector and
# recogniser (see models.py). PhotoPod stores this beside every face it keeps
# and starts its faces file afresh when it changes, since embeddings from
# different models cannot be compared. It must match `faceModelId` in
# PhotoPod's lib/models/face_book.dart.

MODEL_ID = 'buffalo_l:scrfd-10g+arcface-w600k-r50'

#!/usr/bin/env python3
"""Build assets/places/regions.tsv, the places PhotoPod groups photos under.

Copyright (C) 2026, Togaware Pty Ltd.

Licensed under the GNU General Public License, Version 3 (the "License").

License: https://opensource.org/license/gpl-3-0

Authors: Tony Chen

The places come from GeoNames (https://www.geonames.org/), licensed under
Creative Commons Attribution 4.0. Download these into one folder:

    https://download.geonames.org/export/dump/cities15000.zip  (unzipped)
    https://download.geonames.org/export/dump/countryInfo.txt
    https://download.geonames.org/export/dump/admin1CodesASCII.txt

and run

    python3 support/make_place_regions.py <that folder> > assets/places/regions.tsv

Only national capitals and the seats of first- and second-level
administrative divisions are kept, so that a photo is placed under the city
it belongs to, such as Canberra rather than one of its suburbs, while a
city such as Nice keeps a name of its own rather than being folded into
Marseille.
"""

import sys
from collections import Counter
from pathlib import Path

# The seats of government GeoNames marks: a national capital, and the seat of
# a first- or second-level administrative division.

KEPT = {"PPLC", "PPLA", "PPLA2"}

# Places that are, for a photo album's purposes, one city, and are named on
# their own rather than by the districts GeoNames divides them into.

CITY_STATES = {"SG", "HK", "MO", "MC", "VA", "GI"}


def rows(path):
    with open(path, encoding="utf-8") as lines:
        for line in lines:
            if line.startswith("#") or not line.strip():
                continue
            yield line.rstrip("\n").split("\t")


def main(folder):
    folder = Path(folder)
    countries = {row[0]: row[4] for row in rows(folder / "countryInfo.txt")}
    admin1 = {row[0]: row[1] for row in rows(folder / "admin1CodesASCII.txt")}

    places = []
    for row in rows(folder / "cities15000.txt"):
        if row[7] not in KEPT:
            continue
        code = row[8]
        country = countries.get(code)
        if country is None:
            continue
        if code in CITY_STATES:
            name, state = country, None
        else:
            name, state = row[1], admin1.get(f"{code}.{row[10]}")
        places.append((name, state, country, float(row[4]), float(row[5])))

    # A name a country uses more than once, such as Portland in the United
    # States, is told apart by the state or province it is in.

    repeated = Counter((name, country) for name, _, country, _, _ in places)
    states = {}
    for name, state, country, _, _ in places:
        states.setdefault((name, country), set()).add(state)

    print("# Places PhotoPod groups photos under: label, latitude, longitude.")
    print("# Built by support/make_place_regions.py from GeoNames data,")
    print("# https://www.geonames.org/, licensed under CC BY 4.0.")
    lines = set()
    for name, state, country, latitude, longitude in places:
        parts = [name]
        if (
            repeated[(name, country)] > 1
            and len(states[(name, country)]) > 1
            and state
            and state != name
        ):
            parts.append(state)
        if country != name:
            parts.append(country)
        lines.add(f"{', '.join(parts)}\t{latitude:.4f}\t{longitude:.4f}")
    for line in sorted(lines):
        print(line)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")

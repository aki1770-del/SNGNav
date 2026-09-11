#!/usr/bin/env python3
"""Build a databroker VSS tree for a vehicle that LACKS some sensors.

Why this exists
---------------
`kuksa.val.v2` Subscribe is all-or-nothing: one VSS leaf the vehicle does not
have and the whole subscription dies `NOT_FOUND`, delivering nothing for the
leaves it does have. Measured 2026-09-11 against `kuksa-databroker:0.7.1`.

Every broker fixture we had was a FULL VSS 6.0 tree, which knows every leaf —
so the defect was unreproducible in test and "a vehicle that lacks a leaf"
stayed a thought experiment while it was live on `main`. This makes it a
fixture.

    docker cp <broker>:/vss_release_6.0.json vss_full.json
    python3 make_partial_vehicle.py vss_full.json out.json \
        Vehicle.Chassis.Axle.Row1.Wheel.Left.Tire.Pressure \
        Vehicle.Exterior.Humidity
    docker run -d -p 55557:55555 -v "$PWD/out.json":/v.json:ro \
        ghcr.io/eclipse-kuksa/kuksa-databroker:0.7.1 \
        --insecure --address 0.0.0.0 --port 55555 --vss /v.json
"""
import json
import sys


def drop(tree, dotted):
    """Remove one VSS leaf. Returns True if it was there to remove."""
    parts = dotted.split('.')
    if parts[0] != 'Vehicle':
        raise SystemExit(f'not a Vehicle path: {dotted}')
    node = tree['Vehicle']
    for p in parts[1:-1]:
        children = node.get('children')
        if not children or p not in children:
            return False
        node = children[p]
    return node.get('children', {}).pop(parts[-1], None) is not None


def main(argv):
    if len(argv) < 4:
        raise SystemExit(__doc__)
    src, dst, leaves = argv[1], argv[2], argv[3:]
    with open(src) as fh:
        tree = json.load(fh)
    for leaf in leaves:
        # An absent leaf is reported, never silently accepted: a fixture that
        # did not remove what it claims to remove is a fixture that proves
        # nothing, and it would pass exactly like one that worked.
        print(f'{"removed" if drop(tree, leaf) else "NOT PRESENT":>12}  {leaf}')
    with open(dst, 'w') as fh:
        json.dump(tree, fh)
    print(f'wrote {dst}')


if __name__ == '__main__':
    main(sys.argv)

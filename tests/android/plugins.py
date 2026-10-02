#!/usr/bin/env python3
"""The Android project's package.json lists exactly the plugins of
bridge's table (bridge's src/plugins.bats), each at its version, besides
Capacitor's own core and Android platform (bridge#119).

usage: tests/android/plugins.py <package.json> <bridge's plugins.bats>
"""
import json
import re
import sys

package_json, table = sys.argv[1], sys.argv[2]
source = open(table).read()


def column(function):
    """The constructor -> string map of the table's function."""
    body = source.split("implement %s (p) =" % function, 1)[1].split("implement", 1)[0]
    return dict(re.findall(r'\|\s*(Plugin\w+)\(\)\s*=>\s*"([^"]+)"', body))


packages, versions = column("plugin_package"), column("plugin_version")
assert packages and packages.keys() == versions.keys(), "bridge's table could not be read"
expected = {packages[p]: versions[p] for p in packages}
expected["@capacitor/android"] = "^8.1.0"
expected["@capacitor/core"] = "^8.1.0"
dependencies = json.load(open(package_json))["dependencies"]
if dependencies != expected:
    print("package.json's dependencies are not bridge's plugins:")
    for name in sorted(set(dependencies) | set(expected)):
        if dependencies.get(name) != expected.get(name):
            print("  %s: package.json %s, bridge %s" % (name, dependencies.get(name), expected.get(name)))
    sys.exit(1)
print("package.json lists bridge's %d plugins" % len(packages))

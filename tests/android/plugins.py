#!/usr/bin/env python3
"""The Android project's package.json lists exactly the plugins of
bridge's table (bridge's src/plugins.bats) that are packages of their
own (plugin_origin Package), each at its source (plugin_source: a
registry's range, or a GitHub repository's directory at a commit),
besides Capacitor's own core and Android platform (bridge#119).

usage: tests/android/plugins.py <package.json> <bridge's plugins.bats>
"""
import json
import re
import sys

package_json, table = sys.argv[1], sys.argv[2]
source = open(table).read()


def body(function):
    """The text of the table's function."""
    return source.split("implement %s (p) =" % function, 1)[1].split("implement", 1)[0]


def column(function):
    """The constructor -> string map of the table's function."""
    return dict(re.findall(r'\|\s*(Plugin\w+)\(\)\s*=>\s*"([^"]+)"', body(function)))


def sources():
    """The constructor -> package.json value map of plugin_source: a
    registry's range, or a GitHub repository's directory at a commit."""
    found = {}
    for plugin, kind, args in re.findall(r'\|\s*(Plugin\w+)\(\)\s*=>\s*(Registry|Git)\(([^)]*)\)', body("plugin_source")):
        values = re.findall(r'"([^"]*)"', args)
        if kind == "Registry":
            found[plugin] = values[0]
        else:
            repository, commit, path = values
            found[plugin] = "github:%s#%s&path:%s" % (repository, commit, path)
    return found


origins = dict(re.findall(r'\|\s*(Plugin\w+)\(\)\s*=>\s*(CapacitorCore|Package)\(\)', body("plugin_origin")))
packages, versions = column("plugin_package"), sources()
assert packages and packages.keys() == versions.keys() == origins.keys(), "bridge's table could not be read"
# a plugin Capacitor's Android runtime has is no dependency of its own
expected = {packages[p]: versions[p] for p in packages if origins[p] == "Package"}
expected["@capacitor/android"] = "^8.1.0"
expected["@capacitor/core"] = "^8.1.0"
dependencies = json.load(open(package_json))["dependencies"]
if dependencies != expected:
    print("package.json's dependencies are not bridge's plugins:")
    for name in sorted(set(dependencies) | set(expected)):
        if dependencies.get(name) != expected.get(name):
            print("  %s: package.json %s, bridge %s" % (name, dependencies.get(name), expected.get(name)))
    sys.exit(1)
print("package.json lists bridge's %d plugins" % (len(expected) - 2))

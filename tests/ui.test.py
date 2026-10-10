#!/usr/bin/env python3
"""Test the actual Panel.qml field bindings without starting a desktop or server."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

here = Path(__file__).resolve().parent.parent
runner = shutil.which("qmltestrunner") or "/usr/lib/qt6/bin/qmltestrunner"
source = (here / "Panel.qml").read_text()
fields = []
for name in ("portField", "extraField"):
    start = source.rfind("TextField {", 0, source.index("id: " + name))
    depth = 0
    for i in range(start + len("TextField "), len(source)):
        depth += (source[i] == "{") - (source[i] == "}")
        if depth == 0:
            field = source[start:i + 1]
            # The house TextField inherits Qt Controls; stub only its styling.
            field = field.replace("id: " + name, "id: " + name + "\nproperty color foreground")
            fields.append(field.replace("Style.space", "root.space"))
            break

with tempfile.TemporaryDirectory(prefix="omallama-qml-") as directory:
    directory = Path(directory)
    shutil.copyfile(here / "Model.js", directory / "Model.js")
    (directory / "tst_fields.qml").write_text('''import QtQuick
import QtQuick.Controls
import QtTest
import "Model.js" as Model
Item {
  id: root
  width: 600; height: 200
  property color foreground: "white"
  property var sample: ({ port: 8080, extraArgs: "--threads 2" })
  property var saved: ({})
  function space(n) { return n }
  function setKey(key, value) { saved = { key: key, value: value } }
''' + "\n".join(fields) + '''
  TestCase {
    name: "SettingsDrafts"
    when: windowShown
    function test_refresh() {
      compare(portField.text, "8080")
      compare(extraField.text, "--threads 2")
      portField.text = "9090"; portField.textEdited()
      extraField.text = "--threads 6"; extraField.textEdited()
      root.sample = { port: 8080, extraArgs: "--threads 2" }
      wait(2200)
      compare(portField.text, "9090")
      compare(extraField.text, "--threads 6")
      extraField.accepted()
      compare(root.saved.key, "LLM_EXTRA"); compare(root.saved.value, "--threads 6")
      portField.accepted()
      compare(root.saved.key, "LLM_PORT"); compare(root.saved.value, "9090")
      root.sample = { port: 9090, extraArgs: "--threads 6" }
      portField.dirty = false; extraField.dirty = false
      wait(50)
      compare(portField.text, "9090")
      compare(extraField.text, "--threads 6")
      root.sample = { port: 8081, extraArgs: "--threads 3" }
      wait(50)
      compare(portField.text, "8081")
      compare(extraField.text, "--threads 3")
    }
  }
}
''')
    subprocess.run([runner, "-input", str(directory)],
                   env={**os.environ, "QT_QPA_PLATFORM": "offscreen"}, check=True)

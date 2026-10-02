"""Write a minimal tak-shaped bundle (web/index.html, web/game.zip, version.txt) for tests."""
import os
import sys
import zipfile

version = sys.argv[1] if len(sys.argv) > 1 else "1.0.0"
os.makedirs("web", exist_ok=True)
with open("web/index.html", "w") as page:
    page.write("<html><title>fixture %s</title></html>\n" % version)
with zipfile.ZipFile("web/game.zip", "w") as bundle:
    for name in ("boot.js", "client.css", "client.js", "game-worker.js"):
        bundle.writestr("src/tak/web/assets/" + name, "/* %s */" % name)
with open("version.txt", "w") as out:
    out.write(version + "\n")

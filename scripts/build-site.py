from __future__ import annotations

import base64
import shutil
from pathlib import Path


ROOT_DIR = Path.cwd()
DIST_DIR = ROOT_DIR / "dist"
SITE_FILES = ["index.html", "styles.css", "app.js"]
DATA_FILES = ["data/database.txt"]


def main() -> None:
    if DIST_DIR.exists():
        shutil.rmtree(DIST_DIR)
    DIST_DIR.mkdir(parents=True, exist_ok=True)

    for file_name in SITE_FILES + DATA_FILES:
        source = ROOT_DIR / file_name
        if source.exists():
            destination = DIST_DIR / file_name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

    database_path = ROOT_DIR / "data/database.txt"
    if database_path.exists():
        database_text = database_path.read_text(encoding="utf-8")
        encoded = base64.b64encode(database_text.encode("utf-8")).decode("ascii")
        (DIST_DIR / "local-database.js").write_text(
            f"window.LOCAL_DATABASE_TEXT = atob('{encoded}');",
            encoding="utf-8",
        )

    print("Site package hazır.")


if __name__ == "__main__":
    main()

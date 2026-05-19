from __future__ import annotations

import shutil
from pathlib import Path


ROOT_DIR = Path.cwd()
DIST_DIR = ROOT_DIR / "dist"
SITE_FILES = ["index.html", "styles.css", "app.js"]
DATA_FILES = ["data/database.txt"]


def main() -> None:
    (DIST_DIR / "data").mkdir(parents=True, exist_ok=True)

    for file_name in SITE_FILES + DATA_FILES:
        source = ROOT_DIR / file_name
        if source.exists():
            shutil.copy2(source, DIST_DIR / file_name)

    print("Site package hazır.")


if __name__ == "__main__":
    main()

from __future__ import annotations

import shutil
from pathlib import Path


ROOT_DIR = Path.cwd()
DIST_DIR = ROOT_DIR / "dist"
SITE_FILES = ["index.html", "styles.css", "app.js", "supabase.config.js", "local-database.js"]
DATA_FILES = []


def main() -> None:
    if DIST_DIR.exists():
        shutil.rmtree(DIST_DIR)
    DIST_DIR.mkdir(parents=True, exist_ok=True)

    for file_name in SITE_FILES + DATA_FILES:
        source = ROOT_DIR / file_name
        if source.exists():
            shutil.copy2(source, DIST_DIR / file_name)

    print("Site package hazır.")


if __name__ == "__main__":
    main()

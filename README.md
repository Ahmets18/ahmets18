# Siparis Sunucusu

Bu proje, `xlsm` dosyalarindan uretilen siparis verisini GitHub Pages uzerinde yayinlayan takip sitesidir.

## Akis

1. `scripts/sync-from-share.ps1` son 45 gunluk `xlsm` dosyalarini tarar.
2. Script `data/database.txt` dosyasini gunceller.
3. `local-database.js` ve site paketi ayni veriyle yenilenir.
4. GitHub Pages, `data/database.txt` uzerinden son veriyi okur.

## Calistirma

Yerel build uretmek icin:

```powershell
& 'C:\Users\PC\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' .\scripts\build-site.py
```

## Not

Arayuz, giris yapildiktan sonra yerel/GitHub veri dosyasini okur.

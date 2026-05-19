# Siparis Sunucusu

Bu proje, `xlsm` dosyalarindan ureyen siparis verisini Supabase'te tutan ve GitHub Pages uzerinde arayuz olarak yayinlayan takip sitesidir.

## Akis

1. `scripts/sync-from-share.ps1` son 1 gunluk `xlsm` dosyalarini tarar.
2. Script `data/database.txt` dosyasini gunceller.
3. Veri Supabase'e aktarilir.
4. GitHub Pages login sonrasinda Supabase verisini okur.

## Calistirma

Yerel build uretmek icin:

```powershell
& 'C:\Users\PC\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' .\scripts\build-site.py
```

## Supabase

`supabase.config.js` icine:

- `url`
- `anonKey`
- `table`

degerlerini gir.

Yerel senkron icin `secrets/supabase.local.json` dosyasini kullan:

- `url`
- `serviceKey`
- `table`

Bu dosya git'e girmez ve zamanlanmis gorevden bagimsiz calisir.

## Not

Arayuz, giris yapildiktan sonra Supabase'teki `orders` tablosundan veri okur.

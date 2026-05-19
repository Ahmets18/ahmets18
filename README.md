# Siparis Sunucusu

Bu proje, `xlsm` dosyalarindan ureyen siparis verisini Supabase'te tutan ve GitHub Pages uzerinde arayuz olarak yayinlayan takip sitesidir.

## Akis

1. `scripts/sync-from-share.ps1` son 1 gunluk `xlsm` dosyalarini tarar.
2. Script `data/database.txt` dosyasini gunceller.
3. Script `exports/orders.supabase.csv` ve `exports/orders.supabase.json` dosyalarini otomatik uretir.
4. Script `data/database.txt` icin olusan kayitlari Supabase `orders` tablosuna otomatik yazar.
5. Bu dosyalar Supabase `orders` tablosu ile ayni sahayi kullanir.
6. GitHub Pages login sonrasinda Supabase verisini okur.
7. Windows gorevi gizli calismasi icin `scripts/run-sync-hidden.cmd` veya `scripts/run-sync-hidden.ps1` kullanilir.

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

## Export

`scripts/export-for-supabase.ps1`:

- `data/database.txt` dosyasini yeni Supabase semasina cevirir
- `exports/orders.supabase.csv` ve `exports/orders.supabase.json` dosyalarini uretir
- Bunlar Supabase tarafinda manuel import icin kullanilir

`scripts/push-to-supabase.ps1`:

- `data/database.txt` icerigini `orders` tablosuna yazar
- Yerel `secrets/supabase.local.json` dosyasini veya ortam degiskenlerini kullanir
- `sync-from-share.ps1` sonunda otomatik cagirilir

## Not

Arayuz, giris yapildiktan sonra Supabase'teki `orders` tablosundan veri okur.

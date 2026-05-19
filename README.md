# Siparis Sunucusu

Bu proje, `xlsm` dosyalarindan uretilen tek bir `data/database.txt` dosyasini GitHub Pages uzerinde yayinlayan basit siparis takip sitesidir.

## Akis

1. Ağ klasorundeki son 30 gunluk `xlsm` dosyalari yerelde `scripts/sync-from-share.ps1` ile okunur.
2. Script `data/database.txt` dosyasini gunceller.
3. Bu tek dosya repoya push edilir.
4. GitHub Actions siteyi paketler ve GitHub Pages'e yayinlar.

## Tek Elle Tutulan Dosya

- `data/database.txt`

Site veri kaynagı olarak sadece bu dosyayi kullanir.

## Calistirma

Yerel bilgisayarda:

```powershell
.\scripts\sync-from-share.ps1
```

Varsayilan kaynak klasor:

```powershell
\\ARTI\Schelling\YEDEK LİSTELER
```

## GitHub Pages

Repository ayarlarinda GitHub Pages kaynagi olarak `GitHub Actions` secili olmali.

## Not

Bu ilk surumde arama ekrani, musterI adina gore son siparisleri listeler. Istersen sonra tarih filtresi, durum filtreleri ve detay gorunumu de ekleyebilirim.

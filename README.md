# MoeCatnip
A UWP client for Moebooru. 
Both Yandere and Konachan are supported.
~~The app also includes a client for ExHentai.~~



Very dirty coding sytle.


Download:
~~https://www.microsoft.com/store/p/prpr/9nblggh4stnm~~

The app has been removed from the store by Microsoft.
You can download an offline package by other developers: https://github.com/AmazingDM/PRPR/releases/tag/2.7

---

## Flutter rewrite (Windows desktop)

The UWP sources above are kept as-is for reference. A from-scratch Flutter desktop
rewrite lives in [`app/`](app/):

- browse Moebooru sites (search, masonry grid, post detail, rating, favourites)
- anime face detection + smart crop before applying a wallpaper
- one-click "set as wallpaper" and scheduled auto-change
- daily feature, history, content-rating filters

Tile and lock-screen features are gone (Windows 11 removed tiles, and Win32 has no
stable lock-screen API). See [`MIGRATION.md`](MIGRATION.md) for the file-by-file
mapping, the deliberate behaviour changes, and the known upstream Flutter crash
([flutter/flutter#175041](https://github.com/flutter/flutter/issues/175041)).
Build/run instructions and the three build traps are in [`app/README.md`](app/README.md).




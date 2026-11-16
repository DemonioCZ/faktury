# Faktury

Aplikace pro Android a macOS na evidenci účtenek a faktur uložených na Google Disku.

- Skeny (PDF, JPG) leží ve složce na Google Disku, data v tabulce „Faktury – data“ ve stejné složce.
- Nové doklady se vyfotí v mobilu nebo nahrají do složky a údaje z nich vyčte Gemini.
- Hlídání záruky (výchozí 24 měsíců, prodloužené záruky zvlášť), štítek „Bez záruky“.
- Přehled podle měsíce a roku, filtry podle roku, kategorie a stavu záruky, vyhledávání.
- Aktualizace jedním tlačítkem z GitHub Releases.

## Vydání nové verze

1. Zvyšte `version:` v `pubspec.yaml` (např. `1.0.1+2`).
2. `git tag v1.0.1 && git push --tags`
3. GitHub Actions sestaví `Faktury-1.0.1.apk` a `Faktury-1.0.1.dmg` a přiloží je k Release.

## Secrets v GitHubu

| Název | Obsah |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | podpisový klíč `faktury-release.p12` v base64 |
| `ANDROID_KEYSTORE_PASSWORD` | heslo ke klíči |
| `GOOGLE_DESKTOP_CLIENT_ID` | OAuth klient typu Desktop (přihlášení na Macu) |
| `GOOGLE_DESKTOP_CLIENT_SECRET` | jeho secret |

## macOS bez podpisu

Při prvním spuštění klikněte na aplikaci pravým tlačítkem → Otevřít (případně Nastavení systému → Soukromí a zabezpečení → Přesto otevřít).

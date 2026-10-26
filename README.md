# Kontorskjerm

Lysbildefremvisning av «bspoke status» for TV-ene på kontoret, publisert med GitHub Pages.

- Fremvisning: `s-s76bs6c5/index.html`
- Bilder: `s-s76bs6c5/slides/*.png` (kopieres inn av `publiser.ps1`, ikke rediger her)
- Liste over bilder: `s-s76bs6c5/slides.json` (skrives av `publiser.ps1`)

## URL-parametere

| Parameter | Eksempel | Virkning |
|---|---|---|
| `s` | `?s=1,3` | Vis bare `1-*.png` og `3-*.png`. Uten parameter vises alle. |
| `t` | `?t=30` | Sekunder per bilde (standard 45). |

## Publisering

`publiser.ps1` kopierer PNG-ene fra SharePoint-mappa Kontorskjerm\Slides, skriver `slides.json`
og pusher bare hvis noe er endret. Den kjøres av Windows Oppgaveplanlegger hverdager kl. 06:30, 08:00 og 12:00.
Hver kjøring logges til `publiser.log` (ikke i git).

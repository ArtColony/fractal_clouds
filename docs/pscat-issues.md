# pscat issues log

Problems found with pscat and its agent skills while working on fractal_clouds,
kept here until they are filed against
[PSCatLabs/pscat](https://github.com/PSCatLabs/pscat/issues).

Environment unless noted: pscat 0.6.2 release bundle
(`pscat-0.6.2-aarch64-apple-darwin.tar.gz`), macOS 15 (Darwin 24.6) on arm64, no font packs
installed. Skills copied from `plugin/skills/` at tag `v0.6.2`.

Status values: `open` (not filed yet), `filed #N`, `wontfile` (with the reason).

---

## 1. Skills say the LaserWriter 35 fonts "always resolve", but they need the texgyre pack

- **Kind:** skill docs
- **Status:** open
- **Where:** `plugin/skills/pscat/SKILL.md` line 129 (Fonts), `plugin/skills/psart/SKILL.md` line 102 (Type is material)
- **Found:** 2026-10-21

The skills say: "The LaserWriter 35 always resolve (Palatino, Bookman,
AvantGarde, ZapfChancery, NewCenturySchlbk, Symbol, ZapfDingbats, …)". On a
bare release install, only Helvetica, Times and Courier (12 faces) resolve.
The rest belong to the `texgyre` font pack, and `findfont` raises an error:

```
$ echo '/Bookman-Demi findfont pop' | pscat --headless -
%%[ Error: invalidfont; OffendingCommand: findfont; Line: 1 ]%%
pscat: font /Bookman-Demi is in the texgyre font pack, which is not installed; run `pscat fonts install` (or `pscat fonts install --pack texgyre`)
```

`pscat --fonts` on the same install lists only Helvetica, Times and Courier.

**Suggested fix:** say that only Helvetica, Times and Courier are built in, and
that the rest of the LaserWriter 35 come from `pscat fonts install`
(`--pack texgyre`). Or bundle texgyre in the release archive.

## 2. Skills say unknown font names "substitute Helvetica", but pack fonts error out

- **Kind:** skill docs (possibly a behaviour question)
- **Status:** open
- **Where:** `plugin/skills/pscat/SKILL.md` (Fonts: "Unknown names substitute Helvetica rather than erroring"), `plugin/skills/psart/SKILL.md` ("an unknown name silently becomes Helvetica")
- **Found:** 2026-10-21

The fallback happens only for names pscat has never heard of. A name that
belongs to an uninstalled font pack raises `invalidfont` (see #1):

```
$ echo '/NoSuchFont-Bold findfont 12 scalefont setfont 10 10 moveto (x) show' | pscat --headless -   # exit 0, Helvetica
$ echo '/Palatino-Italic findfont pop' | pscat --headless -                                          # exit 1, invalidfont
```

The error message is useful, but an agent that trusts the skill expects a
fallback, not a failed render.

**Suggested fix:** describe both cases in the skills. It's also worth
deciding whether a pack font should fall back the way an unknown name does
(with a warning), or keep erroring.

## 3. psart's "A sketch to start from" fails on a bare install

- **Kind:** skill docs
- **Status:** open
- **Where:** `plugin/skills/psart/SKILL.md`, the final code block
- **Found:** 2026-10-21

The starter sketch uses `/Palatino-Italic`, so running it as written on a
fresh release install stops at `findfont` (line 8) with `invalidfont`. The
partial PNG is still written, but the run exits 1. This is the first thing
an agent tries.

**Suggested fix:** use `/Times-Italic` in the sketch, or add a note that it
needs `pscat fonts install`. CI could run the skills' code blocks against a
bare bundle with no font catalog.

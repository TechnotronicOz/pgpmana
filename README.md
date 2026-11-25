# pgpmana

Stop counting colons. pgpmana is a small Mac app that shows each entry in your PostgreSQL password file as labeled fields: host, port, database, user and password. It edits `~/.pgpass`, or the file in `$PGPASSFILE` if you set one.

Website: https://technotronicoz.github.io/pgpmana/

## What it does

- Lists entries in file order and keeps comments and blank lines where they are.
- Marks entries that never get used. libpq stops at the first line that matches. An earlier line can match every connection a later line would, and then the later line never wins.
- Adds and edits entries. Each field has an "Any (*)" box, and a preview shows the exact line pgpmana will write, escapes included.
- Lets you drag entries to reorder them.
- Fixes the order for you. "Fix order" (⌥⌘F) moves each hidden entry directly above the entry that hides it, and shows every move before it applies them. It also finds exact duplicates and can remove them.
- Fills in a new entry from a connection URL such as `postgres://user:password@host:5432/database`. If the clipboard holds one when you add an entry, pgpmana puts it in the URL field for you.
- Tests a connection. With `psql` installed, pgpmana logs in using only that entry's password, so a stale password shows up. With only `pg_isready`, it checks that the server is up, but it can't check the password.
- Has a Match Tester window (⇧⌘T). Type a host, port, database and user, and it shows which entry libpq would pick.
- Warns you when group or others can read the file, because libpq ignores the file then. One click sets it to 0600.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Add entry | ⌘N |
| Edit the selected entry | ↩ |
| Test connection | ⌘K |
| Copy password | ⇧⌘C |
| Copy psql command | ⌥⌘C |
| Duplicate | ⌘D |
| Delete the selected entry | ⌫ |
| Fix order | ⌥⌘F |
| Save | ⌘S |
| Undo, redo | ⌘Z, ⇧⌘Z |
| Match Tester | ⇧⌘T |

The actions also sit in the bar at the bottom of the details panel. Hover over an icon to see its name and shortcut.

## Undo and outside changes

⌘Z undoes any change and ⇧⌘Z redoes it. A whole drag or a "Fix order" counts as one step.

pgpmana watches the file. If another program changes it and you have no unsaved changes, pgpmana reloads it and tells you. If you have unsaved changes, it keeps them and asks if you want to reload or overwrite.

## Testing connections

pgpmana looks for `psql` and `pg_isready` on your PATH and in the usual install places: Homebrew (including the keg-only `libpq` and `postgresql@N` formulas), Postgres.app and the EDB installer. Run `brew install libpq` if you have neither.

For the test, pgpmana writes a one-line password file holding only the entry under test, with mode 0600 in a private temp folder. It points `PGPASSFILE` at that file, unsets `PGPASSWORD`, runs `psql -X -w -c "select version()"` with a 5-second connect timeout, and deletes the file afterwards. Entries with `*` fields ask you for real values first.

## Saving

Changes stay in memory until you press ⌘S. Then pgpmana:

1. Copies the current file to `~/.pgpass.pgpmana.bak`, with mode 0600.
2. Writes a new temp file in the same folder, created with mode 0600.
3. Renames the temp file over `~/.pgpass`.

pgpmana writes lines you didn't touch back exactly as they were. If another program changed the file after pgpmana read it, the save stops and asks you to reload or overwrite. If you quit with unsaved changes, pgpmana asks first.

## Requirements

- macOS 14 or later
- Xcode 15 or later. `swift test` needs Xcode for XCTest. The Command Line Tools alone can build the app but can't run the tests.

## Build and run

```sh
swift test                 # parser and matcher tests
swift run pgpmana          # run from the terminal
./scripts/bundle.sh        # build build/pgpmana.app (ad-hoc signed)
cp -R build/pgpmana.app ~/Applications/
open Package.swift         # open the package in Xcode
```

## Notes

- The app isn't sandboxed, so it can read and write `~/.pgpass` directly. That also means it can't go in the Mac App Store.
- Apps you open from Finder or the Dock don't get your shell's environment. A `$PGPASSFILE` set in your shell profile won't apply there. It does apply when you start the app with `swift run pgpmana` from a terminal.

## Look and feel

The app uses the dark theme from the Nabis design system: graphite surfaces, gold as the only accent, Inter for text and Roboto Mono for labels and values. `Sources/pgpmana/Theme.swift` holds the colors, fonts, buttons, fields and cards.

The app bundles Inter and Roboto Mono in `Sources/pgpmana/Resources/Fonts`, with their license files next to them. It registers the fonts for its own process only, so nothing gets installed system-wide.

## Logo and icon

`Design/pgpmana-logo.svg` is the source for the faceted blue elephant logo, and `Design/pgpmana-logo-1024.png` is a full-size render. `scripts/bundle.sh` copies `Support/AppIcon.icns` into the .app as its icon. The About sheet shows `Sources/pgpmana/Resources/Images/AppLogo.png`. When you start the app with `swift run`, it uses that PNG as its Dock icon too.

After you edit the SVG, rebuild the icon with these commands. They need `rsvg-convert` from librsvg.

```sh
mkdir -p /tmp/AppIcon.iconset
for s in 16 32 128 256 512; do
  rsvg-convert -w $s -h $s Design/pgpmana-logo.svg -o /tmp/AppIcon.iconset/icon_${s}x${s}.png
  rsvg-convert -w $((s*2)) -h $((s*2)) Design/pgpmana-logo.svg -o /tmp/AppIcon.iconset/icon_${s}x${s}@2x.png
done
iconutil -c icns /tmp/AppIcon.iconset -o Support/AppIcon.icns
cp /tmp/AppIcon.iconset/icon_512x512.png Sources/pgpmana/Resources/Images/AppLogo.png
```

## About

Matt Carter (carter.matt@icloud.com) made pgpmana. In the app, choose pgpmana › About pgpmana to see the logo, the version and how to get in touch.

## Project layout

- `Sources/PgpassKit`: the parser, the matcher and the file writing. It uses only Foundation and has tests.
- `Sources/pgpmana`: the SwiftUI app.

## Website

The marketing site is one static page in `docs/` (`docs/index.html` plus `docs/assets/`). It has no build step. To publish it with GitHub Pages:

1. Open the repo's Settings › Pages.
2. Choose "Deploy from a branch".
3. Pick `main` and `/docs`.

The site will be at https://technotronicoz.github.io/pgpmana/.

## License

pgpmana uses the [MIT License](LICENSE). Copyright (c) 2026 Matt Carter.

The bundled fonts have their own license. Inter and Roboto Mono in `Sources/pgpmana/Resources/Fonts` use the SIL Open Font License 1.1. See `Inter-OFL.txt` and `RobotoMono-OFL.txt` in that folder.

# pgpmana

A small macOS app for managing your PostgreSQL password file (`~/.pgpass`, or the file in `$PGPASSFILE`).

What it does:

- Lists entries in file order, with comments and blank lines kept where they are.
- Flags entries that are never used because an earlier line matches every connection they would. libpq uses the first matching line.
- Adds and edits entries, with an "Any (*)" box per field and a live preview of the escaped line.
- Lets you reorder entries by dragging.
- Has a Match Tester window (⇧⌘T): type a host, port, database and user, and it shows which entry libpq would pick.
- Warns when the file mode lets group or others read it. libpq ignores the file in that case. One click sets it to 0600.

## Saving

Changes stay in memory until you press ⌘S. A save:

1. copies the current file to `~/.pgpass.pgpmana.bak` (mode 0600),
2. writes a new temp file created with mode 0600 in the same folder,
3. renames it over `~/.pgpass`.

Lines you didn't touch are written back exactly as they were. If the file changed on disk after pgpmana read it, saving stops and asks you to reload or overwrite. Quitting with unsaved changes asks first.

## Requirements

- macOS 14 or later
- Xcode 15 or later (`swift test` needs Xcode for XCTest; Command Line Tools alone can build but not test)

## Build and run

```sh
swift test                 # parser and matcher tests
swift run pgpmana          # run from the terminal
./scripts/bundle.sh        # build build/pgpmana.app (ad-hoc signed)
cp -R build/pgpmana.app ~/Applications/
open Package.swift         # open the package in Xcode
```

## Notes

- The app is not sandboxed, so it can read and write `~/.pgpass` directly. That rules out the Mac App Store.
- Apps launched from Finder or the Dock don't inherit your shell's environment, so `$PGPASSFILE` from your shell profile won't apply there. Launched with `swift run pgpmana` from a terminal, it does.

## Look

The app uses the Nabis design system's dark theme: graphite surfaces, gold as the only accent, Inter for text and Roboto Mono for labels and values. Colors, fonts, buttons, fields and cards live in `Sources/pgpmana/Theme.swift`.

Inter and Roboto Mono are bundled in `Sources/pgpmana/Resources/Fonts` under the SIL Open Font License (license files sit next to the fonts). They're registered for the app's process only, so nothing gets installed system-wide.

## Logo and icon

The faceted blue elephant logo's source is `Design/pgpmana-logo.svg`, with a 1024px render beside it. `Support/AppIcon.icns` is the app icon that `scripts/bundle.sh` puts in the .app, and `Sources/pgpmana/Resources/Images/AppLogo.png` is what the About sheet shows. When run with `swift run`, the app sets its Dock icon from that PNG.

To regenerate the icon after editing the SVG (needs `rsvg-convert` from librsvg):

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

pgpmana was created by Matt Carter (carter.matt@icloud.com). The app menu's "About pgpmana" opens a sheet with the logo, version and contact.

## Layout

- `Sources/PgpassKit`: parser, matcher and file writing. Foundation only, with tests.
- `Sources/pgpmana`: the SwiftUI app.

## Website

The marketing site lives in `docs/` as a single static page (`docs/index.html` plus `docs/assets/`), with no build step. To publish it on GitHub Pages, open the repo's Settings › Pages, choose "Deploy from a branch", and pick `main` and `/docs`. It will be served at https://technotronicoz.github.io/pgpmana/.

## License

pgpmana is released under the [MIT License](LICENSE). Copyright (c) 2026 Matt Carter.

The bundled fonts are under their own license. Inter and Roboto Mono in `Sources/pgpmana/Resources/Fonts` are distributed under the SIL Open Font License 1.1; see `Inter-OFL.txt` and `RobotoMono-OFL.txt` in that folder.

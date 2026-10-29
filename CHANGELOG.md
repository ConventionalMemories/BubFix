# Changelog

## 2.0.0

- New menu layout: Backup and restore, Bubble maps, Tests and tools, Report, Set modules, Help.
- Back up all modules or one, corrected (C) or raw (R), to a floppy or the hard disk, into a `BubFix` subject. Checks free space first, asks for another floppy when one is full, and reads every file back to check it.
- Backups carry a header and a check sum, and store the page shift found from the file headers, so a restore puts the pages back in place.
- Verify a backup against the bubble, restore it, or list the files inside it.
- Restore counts write errors, read-back errors and pages that read back different, and shows the first failed page.
- Bubble maps: show, save to a map file, restore from a map file or from the label, check a map by listing files without writing, and an experimental rebuild of a lost map.
- Typing a map from a label offers FF for the first byte, which is what the bootloop holds on real modules.
- Tests and tools: health scan, seed test, page viewer, list the files on a module, Initialize.
- Text report with all maps, the Initialize result and a log of the session.
- Nine help pages. The screen uses the full 53-character width.
- The source is split into eight Pascal modules, because one file is too big for the Pascal-86 compiler.

## 1.x

- First versions: read-only module copies, bootloop write, seed test.

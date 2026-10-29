# GRiD Bubble Fix

Version 2.0.0, by **Conventional Memories (C.M._)**. MIT license (see [LICENSE](LICENSE)); use at your own risk.

A bubble memory backup and repair tool for the GRiD Compass, written in Pascal-86 and ASM86 for GRiD-OS.

A toolkit for the bubble memory of a GRiD Compass. It can:

- back up every bubble module to files on a floppy or the hard disk, 
- check those backups and write them back,
- save and restore each module's bad-loop map (its "bootloop"),
- rescue a bubble that bootloops or that Initialize Media can't format.

<p align="center">
   <img width="322" height="241" alt="screen" src="https://github.com/user-attachments/assets/25ef07c3-fe96-47f0-8f0b-e7010233a27d" />
</p>

## Download and start

Download `bubfix~Run~` (or the floppy image) from the [Releases](../../releases) page. Copy it to a floppy or the hard disk and start it from the Executive. To build it yourself, see [BUILDING.md](BUILDING.md).

Start the GRiD from a floppy or the hard disk, **not from the bubble**. Bubble Fix talks to the 7220 bubble controller directly, so nothing else may use the bubble while it runs. Once the menu shows, the Bubble Fix floppy may come out, for example to make room for backups. Put it back before you quit.

**Keys.** Code-Return confirms and Code-Esc goes back. H or Code-? shows the help, which has nine pages of explanation. Wherever a name is asked for, you type only the name. A cursor shows, the arrows move it, and Backspace deletes the character before it. Bubble Fix adds the file type itself: `~Bootloop~` for map files, `~Bin~` and `~Raw~` for backups, `~Text~` for reports. To use a device other than the one offered, type it in front, like `` `Hard Disk`My Maps ``.

## Background

Every Intel 7110 module stores 128K in 2048 pages, on 320 storage loops. A few loops are bad from the factory. The list of good loops is the map: 40 bytes, kept in the module's bootloop and printed as 80 hex digits on its label. At every Initialize, the controller reads each module's map.

If one map is damaged, the bubble won't start and Initialize Media can't format it. Initialize Media only writes data pages, and the GRiD-OS driver's "hard format" does nothing. The data is often still there, though, and with the right map it can be read again.

GRiD-OS sees all modules as one device: module 1 is pages 0–2047, module 2 is the next 2048 pages, and so on. Files sit in 256-byte blocks of 4 pages each.

## Main menu

The top line shows the module count (with the FSA status bytes it came from).

### 1 Backup and restore

1. **Back up all modules.** Makes one file per module, named `<name> Module N~Bin~` (or `~Raw~`), with the default name `Bubble`.
   - **C** reads the way GRiD-OS does: 64 bytes a page, errors corrected, about 131K a file.
   - **R** reads raw: 68 bytes a page with the check bytes, about 139K a file. It is best for a failing module.

   You choose the hard disk, a floppy or the device Bubble Fix runs from; the bubble itself is refused. The files go into a subject called `BubFix` on that device, which is made the first time; GRiD-OS doesn't handle files at the top level of a device well. Reports go there too. The menu shows which devices answer. Before each file, Bubble Fix checks that the disk has room.
   - **On a floppy:** when it's full, you're asked for another one, which must have been through Initialize Media. A floppy holds two modules.
   - **On the hard disk:** you're never asked for another disk. It stops instead.

   If a file already exists, you can overwrite it, skip that module or stop. After writing each file, Bubble Fix reads it back and checks its check sum, so a bad floppy shows up straight away.

   A module whose map can't be read is skipped here; back it up with option 2 instead. At the end, a summary lists each module.
2. **Back up one module.** Works the same way. If the module's map can't be read, you can give the map from a map file or the label.
3. **Verify a backup against the bubble.** Compares the backup with the bubble page by page. This only reads.
4. **Restore a backup to the bubble.** Writes the backup back onto the module it came from, which **replaces everything on that module**.
   - It refuses a damaged file, and a module that won't initialize: restore that module's map first.
   - It asks for Code-Return, then for the module number to be typed.
   - Pages that were bad in the backup are left alone. Every page written is read back and compared.
   - Afterwards it runs an Initialize. Restart the GRiD then.
5. **List the files in a backup.** Finds the GRiD-OS file headers in the backup and shows each file's name, size and page.

**How page 0 is found.** Bubble Fix first tries an Initialize up to that module, so the pages come out in their real order. If that fails, it loads the module's own map, or the one you give, straight into the controller. The pages can then be shifted, because without the bootloop the controller doesn't know where page 0 is.

Bubble Fix works out the shift from the file headers it finds: each header holds its own block number. It stores the shift in the backup, and a restore uses it to put the pages back in the right place.

### 2 Bubble maps (bootloops)

1. **Show the maps.** Shows each module's map, as 5 lines of 16 hex digits like the label, with its count of good loops.
2. **Save the maps to a map file.** The default name is `Bubble Maps`. Do this first on every working GRiD, keep the file safe and photograph the labels.
3. **Restore a module's map.** Takes the map from a map file or from the label's 80 digits. It then:
   - checks that each half has at least 136 good loops,
   - compares the new map with what the module has now,
   - asks for Code-Return,
   - writes the bootloop the way Intel's BOOTUP routine does (AP-150),
   - reads it back to check it, then runs an Initialize.

   When typing a map, the arrows move the cursor, digits are typed over, and Backspace moves back without erasing. If you already typed this module's map earlier in the run, it comes back filled in.
4. **Check a map by listing files.** Loads a map into the controller without writing anything to the bubble. It then reads the module and counts the readable pages and the file headers it finds. If most pages read well and file names show up, the map is right. You can then list the files, or write the map (W).
5. **Rebuild a lost map (experimental).** For a module whose map is gone and that has no label. It tests each loop by writing patterns to pages 2040–2047 and reading them back; the loops that keep their bits are good.
   - It takes several minutes.
   - The data on those 8 pages is lost, so make a raw backup first.
   - Nothing is written to the bootloop unless you save the result and then check it and write it (S, C, W).
   - It cannot help when the seeds are lost.

### 3 Tests and tools

1. **Health scan.** Reads every page of one module or all of them, and counts good, corrected and failed pages. It lists the first failed pages. Many corrected pages mean the module is wearing out. This only reads.
2. **Seed test.** Checks whether the module can still store data. It borrows page 2047: it keeps the contents, writes FFH, reads it back, then writes the old contents back and checks them.
   - All FFH read back means the seeds are fine.
   - No FFH at all means the seeds are lost, and only Intel's seed module (BPK 72 kit) can fix that.
   - If page 2047 can't be read first, it asks before going on.
3. **Page viewer.** Shows a page in hex and as text.
   - Left and Right arrows move one page; Up and Down move one block (4 pages).
   - G goes to a page number.
   - R switches between corrected and raw.
4. **List the files on a module.** Finds the file headers on the module itself, even when GRiD-OS can't start the bubble.
5. **Initialize.** Runs the same Initialize that GRiD-OS runs at start-up.

### 4 Write a report

Writes a text file, `Bubble Report~Text~` by default, to the device you pick. It holds:

- the module count and FSA status,
- every map with its counts,
- the Initialize result,
- a log of everything done since Bubble Fix started: backups, checks, scans, seed tests and maps written.

Keep it with the backups, or share it when asking for help.

### 5 Set the number of modules

Use this only when the count found at start-up is wrong.

## Backup file format

| Part | Size | Contents |
|---|---|---|
| Header | 64 bytes | `BUBBACK1`; module (0–7); `C` or `R`; bytes a page (64 or 68); how page 0 was found (1 Initialize, 2 the module's own map, 3 a given map); page count 2048 (low byte first); 2 zero bytes; 1 if a map follows; the 40-byte map; zeros |
| Pages | 2048 × 64 or 68 | every page in turn; pages not read are zeros |
| Status | 2048 bytes | one per page: 40H or 42H good, 00H not read |
| Tail | 16 bytes | `BUBTAIL1`; pages read (2 bytes); check sum of the page bytes (Fletcher, 4 bytes); page shift found from the file headers (2 bytes, FFFFH unknown) |

Version 1 copies (pages and status bytes only) can still be verified, restored and listed. Bubble Fix then asks which module they came from.

## Safety

- **Back up first.** Only these write to the bubble, and each asks for Code-Return first: restoring a backup, restoring a map, rebuilding a map (8 test pages), and the seed test (one page, put back afterwards).
- **A wrong map can be fixed, but losing the right one may not be.** Writing a wrong map can be undone by writing the right one, as long as you still have it. If the bootloop, the label and every saved copy are all gone, only the experimental rebuild is left.
- **The label's first byte often differs.** On real modules the first map byte reads FF in the bootloop, even when the label shows something else (seen: 71, 9F, FB). The other 39 bytes match. When you type a label in, Bubble Fix offers to use FF for the first byte (recommended). Check a typed map with menu 2, 4 before writing it, and never write a label map over a module that works.
- **Don't interrupt writes.** Never switch off or reset during a write, and keep magnets away from the GRiD. A bootloop write that failed can safely be repeated with the same map.
- **Lost seeds can't be fixed in software.** A module that lost its seed bubbles takes every write without error but keeps nothing. The seed test shows this.

## Hardware notes

Things found on real machines, such as newer modules that need SWAP A (pin 13) left unconnected, labels whose first byte doesn't match the bootloop, and why a raw restore can make GRiD-OS slow, are in [docs/HARDWARE.md](docs/HARDWARE.md).

## Status

Tested on real GRiD Compass hardware (1101, 1109 and 1109): backups, restores, reading the maps and the module count. The map rebuild (menu 2, 5) is still experimental.

Please send a report file (menu 4) along with any problem, by opening an issue.

# Building

Bubble Fix is built with Intel's Pascal-86 compiler, ASM86 and the GRiD linker, running on a GRiD Compass or in MAME.

The program is split into eight Pascal modules and one assembler file, all in `src/`:

| File | Contents |
|---|---|
| `bubfix.pas` | main program and menus |
| `bfcore.pas` | shared declarations, screen helpers, 7220 controller layer |
| `bfio.pas` | typing, map files, devices, file I/O |
| `bfmaps.pas` | bubble maps menu |
| `bfback.pas` | backups |
| `bfrest.pas` | verify, restore, list files in a backup |
| `bftest.pas` | tests and tools |
| `bfhelp.pas` | help pages and the report |
| `bubasm.asm` | direct access to the 7220 controller |

As one file the program is too big for the Pascal-86 compiler ("Memory exhausted after 32768 bytes").

Compile each `.pas` file separately, assemble `bubasm.asm`, and link all the object files into `bubfix~Run~`, the main module (`bubfix`) first.


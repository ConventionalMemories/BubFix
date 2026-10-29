# Hardware notes

Things found while testing Bubble Fix on real GRiD Compass machines.

## Labels and the first map byte

A module's label shows its map as 80 hex digits. On every module checked (GRiD and non-GRiD, from a telecom board), digits 3 to 80 match the bootloop, but the first byte reads FF from the bootloop whatever the label says (for example 71, 9F or FB). When you type a label in, Bubble Fix offers FF for the first byte; use it. Check a typed map with menu 2, 4 before writing it, and never write a label map over a module that works.

## Newer modules: SWAP A must be left unconnected

Intel's 7110 datasheet says pins 13 and 14 (SWAP A and SWAP B) are joined outside the module, and older boards such as the 1109 do this. On some newer modules (found in a 1139 and on a telecom board) pin 13 is not connected. Put such a module in an older board and it reads perfectly, but no write takes: every page reads back with its old data.

Fix: isolate pin 13 for that module only, by taping over that socket contact or bending the pin away. Don't cut the link on the board, because the original modules may need it.

## 7110 pins

From Intel's 7110 data sheet (1983 Memory Component Handbook, page 6-177):

| Pin | Signal | Used for |
|---|---|---|
| 1 | PULSE.COM | +12 V, common for the pulse lines |
| 2, 3 | REP.B, REP.A | reading pages |
| 4 | BOOT.REP | reading the bootloop |
| 5 | BOOT.SWAP | writing the bootloop |
| 7, 8 | GEN.A, GEN.B | writing (make new bubbles) |
| 9, 10 | X-, X+ coil | |
| 11, 12 | Y-, Y+ coil | |
| 13, 14 | SWAP.A, SWAP.B | writing (move data into the loops) |
| 15 | DET.COM | detector ground |
| 16-19 | DET.OUT A+/A-/B+/B- | detector outputs |
| 20 | DET.SUPPLY | +12 V |

Resistance from pin 1, module out of its socket: GEN 9-59 Ω, REP 9-26 Ω, SWAP 44-149 Ω, BOOT.REP 3.5-24 Ω. A map that reads correctly proves pins 4, 9-12 and 15-20; it says nothing about 2, 3, 7, 8, 13 and 14.

## Raw restore and a slow GRiD-OS

A raw (R) backup keeps each page exactly as read, with its old check bytes. If the module already had bit errors, a raw restore copies them onto the new module, and GRiD-OS then corrects them on almost every read, which is slow. Afterwards, back the module up with C and restore that: the controller then writes fresh check bytes. A health scan (menu 3, 1) shows how many pages need correcting.

## Booting with a dead module (1139)

If a bubble module fails to initialize, the GRiD-OS bubble driver waits forever and the machine hangs at boot, with the bubble indicator blinking. Start Bubble Fix from a copy of a boot floppy with it renamed to ``Programs`Executive~Run~``.

$COMPACT SS(32)
MODULE bubfix;

{ GRiD Bubble Fix, by Conventional Memories (C.M._).

  Backs up the bubble memory of a GRiD Compass and looks after the
  bad-loop maps of its modules.

  Every Intel 7110 bubble module has 320 storage loops, and a few of
  them are bad from the factory. Which ones is written in the module
  itself, in a special "bootloop", and printed as hex on its label.
  The 7220 controller reads that map at every Initialize and only uses
  the good loops. When the bootloop is damaged, Initialize fails and
  Initialize Media cannot format the bubble at all.

  Main menu:
    1 Backup and restore: copy modules into files (all at once or one
      at a time), check a backup against the bubble, write a backup
      back, list the files in a backup.
    2 Bubble maps: show, save and restore bootloop maps, check a map
      by listing the files it makes readable, rebuild a lost map.
    3 Tests and tools: health scan, seed test (puts the data back),
      page viewer, list the files on a module, Initialize.
    4 Write a report file.
    5 Set the number of modules by hand.
    H Help.

  Only these write to the bubble, and only after Code-Return:
  restoring a backup, restoring a map, rebuilding a map (test pages)
  and the seed test (one page, put back afterwards).
  It talks to the 7220 directly (bubasm.asm), so run it from a floppy
  or hard disk start-up with nothing else using the bubble.

  Code-Return confirms, Code-Esc goes back or quits.

  The program is too big for the Pascal-86 compiler in one piece, so it
  is split into modules: this main program and bfcore, bfio, bfmaps,
  bfback, bfrest, bftest and bfhelp (.pas), plus bubasm.asm. All of
  them go in the project folder; the build compiles and links every
  .pas and .asm file there. }

$NOLIST
$INCLUDE (``INCS`Common.Inc~text~)
$INCLUDE (``INCS`OsPasTypes.Inc~text~)
$INCLUDE (``INCS`OsPasProcs.Inc~text~)
$INCLUDE (``INCS`ConPas.Inc~text~)
$INCLUDE (``INCS`Keys.Inc~text~)
$INCLUDE (``INCS`WindowTypes.Inc~text~)
$INCLUDE (``INCS`WindowProcs.Inc~text~)
$LIST

{ the assembly part (bubasm.asm) }
PUBLIC BubAsm;
	PROCEDURE BubPut (reg, val: INTEGER);
	FUNCTION BubGet (reg: INTEGER): INTEGER;
	PROCEDURE BubCmd (cmd: INTEGER);
	FUNCTION BubStat: INTEGER;
	PROCEDURE BubSelFifo;
	PROCEDURE BubFifoW (val: INTEGER);
	FUNCTION BubFifoR: INTEGER;
	PROCEDURE BubParams (blr, er, ar: INTEGER);
	FUNCTION BubWrFill (cmd, val, n: INTEGER): INTEGER;
	FUNCTION BubRdData (cmd, n: INTEGER): INTEGER;
	FUNCTION BubRdByte (i: INTEGER): INTEGER;
	FUNCTION BubWrData (cmd, n: INTEGER): INTEGER;
	PROCEDURE BubSetW (i, val: INTEGER);
	FUNCTION BubGetW (i: INTEGER): INTEGER;
	FUNCTION BubDiff (n: INTEGER): INTEGER;
	PROCEDURE BubCkReset;
	PROCEDURE BubCkAdd (val: INTEGER);
	PROCEDURE BubCkPage (n: INTEGER);
	FUNCTION BubCkGet (k: INTEGER): INTEGER;
	PROCEDURE TxReset;
	PROCEDURE TxPut (VAR s: BYTES; n: INTEGER);
	PROCEDURE TxChar (c: INTEGER);
	FUNCTION TxLen: INTEGER;
	FUNCTION TxByte (i: INTEGER): INTEGER;
	PROCEDURE TxCut (n: INTEGER);

PUBLIC bfcore;

CONST
	maxMbm    = 8;      { the 7220 handles up to 8 modules }
	mapBytes  = 40;     { a map is 320 bits: loop bits of halves A and B, alternating }
	needLoops = 136;    { good loops each half needs (272 per module) }
	pageBytes = 68;     { one page of both halves, no error correction }
	eccBytes  = 64;     { one page with error correction, as GRiD-OS uses it }
	modPages  = 2048;   { pages in one module }
	enGrid    = 28H;    { the enable register GRiD-OS reads and writes with }
	testBase  = 2040;   { the pages the map rebuild writes its tests to }
	testPages = 8;
	seedPage  = 2047;   { the page the seed test borrows }

	{ 7220 commands }
	cmdWrBLRMasked = 0; { Write Bootloop Register Masked }
	cmdInit      = 1;
	cmdRead      = 2;
	cmdWrite     = 3;
	cmdWrBLR     = 6;   { Write Bootloop Register }
	cmdWrBL      = 7;   { Write Bootloop }
	cmdRdFsa     = 8;   { Read FSA Status }
	cmdAbort     = 9;
	cmdRdBL      = 11;  { Read Bootloop }
	cmdResetFifo = 13;
	cmdPurge     = 14;  { MBM Purge }
	cmdSwReset   = 15;  { Software Reset }

	{ block length register: NFC = 1 (both halves of one module), 1 page }
	blrOne = 1001H;
	{ enable register: 10H allows Write Bootloop; no interrupts, no DMA }
	enWrBL = 10H;

	{ map files }
	fileMagic = 'BUBMAPS1';
	fileBytes = 337;    { 8 magic + 1 count + 8 x (1 flag + 40 map) }
	defaultMapName = 'Bubble Maps';
	{ backup files: a 64-byte header, the pages, a status byte per page,
	  a 16-byte tail }
	bakMagic  = 'BUBBACK1';
	tailMagic = 'BUBTAIL1';
	defaultBase = 'Bubble';
	defaultReport = 'Bubble Report';
	rebuiltName = 'Rebuilt Map';
	modWord = ' Module ';
	bakSubject = 'BubFix';  { the subject backups and reports go in }

	{ file types, added to every name: only the name is asked for }
	extMap = '~Bootloop~';
	extBin = '~Bin~';
	extRaw = '~Raw~';
	extText = '~Text~';

	{ devices }
	devHard   = 'Hard Disk';
	devFloppy = 'Floppy Disk';
	devPort   = 'Portable Floppy';
	devBubble = 'Bubble Memory';
	probeName = 'Bubble Fix Probe~Tmp~';

TYPE
	MapType = ARRAY [0..39] OF INTEGER;
	LineType = ARRAY [0..120] OF CHAR;
	{ what OsGetStatus gives for a file: the volume's pages too }
	VolStatus = RECORD
		open: BOOLEAN;
		access, seek: BYTE;
		filePos, fileLen: LONGINT;
		numPages, numAlloc, bytesPerPage: WORD;
		END;

VAR
	nMbm: INTEGER;
	maps: ARRAY [0..7] OF MapType;
	mapOk: ARRAY [0..7] OF BOOLEAN;
	newMap, curMap, prepMap: MapType;
	prepMapOk: BOOLEAN;
	typedFor: INTEGER;        { module the last typed map was for }
	row, lastStat: INTEGER;
	scrRows, scrCols: INTEGER;
	nameBuf: LineType;
	nameLen: INTEGER;
	mapName: LineType;        { last map file name }
	mapLen: INTEGER;
	baseName: LineType;       { last backup name }
	baseLen: INTEGER;
	pathBuf: LineType;
	fbuf: ARRAY [0..399] OF CHAR;
	quit: BOOLEAN;
	fsaRaw: ARRAY [0..15] OF INTEGER;
	fsaN: INTEGER;            { bytes in fsaRaw }
	byHand: BOOLEAN;          { module count typed in }
	initN: INTEGER;           { modules the last EnsureInit got going }
	lastMs: INTEGER;          { how long the last WaitDone waited }
	wbFed, wbLeft, wbMs: INTEGER;  { last Write Bootloop: bytes given, left over, time }
	pstat: ARRAY [0..2047] OF CHAR;    { status of every page of a backup }
	orig: ARRAY [0..127] OF INTEGER;   { a page kept aside }
	{ devices }
	ownDev: LineType;         { the device Bubble Fix runs from }
	ownLen: INTEGER;
	destDev: LineType;        { where backups and reports go }
	destLen: INTEGER;
	destRemovable: BOOLEAN;
	{ the file being written }
	fwConn, fwErr: WORD;
	fwN: INTEGER;
	fwBuf: ARRAY [0..1023] OF CHAR;
	{ the file being read }
	frConn, frErr: WORD;
	frN, frPos: INTEGER;
	frEnd: BOOLEAN;
	frBuf: ARRAY [0..1023] OF CHAR;
	{ the backup file being read }
	bkModule, bkPsize, bkSynced, bkOff: INTEGER;
	bkLegacy, bkMapOk, bkTailOk: BOOLEAN;
	bkMap: MapType;
	bkBad, bkUnread: INTEGER;
	bkCk: ARRAY [0..3] OF INTEGER;
	{ page offset votes: where file headers say a page really is }
	voteOff, voteN: ARRAY [0..7] OF INTEGER;
	{ files found by a listing }
	dirN, dirHeaders: INTEGER;
	dirName: ARRAY [0..99, 0..29] OF CHAR;
	dirNameLen, dirK, dirPage: ARRAY [0..99] OF INTEGER;
	{ map rebuild }
	quality: ARRAY [0..319] OF INTEGER;
	delta, sorted: ARRAY [0..159] OF INTEGER;
	{ one page as numbers, from the bubble or from a backup file }
	pgBuf: ARRAY [0..127] OF INTEGER;
	newFor: INTEGER;          { module newMap was given for, or -1 }
	prepLevel: INTEGER;       { what the last Prepare managed }
	swapped: BOOLEAN;         { a floppy was changed during a backup }
	{ result of each module's backup: bad pages, or -1 skipped, -2 not
	  done, -3 read-back check failed, -4 stopped part way }
	bkRes: ARRAY [0..7] OF INTEGER;
	bkExt: INTEGER;           { 2 corrected copy (~Bin~), 3 raw (~Raw~) }
	ext: Point;

	FUNCTION Bit (v, n: INTEGER): BOOLEAN;
	PROCEDURE Cls;
	PROCEDURE NewLine (n: INTEGER);
	PROCEDURE PutNum (n: INTEGER);
	FUNCTION HexChar (d: INTEGER): CHAR;
	PROCEDURE PutHex2 (b: INTEGER);
	FUNCTION GetKey: INTEGER;
	FUNCTION IsCancel (key: INTEGER): BOOLEAN;
	FUNCTION StopAsked: BOOLEAN;
	PROCEDURE AnyKey;
	FUNCTION Confirmed: BOOLEAN;
	FUNCTION DigitOf (key: INTEGER): INTEGER;
	FUNCTION UpKey (key: INTEGER): INTEGER;
	PROCEDURE TxEnd;
	PROCEDURE TxNum (n: INTEGER);
	PROCEDURE TxHex2 (b: INTEGER);
	PROCEDURE TxPath;
	PROCEDURE PutPath;
	PROCEDURE TxModule (m: INTEGER);
	PROCEDURE SetMapBit (VAR map: MapType; idx: INTEGER; on: BOOLEAN);
	FUNCTION SameMap (VAR a, b: MapType): BOOLEAN;
	PROCEDURE ShowMap (VAR map: MapType);
	PROCEDURE TxMap (VAR map: MapType);
	PROCEDURE ShowCounts (VAR map: MapType);
	PROCEDURE TxCounts (VAR map: MapType);
	FUNCTION MapUsable (VAR map: MapType): BOOLEAN;
	FUNCTION RunCmd (cmd, ms: INTEGER): BOOLEAN;
	PROCEDURE ShowStat;
	PROCEDURE TxStat;
	FUNCTION ResetBmc: BOOLEAN;
	FUNCTION ReadBootloop (m: INTEGER; VAR map: MapType): BOOLEAN;
	FUNCTION InitUpTo (last, er: INTEGER): BOOLEAN;
	FUNCTION InitAll: BOOLEAN;
	FUNCTION EnsureInit: INTEGER;
	FUNCTION CountMbm: INTEGER;
	FUNCTION WriteBootloop (m: INTEGER; VAR map: MapType): INTEGER;
	FUNCTION LoadMapFsa (m, er: INTEGER; VAR map: MapType): BOOLEAN;
	FUNCTION ReadPage (m, p, er, n: INTEGER): INTEGER;
	FUNCTION WritePage (m, p, er, n: INTEGER): BOOLEAN;
	FUNCTION PageGood (got, n, s: INTEGER): BOOLEAN;

PUBLIC bfio;
	FUNCTION AskName (kind: INTEGER): BOOLEAN;
	PROCEDURE MakePath (dev: BOOLEAN; m, ext: INTEGER);
	PROCEDURE SetBaseName;
	PROCEDURE KeepBaseName;
	PROCEDURE ShowFileError (e: WORD);
	FUNCTION TypeMap (m: INTEGER): BOOLEAN;
	FUNCTION SaveFile: BOOLEAN;
	FUNCTION LoadFile (m: INTEGER): BOOLEAN;
	PROCEDURE SetDest (d: INTEGER);
	FUNCTION OwnIsBubble: BOOLEAN;
	PROCEDURE FindOwnDevice;
	PROCEDURE PutDest;
	FUNCTION ChooseDest (reading: BOOLEAN): BOOLEAN;
	PROCEDURE FwByte (b: INTEGER);
	FUNCTION FwClose: BOOLEAN;
	PROCEDURE DeleteFile;
	FUNCTION FwCreate (needK: INTEGER; VAR freeK: INTEGER): INTEGER;
	PROCEDURE FrOpen;
	FUNCTION FrByte: INTEGER;
	PROCEDURE FrClose;

PUBLIC bfmaps;
	PROCEDURE Title;
	FUNCTION ChooseModule (all: BOOLEAN): INTEGER;
	FUNCTION Prepare (m, er: INTEGER; ask: BOOLEAN): INTEGER;
	PROCEDURE ShowLevel (lvl: INTEGER);
	PROCEDURE TxLevel (lvl: INTEGER);
	FUNCTION HeaderAt (m: INTEGER): INTEGER;
	PROCEDURE VoteReset;
	PROCEDURE Vote (m, t, p: INTEGER);
	FUNCTION BestOff: INTEGER;
	PROCEDURE DirAdd (t, p: INTEGER);
	PROCEDURE ShowDir (m, off: INTEGER);
	FUNCTION ScanModule (m: INTEGER; VAR nRead: INTEGER): INTEGER;
	PROCEDURE ScanResult (m, good, nRead: INTEGER);
	PROCEDURE ShowMaps;
	PROCEDURE SaveMaps;
	PROCEDURE RestoreMap;
	PROCEDURE TryMap (m: INTEGER);
	PROCEDURE CheckMap;

PUBLIC bfback;
	FUNCTION StatGood (s: INTEGER): BOOLEAN;
	FUNCTION OpenBackup: BOOLEAN;
	FUNCTION FrPage: BOOLEAN;
	FUNCTION AskBackup: BOOLEAN;
	PROCEDURE DoBackup (all: BOOLEAN);

PUBLIC bfrest;
	PROCEDURE Verify;
	PROCEDURE RestoreBackup;
	PROCEDURE ListBackup;

PUBLIC bftest;
	PROCEDURE RebuildMap;
	PROCEDURE HealthScan;
	PROCEDURE SeedTest;
	PROCEDURE PageViewer;
	PROCEDURE ListModule;
	PROCEDURE TestInit;

PUBLIC bfhelp;
	PROCEDURE Report;
	PROCEDURE Help (first: INTEGER);
	FUNCTION IsHelp (key: INTEGER): BOOLEAN;

PROGRAM bubfix;

VAR
	k: INTEGER;              { loop counter of the main program }

{ ---------- menus ---------- }

PROCEDURE BackupMenu;
VAR key: INTEGER;
	back: BOOLEAN;
BEGIN
back := FALSE;
REPEAT
	Title;
	ConLineOut ('Backup and restore', 18);
	NewLine (1);
	NewLine (1);
	ConLineOut ('1  Back up all modules', 22);
	NewLine (1);
	ConLineOut ('2  Back up one module', 21);
	NewLine (1);
	ConLineOut ('3  Verify a backup against the bubble', 37);
	NewLine (1);
	ConLineOut ('4  Restore a backup to the bubble (!)', 37);
	NewLine (1);
	ConLineOut ('5  List the files in a backup', 29);
	NewLine (1);
	NewLine (1);
	ConLineOut ('Backing up and verifying only read the bubble.', 46);
	NewLine (1);
	ConLineOut ('Restore WRITES to it and replaces what is on the', 48);
	NewLine (1);
	ConLineOut ('module. Save backups on a floppy or the hard disk,', 50);
	NewLine (1);
	ConLineOut ('never on the bubble.', 20);
	NewLine (1);
	NewLine (1);
	ConLineOut ('H help, Code-Esc back', 21);
	key := GetKey;
	IF IsCancel (key) THEN
		back := TRUE
	ELSE IF IsHelp (key) THEN
		Help (3)
	ELSE IF key = ORD ('1') THEN
		DoBackup (TRUE)
	ELSE IF key = ORD ('2') THEN
		DoBackup (FALSE)
	ELSE IF key = ORD ('3') THEN
		Verify
	ELSE IF key = ORD ('4') THEN
		RestoreBackup
	ELSE IF key = ORD ('5') THEN
		ListBackup;
UNTIL back;
END;

PROCEDURE MapsMenu;
VAR key: INTEGER;
	back: BOOLEAN;
BEGIN
back := FALSE;
REPEAT
	Title;
	ConLineOut ('Bubble maps (bootloops)', 23);
	NewLine (1);
	NewLine (1);
	ConLineOut ('1  Show the maps', 16);
	NewLine (1);
	ConLineOut ('2  Save the maps to a map file', 30);
	NewLine (1);
	ConLineOut ('3  Restore a module''s map (writes)', 34);
	NewLine (1);
	ConLineOut ('4  Check a map by listing files', 31);
	NewLine (1);
	ConLineOut ('5  Rebuild a lost map (experimental)', 36);
	NewLine (1);
	NewLine (1);
	ConLineOut ('A map lists a module''s good loops. If it is damaged', 51);
	NewLine (1);
	ConLineOut ('the bubble will not start. Save the maps of working', 51);
	NewLine (1);
	ConLineOut ('modules first (2), and compare them with the labels', 51);
	NewLine (1);
	ConLineOut ('(1).', 4);
	NewLine (1);
	NewLine (1);
	ConLineOut ('H help, Code-Esc back', 21);
	key := GetKey;
	IF IsCancel (key) THEN
		back := TRUE
	ELSE IF IsHelp (key) THEN
		Help (6)
	ELSE IF key = ORD ('1') THEN
		ShowMaps
	ELSE IF key = ORD ('2') THEN
		SaveMaps
	ELSE IF key = ORD ('3') THEN
		RestoreMap
	ELSE IF key = ORD ('4') THEN
		CheckMap
	ELSE IF key = ORD ('5') THEN
		RebuildMap;
UNTIL back;
END;

PROCEDURE TestsMenu;
VAR key: INTEGER;
	back: BOOLEAN;
BEGIN
back := FALSE;
REPEAT
	Title;
	ConLineOut ('Tests and tools', 15);
	NewLine (1);
	NewLine (1);
	ConLineOut ('1  Health scan (reads every page)', 33);
	NewLine (1);
	ConLineOut ('2  Seed test (borrows one page)', 31);
	NewLine (1);
	ConLineOut ('3  Page viewer', 14);
	NewLine (1);
	ConLineOut ('4  List the files on a module', 29);
	NewLine (1);
	ConLineOut ('5  Initialize, as at start-up', 29);
	NewLine (1);
	NewLine (1);
	ConLineOut ('All of these only read, except the seed test: it', 48);
	NewLine (1);
	ConLineOut ('writes one page and puts it back afterwards.', 44);
	NewLine (1);
	NewLine (1);
	ConLineOut ('H help, Code-Esc back', 21);
	key := GetKey;
	IF IsCancel (key) THEN
		back := TRUE
	ELSE IF IsHelp (key) THEN
		Help (8)
	ELSE IF key = ORD ('1') THEN
		HealthScan
	ELSE IF key = ORD ('2') THEN
		SeedTest
	ELSE IF key = ORD ('3') THEN
		PageViewer
	ELSE IF key = ORD ('4') THEN
		ListModule
	ELSE IF key = ORD ('5') THEN
		TestInit;
UNTIL back;
END;

{ 5: when the count is wrong, it can be set by hand. }
PROCEDURE SetCount;
VAR key, n: INTEGER;
BEGIN
Title;
NewLine (1);
ConLineOut ('How many bubble modules? (1-8) Only when the count', 50);
NewLine (1);
ConLineOut ('found is wrong.', 15);
NewLine (1);
REPEAT
	key := GetKey;
	n := DigitOf (key);
UNTIL IsCancel (key) OR ((n >= 1) AND (n <= maxMbm));
IF NOT IsCancel (key) THEN
	BEGIN
	nMbm := n;
	byHand := TRUE;
	TxPut ('Number of modules set by hand:', 30);
	TxNum (n);
	TxEnd;
	END;
END;

PROCEDURE Menu;
VAR key, i: INTEGER;
BEGIN
Title;
ConMoveCsr (scrCols - 5, 0);
ConLineOut ('C.M._', 5);
ConMoveCsr (0, row);
IF byHand THEN
	BEGIN
	ConLineOut ('Bubble modules (set by hand):', 29);
	END
ELSE
	BEGIN
	ConLineOut ('Bubble modules found:', 21);
	END;
PutNum (nMbm);
NewLine (1);
ConLineOut ('FSA status:', 11);
NewLine (1);
FOR i := 0 TO fsaN - 1 DO
	BEGIN
	IF (i MOD 2) = 0 THEN
		ConCharOut (' ');
	PutHex2 (fsaRaw[i]);
	END;
NewLine (1);
IF OwnIsBubble THEN
	BEGIN
	ConLineOut ('WARNING: started from the bubble. Start from a floppy', 53);
	NewLine (1);
	ConLineOut ('or the hard disk instead.', 25);
	NewLine (1);
	END;
NewLine (1);
IF nMbm > 0 THEN
	BEGIN
	ConLineOut ('1  Backup and restore: bubble to files and back', 47);
	NewLine (1);
	ConLineOut ('2  Bubble maps (bootloops): show, save, restore', 47);
	NewLine (1);
	ConLineOut ('3  Tests and tools: health scan, seed test, viewer', 50);
	NewLine (1);
	ConLineOut ('4  Write a report file', 22);
	NewLine (1);
	END
ELSE
	BEGIN
	ConLineOut ('No bubble memory was found.', 27);
	NewLine (1);
	NewLine (1);
	END;
ConLineOut ('5  Set the number of modules', 28);
NewLine (1);
ConLineOut ('H  Help: please read it first', 29);
NewLine (1);
NewLine (1);
ConLineOut ('Back up first. Anything that writes to the bubble', 49);
NewLine (1);
ConLineOut ('asks for Code-Return. Code-Esc quits.', 37);
key := GetKey;
IF IsCancel (key) THEN
	quit := TRUE
ELSE IF IsHelp (key) THEN
	Help (1)
ELSE IF key = ORD ('5') THEN
	SetCount
ELSE IF nMbm > 0 THEN
	BEGIN
	IF key = ORD ('1') THEN
		BackupMenu
	ELSE IF key = ORD ('2') THEN
		MapsMenu
	ELSE IF key = ORD ('3') THEN
		TestsMenu
	ELSE IF key = ORD ('4') THEN
		Report;
	END;
END;

BEGIN
WinInitDefaultWindow;
ConDefCsr (FALSE);
WinGetWindowExtent (ext);
scrRows := ext.y DIV LineHeight;
scrCols := ext.x DIV CharWidth;
IF (scrCols < 20) OR (scrCols > 132) THEN
	scrCols := 40;
IF (scrRows < 10) OR (scrRows > 60) THEN
	scrRows := 24;
Title;
NewLine (1);
ConLineOut ('Looking for bubble memory...', 28);
TxReset;
FindOwnDevice;
fsaN := 0;
byHand := FALSE;
typedFor := -1;
newFor := -1;
prepLevel := 0;
prepMapOk := FALSE;
nameLen := 0;
bkExt := 2;
FOR k := 0 TO maxMbm - 1 DO
	mapOk[k] := FALSE;
mapLen := 11;
FOR k := 0 TO mapLen - 1 DO
	mapName[k] := defaultMapName[k + 1];
baseLen := 6;
FOR k := 0 TO baseLen - 1 DO
	baseName[k] := defaultBase[k + 1];
SetDest (4);
nMbm := CountMbm;
initN := EnsureInit;
TxPut ('Bubble Fix 2.0.0 started. Modules found:', 40);
TxNum (nMbm);
TxPut (', FSA status', 12);
FOR k := 0 TO fsaN - 1 DO
	BEGIN
	TxChar (32);
	TxHex2 (fsaRaw[k]);
	END;
TxEnd;
TxPut ('Initialize at start:', 20);
TxNum (initN);
TxPut (' of', 3);
TxNum (nMbm);
TxPut (' modules', 8);
TxEnd;
quit := FALSE;
WHILE NOT quit DO
	Menu;
WinEraseWindow;
ConDefCsr (TRUE);
END.


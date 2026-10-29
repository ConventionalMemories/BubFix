$COMPACT SS(32)
MODULE bfcore;

{ GRiD Bubble Fix 2, by Conventional Memories (C.M._).
  Part of bubfix (see bubfix.pas): small helpers, maps, the 7220 controller. }

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

PRIVATE bfcore;

{ ---------- small helpers ---------- }

{ Bit n (0..7) of v. }
FUNCTION Bit (v, n: INTEGER): BOOLEAN;
VAR i: INTEGER;
BEGIN
FOR i := 1 TO n DO
	v := v DIV 2;
Bit := (v MOD 2) = 1;
END;

PROCEDURE Cls;
BEGIN
WinEraseWindow;
row := 0;
ConMoveCsr (0, 0);
END;

{ Go to the start of the next line (or skip n lines). }
PROCEDURE NewLine (n: INTEGER);
BEGIN
row := row + n;
ConMoveCsr (0, row);
END;

PROCEDURE PutNum (n: INTEGER);
VAR digits: ARRAY [0..5] OF CHAR;
	i: INTEGER;
BEGIN
IF n < 0 THEN
	BEGIN
	ConCharOut ('-');
	n := -n;
	END;
i := 0;
REPEAT
	digits[i] := CHR (ORD ('0') + n MOD 10);
	n := n DIV 10;
	i := i + 1;
UNTIL n = 0;
WHILE i > 0 DO
	BEGIN
	i := i - 1;
	ConCharOut (digits[i]);
	END;
END;

FUNCTION HexChar (d: INTEGER): CHAR;
BEGIN
IF d < 10 THEN
	HexChar := CHR (ORD ('0') + d)
ELSE
	HexChar := CHR (ORD ('A') + d - 10);
END;

PROCEDURE PutHex2 (b: INTEGER);
BEGIN
ConCharOut (HexChar (b DIV 16));
ConCharOut (HexChar (b MOD 16));
END;

{ Waits for a key and gives its code. }
FUNCTION GetKey: INTEGER;
BEGIN
WHILE NOT ConKeyPressed DO
	OsDelay (10);
GetKey := ORD (ConCharIn);
END;

FUNCTION IsCancel (key: INTEGER): BOOLEAN;
BEGIN
IsCancel := (key = cancelKey) OR (key = escapeKey);
END;

{ Code-Esc pressed since the last look? (for long jobs) }
FUNCTION StopAsked: BOOLEAN;
VAR stop: BOOLEAN;
BEGIN
stop := FALSE;
WHILE ConKeyPressed DO
	IF IsCancel (ORD (ConCharIn)) THEN
		stop := TRUE;
StopAsked := stop;
END;

{ Shows "Press any key." and waits. }
PROCEDURE AnyKey;
VAR key: INTEGER;
BEGIN
NewLine (2);
ConLineOut ('Press any key.', 14);
key := GetKey;
END;

{ Asks for Code-Return; TRUE when given, FALSE for Code-Esc. }
FUNCTION Confirmed: BOOLEAN;
VAR key: INTEGER;
BEGIN
REPEAT
	key := GetKey;
UNTIL (key = confirmKey) OR IsCancel (key);
Confirmed := key = confirmKey;
END;

{ The digit key typed, as a number, or -1. }
FUNCTION DigitOf (key: INTEGER): INTEGER;
BEGIN
IF (key >= ORD ('0')) AND (key <= ORD ('9')) THEN
	DigitOf := key - ORD ('0')
ELSE
	DigitOf := -1;
END;

FUNCTION UpKey (key: INTEGER): INTEGER;
BEGIN
IF (key >= ORD ('a')) AND (key <= ORD ('z')) THEN
	UpKey := key - 32
ELSE
	UpKey := key;
END;

{ ---------- the text buffer: session log and report ---------- }

PROCEDURE TxEnd;
BEGIN
TxChar (13);
TxChar (10);
END;

PROCEDURE TxNum (n: INTEGER);
VAR digits: ARRAY [0..5] OF INTEGER;
	i: INTEGER;
BEGIN
IF n < 0 THEN
	BEGIN
	TxChar (ORD ('-'));
	n := -n;
	END;
i := 0;
REPEAT
	digits[i] := ORD ('0') + n MOD 10;
	n := n DIV 10;
	i := i + 1;
UNTIL n = 0;
WHILE i > 0 DO
	BEGIN
	i := i - 1;
	TxChar (digits[i]);
	END;
END;

PROCEDURE TxHex2 (b: INTEGER);
BEGIN
TxChar (ORD (HexChar (b DIV 16)));
TxChar (ORD (HexChar (b MOD 16)));
END;

{ The text of nameBuf / pathBuf into the text buffer. }
PROCEDURE TxName;
VAR i: INTEGER;
BEGIN
FOR i := 0 TO nameLen - 1 DO
	TxChar (ORD (nameBuf[i]));
END;

PROCEDURE TxPath;
VAR i: INTEGER;
BEGIN
FOR i := 1 TO ORD (pathBuf[0]) DO
	TxChar (ORD (pathBuf[i]));
END;

PROCEDURE PutPath;
VAR i: INTEGER;
BEGIN
FOR i := 1 TO ORD (pathBuf[0]) DO
	ConCharOut (pathBuf[i]);
END;

{ "Module 2: " at the start of a log line }
PROCEDURE TxModule (m: INTEGER);
BEGIN
TxPut ('Module', 6);
TxNum (m + 1);
TxChar (ORD (':'));
TxChar (32);
END;

{ ---------- maps ---------- }

{ Good loops in one half of a map: half A is bits 7, 5, 3, 1 of each
  byte, half B bits 6, 4, 2, 0 (the controller takes the bits highest
  first, A and B in turn). }
FUNCTION GoodLoops (VAR map: MapType; half: INTEGER): INTEGER;
VAR i, j, n: INTEGER;
BEGIN
n := 0;
FOR i := 0 TO mapBytes - 1 DO
	FOR j := 0 TO 3 DO
		IF Bit (map[i], 7 - half - 2 * j) THEN
			n := n + 1;
GoodLoops := n;
END;

{ Loop idx of a map (0..319, in the order the controller takes them:
  even idx is half A, odd idx half B). }
FUNCTION MapBit (VAR map: MapType; idx: INTEGER): BOOLEAN;
BEGIN
MapBit := Bit (map[idx DIV 8], 7 - idx MOD 8);
END;

PROCEDURE SetMapBit (VAR map: MapType; idx: INTEGER; on: BOOLEAN);
VAR v, i: INTEGER;
BEGIN
v := 1;
FOR i := 1 TO 7 - idx MOD 8 DO
	v := v * 2;
IF on AND NOT MapBit (map, idx) THEN
	map[idx DIV 8] := map[idx DIV 8] + v
ELSE IF NOT on AND MapBit (map, idx) THEN
	map[idx DIV 8] := map[idx DIV 8] - v;
END;

FUNCTION SameMap (VAR a, b: MapType): BOOLEAN;
VAR i: INTEGER;
	same: BOOLEAN;
BEGIN
same := TRUE;
FOR i := 0 TO mapBytes - 1 DO
	IF a[i] <> b[i] THEN
		same := FALSE;
SameMap := same;
END;

{ Shows a map as 5 lines of 16 hex digits, the way the module's
  label prints it, starting on the next line. }
PROCEDURE ShowMap (VAR map: MapType);
VAR i: INTEGER;
BEGIN
FOR i := 0 TO mapBytes - 1 DO
	BEGIN
	IF (i MOD 8) = 0 THEN
		BEGIN
		NewLine (1);
		;
		END;
	PutHex2 (map[i]);
	END;
END;

{ The same into the text buffer, 5 lines. }
PROCEDURE TxMap (VAR map: MapType);
VAR i: INTEGER;
BEGIN
FOR i := 0 TO mapBytes - 1 DO
	BEGIN
	IF (i MOD 8) = 0 THEN
		;
	TxHex2 (map[i]);
	IF (i MOD 8) = 7 THEN
		TxEnd;
	END;
END;

{ "good loops 138 + 138" }
PROCEDURE ShowCounts (VAR map: MapType);
BEGIN
ConLineOut ('good loops', 10);
PutNum (GoodLoops (map, 0));
ConLineOut (' +', 2);
PutNum (GoodLoops (map, 1));
END;

PROCEDURE TxCounts (VAR map: MapType);
BEGIN
TxPut ('good loops', 10);
TxNum (GoodLoops (map, 0));
TxPut (' +', 2);
TxNum (GoodLoops (map, 1));
END;

FUNCTION MapUsable (VAR map: MapType): BOOLEAN;
BEGIN
MapUsable := (GoodLoops (map, 0) >= needLoops) AND
             (GoodLoops (map, 1) >= needLoops);
END;

{ ---------- the 7220 ---------- }

{ Waits until the controller is not busy (at most ms milliseconds)
  and gives its status. }
FUNCTION WaitDone (ms: INTEGER): INTEGER;
VAR s, t: INTEGER;
BEGIN
t := 0;
s := BubStat;
WHILE Bit (s, 7) AND (t < ms) DO
	BEGIN
	OsDelay (10);
	t := t + 10;
	s := BubStat;
	END;
lastStat := s;
lastMs := t;
WaitDone := s;
END;

{ Done, not failed, not busy. }
FUNCTION StatOk (s: INTEGER): BOOLEAN;
BEGIN
StatOk := Bit (s, 6) AND NOT Bit (s, 5) AND NOT Bit (s, 7);
END;

FUNCTION RunCmd (cmd, ms: INTEGER): BOOLEAN;
BEGIN
BubCmd (cmd);
RunCmd := StatOk (WaitDone (ms));
END;

{ "(status 40)" }
PROCEDURE ShowStat;
BEGIN
ConLineOut (' (status', 8);
PutHex2 (lastStat);
ConCharOut (')');
END;

PROCEDURE TxStat;
BEGIN
TxPut (' (status', 8);
TxHex2 (lastStat);
TxChar (ORD (')'));
END;

{ Is there a 7220? Its utility register keeps what is written to it
  (the same test the GRiD-OS driver makes). }
FUNCTION Present: BOOLEAN;
BEGIN
BubPut (0AH, 5AH);
Present := BubGet (0AH) = 5AH;
END;

{ Stops whatever the controller does and gets it ready for a command:
  Abort, the 150 ms pause the GRiD-OS driver makes after it, MBM Purge
  and Reset FIFO. The purge also makes the controller forget where
  page 0 is, so an Initialize is needed again after it. }
FUNCTION ResetBmc: BOOLEAN;
VAR s: INTEGER;
	ok: BOOLEAN;
BEGIN
BubCmd (cmdAbort);
s := WaitDone (500);
OsDelay (150);
ok := RunCmd (cmdPurge, 500);
IF ok THEN
	ok := RunCmd (cmdResetFifo, 500);
ResetBmc := ok;
END;

{ After a page transfer went wrong: clears the error the way GRiD-OS
  does (Abort, pause, Software Reset), without a purge, so the
  controller keeps its place. lastStat keeps the error. }
PROCEDURE ClearError;
VAR s, keep: INTEGER;
BEGIN
keep := lastStat;
BubCmd (cmdAbort);
s := WaitDone (500);
OsDelay (150);
IF RunCmd (cmdSwReset, 500) THEN;
lastStat := keep;
END;

{ Number of modules: Read FSA Status gives two status bytes per
  module; an empty position reads FFH. First the way GRiD's own
  driver (1984, made for 1 to 4 modules) does it: Abort, Software
  Reset, Reset FIFO, Read FSA Status, count the bytes that are not
  FFH, halve. If that finds nothing, again after an MBM Purge. The
  bytes are kept in fsaRaw to show on the main page.
  The address register is set to the last possible module first: on
  a real 1101 the count came out one short without it. }
FUNCTION FsaCount (purge: BOOLEAN): INTEGER;
VAR n, i, b, s: INTEGER;
	ok: BOOLEAN;
BEGIN
n := 0;
fsaN := 0;
BubCmd (cmdAbort);
s := WaitDone (500);
OsDelay (150);
IF purge THEN
	ok := RunCmd (cmdPurge, 500)
ELSE
	ok := RunCmd (cmdSwReset, 500);
IF ok THEN
	ok := RunCmd (cmdResetFifo, 500);
{ the address register names the last possible module, so the
  status of every position comes back (an empty one reads FFH) }
IF ok THEN
	BubParams (blrOne, 0, (maxMbm - 1) * 2048);
IF ok THEN
	ok := RunCmd (cmdRdFsa, 500);
IF ok THEN
	BEGIN
	BubSelFifo;
	i := 0;
	WHILE (i < 2 * maxMbm) AND Bit (BubStat, 0) DO
		BEGIN
		b := BubFifoR;
		fsaRaw[i] := b;
		IF b <> 0FFH THEN
			n := n + 1;
		i := i + 1;
		END;
	fsaN := i;
	END;
IF RunCmd (cmdResetFifo, 500) THEN;
n := n DIV 2;
IF n > maxMbm THEN n := maxMbm;
FsaCount := n;
END;

{ Reads module m's bootloop (only reads, never writes). }
FUNCTION ReadBootloop (m: INTEGER; VAR map: MapType): BOOLEAN;
VAR i, keep: INTEGER;
	ok: BOOLEAN;
BEGIN
ok := ResetBmc;
IF ok THEN
	BEGIN
	BubParams (blrOne, 0, m * 2048);
	ok := RunCmd (cmdRdBL, 1000);
	END;
IF ok THEN
	BEGIN
	BubSelFifo;
	i := 0;
	WHILE (i < mapBytes) AND Bit (BubStat, 0) DO
		BEGIN
		map[i] := BubFifoR;
		i := i + 1;
		END;
	ok := i = mapBytes;
	END;
keep := lastStat;
IF RunCmd (cmdResetFifo, 500) THEN;
lastStat := keep;
ReadBootloop := ok;
END;

{ Initialize of modules 0..last with enable register er (0, or enGrid
  the way GRiD-OS does it): the controller reads each one's bootloop
  into its FSA and finds page 0. The address register names the last
  module; naming more modules than are fitted makes it fail, and so
  does a module with a damaged bootloop. Only reads.
  On real hardware Read Bootloop and Write Bootloop only work after an
  Initialize has succeeded since power-on, so EnsureInit is called
  before them. }
FUNCTION InitUpTo (last, er: INTEGER): BOOLEAN;
VAR keep: INTEGER;
	ok: BOOLEAN;
BEGIN
ok := ResetBmc;
IF ok THEN
	BEGIN
	BubParams (blrOne, er, last * 2048);
	ok := RunCmd (cmdInit, 3000);
	IF Bit (lastStat, 7) THEN
		BEGIN
		{ still busy: it never found the bootloop; stop it }
		keep := lastStat;
		BubCmd (cmdAbort);
		IF WaitDone (500) = 0 THEN;
		OsDelay (150);
		lastStat := keep;
		END;
	END;
InitUpTo := ok;
END;

FUNCTION InitAll: BOOLEAN;
BEGIN
InitAll := InitUpTo (nMbm - 1, 0);
END;

{ Initializes as many modules as will: all of them, or else modules
  0..j for the largest j that works (a module with a damaged
  bootloop stops the Initialize there). Gives that number. }
FUNCTION EnsureInit: INTEGER;
VAR j, keep: INTEGER;
BEGIN
j := nMbm - 1;
WHILE (j >= 0) AND NOT InitUpTo (j, 0) DO
	BEGIN
	IF j = nMbm - 1 THEN
		keep := lastStat;
	j := j - 1;
	END;
IF j < nMbm - 1 THEN
	lastStat := keep;
EnsureInit := j + 1;
END;

FUNCTION CountMbm: INTEGER;
VAR n, m, j: INTEGER;
BEGIN
n := 0;
IF Present THEN
	BEGIN
	n := FsaCount (FALSE);
	IF n = 0 THEN
		n := FsaCount (TRUE);
	{ count up while Initialize works; it fails once it names a
	  position with no module (or a damaged bootloop) }
	j := 0;
	WHILE (j < maxMbm) AND InitUpTo (j, 0) DO
		j := j + 1;
	IF j > n THEN
		n := j;
	{ leave the controller initialized }
	IF j > 0 THEN
		IF InitUpTo (j - 1, 0) THEN;
	{ a module behind the last one counted whose bootloop can be
	  read is there too }
	FOR m := n TO maxMbm - 1 DO
		IF ReadBootloop (m, curMap) THEN
			n := m + 1;
	END;
CountMbm := n;
END;

{ Writes map into module m's bootloop exactly the way Intel's own
  BOOTUP routine does it (AP-150, BPK 72 driver, 1983 Memory Component
  Handbook):
    - load the parametric registers with write-bootloop enable set,
    - Reset FIFO,
    - 40 bytes of FFH into the FIFO, then Write Bootloop Register:
      every one of the 320 loops switched on in the FSA. Write
      Bootloop puts one bit into each of the 320 loops, so with only
      the good loops switched on the controller runs short (timing
      error, status 30),
    - Reset FIFO,
    - the 40 map bytes plus a 41st byte of 00H into the FIFO (the
      controller starts taking it the moment the command is given),
      then Write Bootloop.
  Result: 0 = done, 1 = controller would not reset, 2 = Write
  Bootloop failed, 4 = switching all loops on failed. wbFed, wbLeft
  and wbMs tell how many bytes were given, how many were left over in
  the FIFO, and how long Write Bootloop ran. }
FUNCTION WriteBootloop (m: INTEGER; VAR map: MapType): INTEGER;
VAR i, s, v, res, keep: INTEGER;
BEGIN
res := 0;
wbFed := 0;
wbLeft := 0;
wbMs := 0;
IF NOT ResetBmc THEN
	res := 1
ELSE
	BEGIN
	BubParams (blrOne, enWrBL, m * 2048);
	IF NOT RunCmd (cmdResetFifo, 500) THEN
		res := 4
	ELSE
		BEGIN
		{ all loops on in the FSA's loop register }
		BubSelFifo;
		FOR i := 0 TO mapBytes - 1 DO
			BubFifoW (0FFH);
		IF NOT RunCmd (cmdWrBLR, 500) THEN
			res := 4;
		END;
	END;
IF res = 0 THEN
	BEGIN
	IF NOT RunCmd (cmdResetFifo, 500) THEN
		res := 4;
	END;
IF res = 0 THEN
	BEGIN
	BubSelFifo;
	FOR i := 0 TO mapBytes - 1 DO
		BubFifoW (map[i]);
	BubFifoW (0);
	wbFed := mapBytes + 1;
	BubCmd (cmdWrBL);
	s := WaitDone (2000);
	wbMs := lastMs;
	IF Bit (s, 7) THEN
		BEGIN
		keep := s;
		BubCmd (cmdAbort);
		s := WaitDone (500);
		lastStat := keep;
		res := 2;
		END
	ELSE
		BEGIN
		{ count what the controller did not take }
		BubSelFifo;
		WHILE Bit (BubStat, 0) AND (wbLeft < 64) DO
			BEGIN
			v := BubFifoR;
			wbLeft := wbLeft + 1;
			END;
		lastStat := s;
		IF NOT StatOk (s) THEN
			res := 2;
		END;
	END;
IF res <> 1 THEN
	BEGIN
	{ take the permission to write the bootloop away again }
	BubParams (blrOne, 0, m * 2048);
	keep := lastStat;
	IF RunCmd (cmdResetFifo, 500) THEN;
	lastStat := keep;
	END;
WriteBootloop := res;
END;

{ Loads map into module m's FSA without writing anything to the
  module: Abort, MBM Purge, Reset FIFO, then the 40 map bytes and
  Write Bootloop Register Masked (Intel: functionally like an
  Initialize, but the map comes from us). Masked keeps 136 good loops
  a half (135 with error correction), as an Initialize does. The
  controller then reads and writes pages, but without a bootloop it
  cannot find page 0, so the pages may be counted from another
  place. er: the enable register to work with (0 or enGrid). }
FUNCTION LoadMapFsa (m, er: INTEGER; VAR map: MapType): BOOLEAN;
VAR i: INTEGER;
	ok: BOOLEAN;
BEGIN
ok := ResetBmc;
IF ok THEN
	BEGIN
	BubParams (blrOne, er, m * 2048);
	ok := RunCmd (cmdResetFifo, 500);
	END;
IF ok THEN
	BEGIN
	BubSelFifo;
	FOR i := 0 TO mapBytes - 1 DO
		BubFifoW (map[i]);
	ok := RunCmd (cmdWrBLRMasked, 500);
	END;
LoadMapFsa := ok;
END;

{ Reads page p of module m (64 bytes with error correction when er
  is enGrid, 68 raw bytes when er is 0) into the assembly part's
  RDBUF. Gives the bytes read; lastStat has the status. After an
  error the controller is cleared without losing its place. }
FUNCTION ReadPage (m, p, er, n: INTEGER): INTEGER;
VAR got, s: INTEGER;
BEGIN
IF RunCmd (cmdResetFifo, 500) THEN;
BubParams (blrOne, er, m * 2048 + p);
got := BubRdData (cmdRead, n);
s := WaitDone (1000);
IF (got < n) OR NOT StatOk (s) OR Bit (s, 2) THEN
	ClearError;
ReadPage := got;
END;

{ Writes WRBUF (n bytes) to page p of module m. TRUE when done. }
FUNCTION WritePage (m, p, er, n: INTEGER): BOOLEAN;
VAR got, s: INTEGER;
	ok: BOOLEAN;
BEGIN
IF RunCmd (cmdResetFifo, 500) THEN;
BubParams (blrOne, er, m * 2048 + p);
got := BubWrData (cmdWrite, n);
s := WaitDone (1000);
ok := (got = n) AND StatOk (s);
IF NOT ok THEN
	ClearError;
WritePage := ok;
END;

{ A page read that gave every byte with no error left: the status may
  only say "corrected" (08H) or parity (02H) on top of done. }
FUNCTION PageGood (got, n, s: INTEGER): BOOLEAN;
BEGIN
PageGood := (got = n) AND StatOk (s) AND NOT Bit (s, 2) AND NOT Bit (s, 4);
END;

.

$COMPACT SS(32)
MODULE bfmaps;

{ GRiD Bubble Fix 2, by Conventional Memories (C.M._).
  Part of bubfix (see bubfix.pas): shared screens, getting a module ready, writing a bootloop, finding files, menu 2. }

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

PRIVATE bfmaps;

{ ---------- screens used everywhere ---------- }

PROCEDURE Title;
BEGIN
Cls;
ConLineOut ('GRiD Bubble Fix 2.0.0', 21);
NewLine (1);
END;

{ Which module: 0.., -1 for Code-Esc, -2 for all (only when all is
  offered). The question is on the screen already. }
FUNCTION ChooseModule (all: BOOLEAN): INTEGER;
VAR m, key: INTEGER;
BEGIN
NewLine (1);
ConLineOut ('Module 1-', 9);
PutNum (nMbm);
IF all THEN
	BEGIN
	ConLineOut (', or A for all of them', 22);
	END;
NewLine (1);
ConLineOut ('(Code-Esc goes back)', 20);
REPEAT
	key := UpKey (GetKey);
	m := key - ORD ('1');
UNTIL IsCancel (key) OR ((m >= 0) AND (m < nMbm)) OR
      (all AND (key = ORD ('A')));
IF IsCancel (key) THEN
	m := -1
ELSE IF key = ORD ('A') THEN
	m := -2;
ChooseModule := m;
END;

{ Gets a map for module m into newMap, from a file or the label. }
FUNCTION GetNewMap (m: INTEGER): BOOLEAN;
VAR key: INTEGER;
	ok: BOOLEAN;
BEGIN
NewLine (2);
ConLineOut ('Map for module', 14);
PutNum (m + 1);
ConCharOut (':');
NewLine (1);
ConLineOut ('F  from a map file saved by Bubble Fix', 38);
NewLine (1);
ConLineOut ('L  typed in from the module''s label', 35);
NewLine (1);
ConLineOut ('(Code-Esc goes back)', 20);
REPEAT
	key := UpKey (GetKey);
UNTIL IsCancel (key) OR (key = ORD ('F')) OR (key = ORD ('L'));
ok := FALSE;
IF NOT IsCancel (key) THEN
	BEGIN
	Title;
	NewLine (1);
	ConLineOut ('Map for module', 14);
	PutNum (m + 1);
	IF key = ORD ('F') THEN
		BEGIN
		ok := AskName (0);
		IF ok THEN
			BEGIN
			MakePath (FALSE, -1, 1);
			ok := LoadFile (m);
			IF NOT ok THEN
				AnyKey;
			END;
		END
	ELSE
		ok := TypeMap (m);
	END;
IF ok THEN
	newFor := m;
GetNewMap := ok;
END;

{ Gets module m ready to read and write pages with enable register er
  (enGrid: 64 bytes a page, corrected; 0: 68 raw bytes).
  Gives 1 when an Initialize found page 0, so the pages are in their
  real order; 2 when the module's own map was loaded into the FSA;
  3 when a map from a file or the label was; 0 when none worked.
  Without an Initialize the controller does not know where page 0 is,
  so with 2 and 3 the pages may be shifted. prepMap / prepMapOk get
  the module's own map when it can be read. ask: may ask for a map. }
FUNCTION Prepare (m, er: INTEGER; ask: BOOLEAN): INTEGER;
VAR res: INTEGER;
BEGIN
res := 0;
initN := EnsureInit;
prepMapOk := ReadBootloop (m, prepMap);
IF prepMapOk THEN
	prepMapOk := MapUsable (prepMap);
IF InitUpTo (m, er) THEN
	res := 1
ELSE IF prepMapOk THEN
	BEGIN
	IF LoadMapFsa (m, er, prepMap) THEN
		res := 2;
	END;
{ a map given for this module earlier in this run }
IF (res = 0) AND (newFor = m) THEN
	BEGIN
	IF LoadMapFsa (m, er, newMap) THEN
		res := 3;
	END;
IF (res = 0) AND ask THEN
	BEGIN
	NewLine (2);
	ConLineOut ('This module does not initialize and its own map', 47);
	NewLine (1);
	ConLineOut ('cannot be read, so the map must come from a map file', 52);
	NewLine (1);
	ConLineOut ('or the label.', 13);
	NewLine (1);
	IF GetNewMap (m) THEN
		IF LoadMapFsa (m, er, newMap) THEN
			res := 3;
	END;
prepLevel := res;
Prepare := res;
END;

{ What a Prepare result means, on the screen. }
PROCEDURE ShowLevel (lvl: INTEGER);
BEGIN
IF lvl = 1 THEN
	BEGIN
	ConLineOut ('Initialized: pages in their real order', 38);
	END
ELSE IF lvl = 2 THEN
	BEGIN
	ConLineOut ('Own map loaded: pages may be shifted', 36);
	END
ELSE IF lvl = 3 THEN
	BEGIN
	ConLineOut ('Given map loaded: pages may be shifted', 38);
	END
ELSE
	BEGIN
	ConLineOut ('No map: the module cannot be read', 33);
	END;
END;

PROCEDURE TxLevel (lvl: INTEGER);
BEGIN
IF lvl = 1 THEN
	BEGIN
	TxPut ('initialized (pages in real order)', 33);
	END
ELSE IF lvl = 2 THEN
	BEGIN
	TxPut ('own map loaded (page 0 not known)', 33);
	END
ELSE IF lvl = 3 THEN
	BEGIN
	TxPut ('given map loaded (page 0 not known)', 35);
	END
ELSE
	BEGIN
	TxPut ('no usable map', 13);
	END;
END;

{ ---------- writing a bootloop ---------- }

{ Shows the new map next to what the module has now, and asks. }
FUNCTION CheckAndConfirm (m: INTEGER): BOOLEAN;
VAR ok, readable: BOOLEAN;
BEGIN
Title;
NewLine (1);
ConLineOut ('New map for module', 18);
PutNum (m + 1);
ConCharOut (',');
ShowCounts (newMap);
ShowMap (newMap);
ok := MapUsable (newMap);
IF NOT ok THEN
	BEGIN
	NewLine (2);
	ConLineOut ('Each half needs 136 good loops. Check the digits;', 49);
	NewLine (1);
	ConLineOut ('nothing has been written.', 25);
	AnyKey;
	END
ELSE
	BEGIN
	NewLine (2);
	ConLineOut ('Reading the module''s own map...', 31);
	initN := EnsureInit;
	readable := ReadBootloop (m, curMap);
	ConMoveCsr (0, row);
	;
	ConMoveCsr (0, row);
	IF readable AND SameMap (curMap, newMap) THEN
		BEGIN
		ConLineOut ('The module already has this map. Nothing to do.', 47);
		AnyKey;
		ok := FALSE;
		END
	ELSE
		BEGIN
		IF readable THEN
			BEGIN
			ConLineOut ('WARNING: the module now has another map:', 40);
			ShowMap (curMap);
			NewLine (1);
			ConLineOut ('Is this really the right module?', 32);
			END
		ELSE
			BEGIN
			ConLineOut ('The module''s own map cannot be read', 35);
			ShowStat;
			END;
		NewLine (2);
		ConLineOut ('Writing the bootloop changes the module for good.', 49);
		NewLine (1);
		ConLineOut ('Keep the old map if you have it: menu 2, 2 saves it.', 52);
		NewLine (1);
		ConLineOut ('Code-Return writes, Code-Esc cancels.', 37);
		ok := Confirmed;
		END;
	END;
CheckAndConfirm := ok;
END;

{ "Bytes given 41, left 1, 84 ms" }
PROCEDURE ShowWrite;
BEGIN
ConLineOut ('Bytes given', 11);
PutNum (wbFed);
ConLineOut (', left', 6);
PutNum (wbLeft);
ConCharOut (',');
PutNum (wbMs);
ConLineOut (' ms', 3);
ShowStat;
END;

{ Writes newMap into module m, reads it back, initializes. }
PROCEDURE DoWrite (m: INTEGER);
VAR res: INTEGER;
BEGIN
Title;
NewLine (1);
ConLineOut ('Writing the map of module', 25);
PutNum (m + 1);
ConLineOut ('...', 3);
initN := EnsureInit;
res := WriteBootloop (m, newMap);
TxModule (m);
TxPut ('map written:', 12);
IF res = 0 THEN
	BEGIN
	ConLineOut (' done', 5);
	NewLine (1);
	ConLineOut ('Reading it back...', 18);
	initN := EnsureInit;
	IF NOT ReadBootloop (m, curMap) THEN
		BEGIN
		ConLineOut (' failed', 7);
		ShowStat;
		res := 4;
		END
	ELSE IF NOT SameMap (curMap, newMap) THEN
		BEGIN
		ConLineOut (' it differs:', 12);
		ShowMap (curMap);
		res := 4;
		END
	ELSE
		BEGIN
		ConLineOut (' same, good', 11);
		END;
	END
ELSE
	BEGIN
	IF res = 1 THEN
		BEGIN
		ConLineOut (' controller did not respond', 27);
		END
	ELSE IF res = 2 THEN
		BEGIN
		ConLineOut (' Write Bootloop failed', 22);
		END
	ELSE
		BEGIN
		ConLineOut (' could not switch loops on', 26);
		END;
	ShowStat;
	END;
IF res = 0 THEN
	BEGIN
	TxPut (' OK', 3);
	END
ELSE
	BEGIN
	TxPut (' FAILED', 7);
	TxStat;
	END;
TxEnd;
TxMap (newMap);
NewLine (1);
ShowWrite;
IF res = 0 THEN
	BEGIN
	NewLine (1);
	ConLineOut ('Initialize of the bubble...', 27);
	IF InitAll THEN
		BEGIN
		ConLineOut (' OK', 3);
		NewLine (2);
		ConLineOut ('Restart the GRiD. If this is the old map, the files', 51);
		NewLine (1);
		ConLineOut ('may be back: copy them. Otherwise use Initialize', 48);
		NewLine (1);
		ConLineOut ('Media.', 6);
		END
	ELSE
		BEGIN
		ConLineOut (' failed', 7);
		ShowStat;
		NewLine (1);
		ConLineOut ('Another module may need its map too.', 36);
		END;
	END
ELSE
	BEGIN
	NewLine (2);
	ConLineOut ('The bootloop may be half written now. It is safe to', 51);
	NewLine (1);
	ConLineOut ('try again with the same map. If it keeps failing, the', 53);
	NewLine (1);
	ConLineOut ('module may have lost its seeds: see Tests 2.', 44);
	END;
AnyKey;
END;

{ ---------- finding GRiD-OS files in pages ---------- }

{ GRiD-OS keeps files in 256-byte blocks, 4 bubble pages each. The
  first page of a file's header block starts with the block's own
  number (2 bytes, then 2 zero bytes), the file size (4 bytes), the
  length of the name and the name. HeaderAt gives that block number
  when pgBuf looks like such a page of module m, else -1. }
FUNCTION HeaderAt (m: INTEGER): INTEGER;
VAR t, len, i, tildes: INTEGER;
	ok: BOOLEAN;
BEGIN
t := -1;
ok := (pgBuf[2] = 0) AND (pgBuf[3] = 0) AND (pgBuf[1] < 8) AND
      (pgBuf[7] = 0) AND (pgBuf[6] < 7);
len := pgBuf[8];
IF ok THEN
	ok := (len >= 3) AND (len <= 55);
IF ok THEN
	BEGIN
	tildes := 0;
	FOR i := 9 TO 8 + len DO
		BEGIN
		IF pgBuf[i] = ORD ('~') THEN
			tildes := tildes + 1
		ELSE IF (pgBuf[i] < 32) OR (pgBuf[i] > 126) THEN
			ok := FALSE;
		END;
	ok := ok AND (tildes >= 2);
	END;
IF ok THEN
	BEGIN
	t := pgBuf[0] + 256 * pgBuf[1];
	IF (t DIV 512) <> m THEN
		t := -1;
	END;
HeaderAt := t;
END;

PROCEDURE VoteReset;
VAR i: INTEGER;
BEGIN
FOR i := 0 TO 7 DO
	BEGIN
	voteOff[i] := 0;
	voteN[i] := 0;
	END;
END;

{ A header block t found at page p (as read) of module m says the
  pages are shifted by (real page - p). }
PROCEDURE Vote (m, t, p: INTEGER);
VAR off, i, j: INTEGER;
BEGIN
off := t * 4 - m * 2048 - p;
WHILE off < 0 DO
	off := off + 2048;
off := off MOD 2048;
j := -1;
FOR i := 7 DOWNTO 0 DO
	IF (voteN[i] > 0) AND (voteOff[i] = off) THEN
		j := i;
IF j < 0 THEN
	FOR i := 7 DOWNTO 0 DO
		IF voteN[i] = 0 THEN
			j := i;
IF j >= 0 THEN
	BEGIN
	voteOff[j] := off;
	voteN[j] := voteN[j] + 1;
	END;
END;

{ The shift most headers agree on, or -1 when none was found. }
FUNCTION BestOff: INTEGER;
VAR i, best: INTEGER;
BEGIN
best := -1;
FOR i := 0 TO 7 DO
	IF voteN[i] > 0 THEN
		IF best < 0 THEN
			best := i
		ELSE IF voteN[i] > voteN[best] THEN
			best := i;
IF best >= 0 THEN
	BestOff := voteOff[best]
ELSE
	BestOff := -1;
END;

FUNCTION BestVotes: INTEGER;
VAR i, n: INTEGER;
BEGIN
n := 0;
FOR i := 0 TO 7 DO
	IF voteN[i] > n THEN
		n := voteN[i];
BestVotes := n;
END;

{ Keeps the header in pgBuf (block t, read at page p) in the list. }
PROCEDURE DirAdd (t, p: INTEGER);
VAR i, len, k: INTEGER;
BEGIN
dirHeaders := dirHeaders + 1;
IF dirN < 100 THEN
	BEGIN
	len := pgBuf[8];
	IF len > 30 THEN
		len := 30;
	FOR i := 0 TO len - 1 DO
		dirName[dirN, i] := CHR (pgBuf[9 + i]);
	dirNameLen[dirN] := len;
	{ size in K, rounded up }
	k := pgBuf[5] DIV 4 + pgBuf[6] * 64;
	IF (pgBuf[4] > 0) OR ((pgBuf[5] MOD 4) > 0) THEN
		k := k + 1;
	dirK[dirN] := k;
	dirPage[dirN] := p;
	dirN := dirN + 1;
	END;
END;

{ Shows the list: name, size, page (as the module counts it, using the
  shift the headers agree on). One screen at a time. }
PROCEDURE ShowDir (m, off: INTEGER);
VAR i, j, n, key, per: INTEGER;
BEGIN
per := scrRows - 5;
IF per < 5 THEN
	per := 5;
i := 0;
key := 0;
REPEAT
	Title;
	ConLineOut ('Files found on module', 21);
	PutNum (m + 1);
	ConCharOut (':');
	PutNum (dirHeaders);
	NewLine (1);
	ConLineOut ('Name                              size K    page', 48);
	NewLine (1);
	n := 0;
	WHILE (n < per) AND (i < dirN) DO
		BEGIN
		FOR j := 0 TO dirNameLen[i] - 1 DO
			ConCharOut (dirName[i, j]);
		ConMoveCsr (34, row);
		PutNum (dirK[i]);
		ConMoveCsr (45, row);
		IF off >= 0 THEN
			PutNum ((dirPage[i] + off) MOD 2048)
		ELSE
			PutNum (dirPage[i]);
		NewLine (1);
		i := i + 1;
		n := n + 1;
		END;
	IF dirN = 0 THEN
		BEGIN
		ConLineOut ('No file headers found.', 22);
		NewLine (1);
		END;
	NewLine (1);
	IF i < dirN THEN
		BEGIN
		ConLineOut ('Any key: more, Code-Esc: done', 29);
		END
	ELSE
		BEGIN
		IF dirHeaders > dirN THEN
			BEGIN
			ConLineOut ('(only the first 100 are shown)', 30);
			NewLine (1);
			END;
		ConLineOut ('Any key: done', 13);
		END;
	key := GetKey;
UNTIL (i >= dirN) OR IsCancel (key);
END;

{ Reads module m (prepared with enGrid) and lists the files whose
  header blocks it finds. Reads every 4th page when the pages are in
  their real order, else every page. Gives the number of pages that
  read without errors (nRead gives how many were read). }
FUNCTION ScanModule (m: INTEGER; VAR nRead: INTEGER): INTEGER;
VAR p, step, got, good, t, i: INTEGER;
	stop: BOOLEAN;
BEGIN
dirN := 0;
dirHeaders := 0;
VoteReset;
IF prepLevel = 1 THEN
	step := 4
ELSE
	step := 1;
good := 0;
nRead := 0;
p := 0;
stop := FALSE;
NewLine (1);
ConLineOut ('Code-Esc stops.', 15);
WHILE (p < modPages) AND NOT stop DO
	BEGIN
	got := ReadPage (m, p, enGrid, eccBytes);
	nRead := nRead + 1;
	IF PageGood (got, eccBytes, lastStat) THEN
		BEGIN
		good := good + 1;
		FOR i := 0 TO eccBytes - 1 DO
			pgBuf[i] := BubRdByte (i);
		t := HeaderAt (m);
		IF t >= 0 THEN
			BEGIN
			DirAdd (t, p);
			Vote (m, t, p);
			END;
		END;
	p := p + step;
	IF (nRead MOD 32) = 0 THEN
		BEGIN
		ConMoveCsr (0, row + 1);
		ConLineOut ('Page', 4);
		PutNum (p);
		ConLineOut (', readable', 10);
		PutNum (good);
		ConLineOut (', files', 7);
		PutNum (dirHeaders);
		;
		stop := StopAsked;
		END;
	END;
NewLine (1);
ScanModule := good;
END;

{ Says what a scan found, on the screen and in the log. }
PROCEDURE ScanResult (m, good, nRead: INTEGER);
BEGIN
NewLine (2);
ConLineOut ('Readable pages:', 15);
PutNum (good);
ConLineOut (' of', 3);
PutNum (nRead);
NewLine (1);
ConLineOut ('File headers found:', 19);
PutNum (dirHeaders);
TxModule (m);
TxPut ('listing:', 8);
TxNum (good);
TxPut (' of', 3);
TxNum (nRead);
TxPut (' pages readable,', 16);
TxNum (dirHeaders);
TxPut (' file headers', 13);
TxEnd;
IF (prepLevel <> 1) AND (dirHeaders > 0) THEN
	BEGIN
	NewLine (1);
	ConLineOut ('Shift of the pages:', 19);
	PutNum (BestOff);
	ConLineOut (' (', 2);
	PutNum (BestVotes);
	ConLineOut (' agree)', 7);
	END;
END;

{ ---------- menu 2: bubble maps ---------- }

{ 2-1: one module per page. }
PROCEDURE ShowMaps;
VAR m, key: INTEGER;
BEGIN
Title;
NewLine (1);
ConLineOut ('Reading the maps, please wait...', 32);
initN := EnsureInit;
m := 0;
key := 0;
WHILE (m < nMbm) AND NOT IsCancel (key) DO
	BEGIN
	Title;
	NewLine (1);
	ConLineOut ('Module', 6);
	PutNum (m + 1);
	ConLineOut (' of', 3);
	PutNum (nMbm);
	ConCharOut (':');
	TxModule (m);
	IF ReadBootloop (m, curMap) THEN
		BEGIN
		ShowCounts (curMap);
		ShowMap (curMap);
		TxCounts (curMap);
		TxEnd;
		TxMap (curMap);
		IF NOT MapUsable (curMap) THEN
			BEGIN
			NewLine (1);
			ConLineOut ('Too few good loops: this map is damaged.', 40);
			END;
		NewLine (2);
		ConLineOut ('Compare it with the label on the module.', 40);
		NewLine (1);
		END
	ELSE
		BEGIN
		ConLineOut ('map unreadable', 14);
		ShowStat;
		TxPut ('map unreadable', 14);
		TxStat;
		TxEnd;
		NewLine (2);
		ConLineOut ('Restore it with 3, from a map file or the label. Back', 53);
		NewLine (1);
		ConLineOut ('the module up first.', 20);
		NewLine (1);
		END;
	NewLine (1);
	IF m < nMbm - 1 THEN
		BEGIN
		ConLineOut ('Any key: next module, Code-Esc: back', 36);
		END
	ELSE
		BEGIN
		ConLineOut ('Any key: back', 13);
		END;
	key := GetKey;
	m := m + 1;
	END;
END;

{ 2-2: read all maps, save them. }
PROCEDURE SaveMaps;
VAR m, good: INTEGER;
BEGIN
Title;
NewLine (1);
ConLineOut ('Reading the maps, please wait...', 32);
initN := EnsureInit;
good := 0;
FOR m := 0 TO nMbm - 1 DO
	BEGIN
	NewLine (1);
	ConLineOut ('Module', 6);
	PutNum (m + 1);
	ConCharOut (':');
	mapOk[m] := ReadBootloop (m, maps[m]);
	IF mapOk[m] THEN
		mapOk[m] := MapUsable (maps[m]);
	IF mapOk[m] THEN
		BEGIN
		ShowCounts (maps[m]);
		good := good + 1;
		END
	ELSE
		BEGIN
		ConLineOut ('no good map, left out', 21);
		ShowStat;
		END;
	END;
IF good = 0 THEN
	BEGIN
	NewLine (2);
	ConLineOut ('No module has a readable map to save.', 37);
	AnyKey;
	END
ELSE IF AskName (1) THEN
	BEGIN
	MakePath (FALSE, -1, 1);
	IF SaveFile THEN
		BEGIN
		NewLine (2);
		ConLineOut ('Saved. Keep a copy on another floppy and photograph', 51);
		NewLine (1);
		ConLineOut ('the labels as well.', 19);
		TxPut ('Maps saved to', 13);
		TxPath;
		TxEnd;
		END;
	AnyKey;
	END;
END;

{ 2-3: write a map into a module's bootloop. }
PROCEDURE RestoreMap;
VAR m: INTEGER;
BEGIN
Title;
NewLine (1);
ConLineOut ('Restore the bootloop map of a module. Use this when', 51);
NewLine (1);
ConLineOut ('the module does not initialize. Have the right map', 50);
NewLine (1);
ConLineOut ('ready: a map file, or the label''s 80 digits.', 44);
NewLine (1);
m := ChooseModule (FALSE);
IF m >= 0 THEN
	IF GetNewMap (m) THEN
		IF CheckAndConfirm (m) THEN
			DoWrite (m);
END;

{ Tries newMap on module m without writing it: loads it into the FSA
  and lists the files it makes readable. Then offers to write it. }
PROCEDURE TryMap (m: INTEGER);
VAR good, nRead, key: INTEGER;
BEGIN
Title;
NewLine (1);
ConLineOut ('Checking the map on module', 26);
PutNum (m + 1);
ConLineOut ('...', 3);
initN := EnsureInit;
IF LoadMapFsa (m, enGrid, newMap) THEN
	BEGIN
	prepLevel := 3;
	good := ScanModule (m, nRead);
	TxModule (m);
	TxPut ('map checked:', 12);
	TxEnd;
	TxMap (newMap);
	ScanResult (m, good, nRead);
	NewLine (2);
	IF good > nRead DIV 2 THEN
		BEGIN
		ConLineOut ('Most pages read: the map looks right.', 37);
		NewLine (1);
		END
	ELSE
		BEGIN
		ConLineOut ('Few pages read: the map looks wrong, or the module', 50);
		NewLine (1);
		ConLineOut ('lost its data.', 14);
		NewLine (1);
		END;
	ConLineOut ('L lists the files, W writes this map,', 37);
	NewLine (1);
	ConLineOut ('any other key goes back.', 24);
	key := UpKey (GetKey);
	IF key = ORD ('L') THEN
		BEGIN
		ShowDir (m, BestOff);
		Title;
		NewLine (1);
		ConLineOut ('W writes this map, any other key back.', 38);
		key := UpKey (GetKey);
		END;
	IF key = ORD ('W') THEN
		IF CheckAndConfirm (m) THEN
			DoWrite (m);
	END
ELSE
	BEGIN
	NewLine (1);
	ConLineOut ('The controller would not take the map', 37);
	ShowStat;
	AnyKey;
	END;
END;

{ 2-4: try a map without writing it. }
PROCEDURE CheckMap;
VAR m: INTEGER;
BEGIN
Title;
NewLine (1);
ConLineOut ('Check a map before writing it. The map is only loaded', 53);
NewLine (1);
ConLineOut ('into the controller, nothing is written to the', 46);
NewLine (1);
ConLineOut ('bubble. When many pages read well and file names show', 53);
NewLine (1);
ConLineOut ('up, the map is right.', 21);
NewLine (1);
m := ChooseModule (FALSE);
IF m >= 0 THEN
	IF GetNewMap (m) THEN
		TryMap (m);
END;

.

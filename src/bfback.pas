$COMPACT SS(32)
MODULE bfback;

{ GRiD Bubble Fix 2, by Conventional Memories (C.M._).
  Part of bubfix (see bubfix.pas): backup files, backing up (menu 1, 1 and 2). }

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

PRIVATE bfback;


{ ---------- menu 1: backup and restore ---------- }

{ A backup file ("<name> Module N~Bin~" or "~Raw~"):
    64-byte header: 'BUBBACK1', module (0..7), 'C' or 'R', bytes a
      page (64 or 68), how page 0 was found (1 Initialize, 2 the
      module's own map, 3 a map given by the user), pages (2048, low
      byte first), 2 zero bytes, 1 when a map follows, the map (40
      bytes), zeros up to 64.
    every page in turn (64 or 68 bytes); pages not read are zeros.
    a status byte per page (40H or 42H good, 00H not read).
    16-byte tail: 'BUBTAIL1', pages read (2 bytes), check sum of the
      page bytes (4 bytes), the shift of the pages found from the file
      headers (2 bytes, FFFFH unknown).
  Version 1 files (pages and status bytes only) can be read too. }

{ A page status byte that says the page came in whole. }
FUNCTION StatGood (s: INTEGER): BOOLEAN;
BEGIN
StatGood := Bit (s, 6) AND NOT Bit (s, 5) AND NOT Bit (s, 7) AND
            NOT Bit (s, 2) AND NOT Bit (s, 4);
END;

PROCEDURE FwWord (w: INTEGER);
BEGIN
FwByte (w MOD 256);
FwByte (w DIV 256);
END;

{ Writes the 64-byte header of a backup of module m. }
PROCEDURE WriteHeader (m, psize, lvl: INTEGER);
VAR i: INTEGER;
	map: MapType;
	have: BOOLEAN;
BEGIN
FOR i := 1 TO 8 DO
	FwByte (ORD (bakMagic[i]));
FwByte (m);
IF psize = eccBytes THEN
	FwByte (ORD ('C'))
ELSE
	FwByte (ORD ('R'));
FwByte (psize);
FwByte (lvl);
FwWord (modPages);
FwWord (0);
have := FALSE;
IF lvl = 3 THEN
	BEGIN
	map := newMap;
	have := TRUE;
	END
ELSE IF prepMapOk THEN
	BEGIN
	map := prepMap;
	have := TRUE;
	END;
IF have THEN
	FwByte (1)
ELSE
	FwByte (0);
FOR i := 0 TO mapBytes - 1 DO
	IF have THEN
		FwByte (map[i])
	ELSE
		FwByte (0);
FOR i := 57 TO 63 DO
	FwByte (0);
END;

{ Opens the backup file in pathBuf and reads its header. A file
  without one is taken as a version 1 copy: bkExt then says the bytes
  a page, and the module is not known (bkModule -1). }
FUNCTION OpenBackup: BOOLEAN;
VAR i, b: INTEGER;
	ok: BOOLEAN;
BEGIN
FrOpen;
ok := frErr = okCode;
IF ok THEN
	BEGIN
	bkLegacy := FALSE;
	FOR i := 0 TO 63 DO
		BEGIN
		b := FrByte;
		IF b < 0 THEN
			b := 0;
		pgBuf[i] := b;
		END;
	FOR i := 0 TO 7 DO
		IF pgBuf[i] <> ORD (bakMagic[i + 1]) THEN
			bkLegacy := TRUE;
	IF NOT bkLegacy THEN
		bkLegacy := (pgBuf[8] >= maxMbm) OR
		            ((pgBuf[10] <> eccBytes) AND (pgBuf[10] <> pageBytes));
	IF bkLegacy THEN
		BEGIN
		{ no header: the pages start at the beginning }
		FrClose;
		FrOpen;
		ok := frErr = okCode;
		bkModule := -1;
		IF bkExt = 3 THEN
			bkPsize := pageBytes
		ELSE
			bkPsize := eccBytes;
		bkSynced := 0;
		bkMapOk := FALSE;
		END
	ELSE
		BEGIN
		bkModule := pgBuf[8];
		bkPsize := pgBuf[10];
		bkSynced := pgBuf[11];
		bkMapOk := pgBuf[16] = 1;
		FOR i := 0 TO mapBytes - 1 DO
			bkMap[i] := pgBuf[17 + i];
		END;
	END;
IF NOT ok THEN
	BEGIN
	NewLine (2);
	ConLineOut ('Could not open the backup,', 26);
	ShowFileError (frErr);
	END;
OpenBackup := ok;
END;

{ The next page of the backup being read into pgBuf; FALSE when the
  file ends first. }
FUNCTION FrPage: BOOLEAN;
VAR i, b: INTEGER;
	ok: BOOLEAN;
BEGIN
ok := TRUE;
FOR i := 0 TO bkPsize - 1 DO
	BEGIN
	b := FrByte;
	IF b < 0 THEN
		BEGIN
		ok := FALSE;
		b := 0;
		END;
	pgBuf[i] := b;
	END;
FrPage := ok;
END;

{ Reads the whole backup in pathBuf: checks its check sum (or, for a
  version 1 file, its length), keeps the status bytes in pstat, counts
  the pages that were bad (bkBad) or not read (bkUnread), finds the
  file headers (for module m) and the shift of the pages (bkOff, -1
  when not known). bkTailOk: the file is whole. The backup must be
  opened with OpenBackup first; it is closed afterwards. }
PROCEDURE CheckBackup (m: INTEGER);
VAR p, i, b, t, done: INTEGER;
	whole: BOOLEAN;
BEGIN
dirN := 0;
dirHeaders := 0;
VoteReset;
BubCkReset;
whole := TRUE;
NewLine (1);
ConLineOut ('Checking the file...', 20);
p := 0;
WHILE (p < modPages) AND whole DO
	BEGIN
	IF NOT FrPage THEN
		whole := FALSE;
	FOR i := 0 TO bkPsize - 1 DO
		BubCkAdd (pgBuf[i]);
	IF whole AND ((bkSynced <> 1) OR ((p MOD 4) = 0)) THEN
		BEGIN
		t := HeaderAt (m);
		IF t >= 0 THEN
			BEGIN
			DirAdd (t, p);
			Vote (m, t, p);
			END;
		END;
	p := p + 1;
	IF (p MOD 256) = 0 THEN
		BEGIN
		ConMoveCsr (21, row);
		PutNum ((p DIV 16) * 100 DIV 128);
		ConCharOut ('%');
		END;
	END;
bkBad := 0;
bkUnread := 0;
FOR p := 0 TO modPages - 1 DO
	BEGIN
	b := FrByte;
	IF b < 0 THEN
		BEGIN
		whole := FALSE;
		b := 0;
		END;
	pstat[p] := CHR (b);
	IF b = 0 THEN
		bkUnread := bkUnread + 1
	ELSE IF NOT StatGood (b) THEN
		bkBad := bkBad + 1;
	END;
IF bkSynced = 1 THEN
	bkOff := 0
ELSE
	bkOff := BestOff;
IF bkLegacy THEN
	{ nothing may follow the status bytes }
	bkTailOk := whole AND (FrByte < 0)
ELSE
	BEGIN
	FOR i := 0 TO 15 DO
		BEGIN
		b := FrByte;
		IF b < 0 THEN
			BEGIN
			whole := FALSE;
			b := 0;
			END;
		pgBuf[i] := b;
		END;
	FOR i := 0 TO 7 DO
		IF pgBuf[i] <> ORD (tailMagic[i + 1]) THEN
			whole := FALSE;
	FOR i := 0 TO 3 DO
		BEGIN
		bkCk[i] := pgBuf[10 + i];
		IF bkCk[i] <> BubCkGet (i) THEN
			whole := FALSE;
		END;
	IF (bkSynced <> 1) AND (pgBuf[15] < 8) THEN
		bkOff := pgBuf[14] + 256 * pgBuf[15];
	bkTailOk := whole;
	END;
FrClose;
ConMoveCsr (0, row);
IF bkTailOk THEN
	BEGIN
	IF bkLegacy THEN
		BEGIN
		ConLineOut ('File complete (version 1, no check sum)', 39);
		END
	ELSE
		BEGIN
		ConLineOut ('File checked: check sum is right.', 33);
		END;
	END
ELSE
	BEGIN
	ConLineOut ('FILE DAMAGED: check sum or length wrong', 39);
	END;
NewLine (1);
done := modPages - bkUnread;
PutNum (done);
ConLineOut (' pages copied,', 14);
PutNum (bkBad);
ConLineOut (' of them with errors.', 21);
END;

{ Asks which backup to read and opens it: the type (C or R), the
  device and the name. For a version 1 file, asks for the module. }
FUNCTION AskBackup: BOOLEAN;
VAR key, i: INTEGER;
	ok: BOOLEAN;
BEGIN
NewLine (1);
ConLineOut ('Which copy?', 11);
NewLine (1);
ConLineOut ('C  corrected copy (~Bin~)', 25);
NewLine (1);
ConLineOut ('R  raw copy (~Raw~)', 19);
REPEAT
	key := UpKey (GetKey);
UNTIL IsCancel (key) OR (key = ORD ('C')) OR (key = ORD ('R'));
ok := NOT IsCancel (key);
IF key = ORD ('R') THEN
	bkExt := 3
ELSE
	bkExt := 2;
IF ok THEN
	ok := ChooseDest (TRUE);
IF ok THEN
	BEGIN
	Title;
	SetBaseName;
	FOR i := 1 TO 8 DO
		nameBuf[nameLen + i - 1] := modWord[i];
	nameLen := nameLen + 8;
	nameBuf[nameLen] := '1';
	nameLen := nameLen + 1;
	ConLineOut ('Give the whole name, with " Module N" but without the', 53);
	NewLine (1);
	ConLineOut ('type.', 5);
	ok := AskName (3);
	END;
IF ok THEN
	BEGIN
	MakePath (TRUE, -1, bkExt);
	ok := OpenBackup;
	IF ok AND bkLegacy THEN
		BEGIN
		NewLine (2);
		ConLineOut ('This is a version 1 copy. Which module was it copied', 52);
		NewLine (1);
		ConLineOut ('from?', 5);
		bkModule := ChooseModule (FALSE);
		IF bkModule < 0 THEN
			BEGIN
			FrClose;
			ok := FALSE;
			END;
		END;
	IF NOT ok THEN
		AnyKey;
	END;
IF ok THEN
	BEGIN
	Title;
	ConLineOut ('Backup of module', 16);
	PutNum (bkModule + 1);
	IF bkPsize = pageBytes THEN
		BEGIN
		ConLineOut (', raw', 5);
		END
	ELSE
		BEGIN
		ConLineOut (', corrected', 11);
		END;
	NewLine (1);
	PutPath;
	CheckBackup (bkModule);
	TxModule (bkModule);
	TxPut ('checked backup', 14);
	TxPath;
	IF bkTailOk THEN
		BEGIN
		TxPut (': OK,', 5);
		END
	ELSE
		BEGIN
		TxPut (': DAMAGED,', 10);
		END;
	TxNum (bkBad);
	TxPut (' bad pages', 10);
	TxEnd;
	END;
AskBackup := ok;
END;

{ Backs up module m into one file. Result: 0 done, 1 skipped,
  2 stop (no room on a fixed disk, or Code-Esc). }
FUNCTION BackupModule (m, er, psize: INTEGER; all: BOOLEAN): INTEGER;
VAR lvl, res, needK, freeK, key, p, i, got, s, b, bad, t, off: INTEGER;
	stop, made: BOOLEAN;
BEGIN
Title;
ConLineOut ('Backing up module', 17);
PutNum (m + 1);
ConLineOut (' of', 3);
PutNum (nMbm);
NewLine (2);
ConLineOut ('Getting the module ready...', 27);
lvl := Prepare (m, er, NOT all);
NewLine (1);
ShowLevel (lvl);
res := 0;
bkRes[m] := -2;
IF lvl = 0 THEN
	BEGIN
	bkRes[m] := -1;
	NewLine (2);
	ConLineOut ('Skipped: no usable map. "Back up one module" can take', 53);
	NewLine (1);
	ConLineOut ('a map from you.', 15);
	NewLine (1);
	TxModule (m);
	TxPut ('skipped, no usable map', 22);
	TxEnd;
	res := 1;
	IF NOT all THEN
		AnyKey
	ELSE
		OsDelay (2000);
	END;
{ the file, when there is room for it }
needK := 2 * psize + 3;
made := FALSE;
WHILE (res = 0) AND NOT made DO
	BEGIN
	MakePath (TRUE, m, bkExt);
	i := FwCreate (needK, freeK);
	NewLine (1);
	IF i = 0 THEN
		made := TRUE
	ELSE IF i = 2 THEN
		BEGIN
		PutPath;
		NewLine (1);
		ConLineOut ('exists already. O overwrites it,', 32);
		NewLine (1);
		ConLineOut ('S skips this module, Code-Esc stops.', 36);
		REPEAT
			key := UpKey (GetKey);
		UNTIL IsCancel (key) OR (key = ORD ('O')) OR (key = ORD ('S'));
		NewLine (1);
		IF key = ORD ('O') THEN
			DeleteFile
		ELSE IF key = ORD ('S') THEN
			BEGIN
			res := 1;
			bkRes[m] := -1;
			END
		ELSE
			res := 2;
		END
	ELSE
		BEGIN
		IF i = 1 THEN
			BEGIN
			ConLineOut ('Not enough room: needs', 22);
			PutNum (needK);
			ConLineOut ('K, has', 6);
			PutNum (freeK);
			ConLineOut ('K.', 2);
			END
		ELSE
			BEGIN
			ConLineOut ('Could not make the file,', 24);
			ShowFileError (fwErr);
			END;
		NewLine (1);
		IF destRemovable THEN
			BEGIN
			ConLineOut ('Put in another floppy (one that has been through', 48);
			NewLine (1);
			ConLineOut ('Initialize Media), then Return. Code-Esc stops.', 47);
			REPEAT
				key := GetKey;
			UNTIL IsCancel (key) OR (key = returnKey) OR (key = confirmKey);
			IF IsCancel (key) THEN
				res := 2
			ELSE
				BEGIN
				swapped := TRUE;
				Title;
				ConLineOut ('Backing up module', 17);
				PutNum (m + 1);
				NewLine (1);
				END;
			END
		ELSE
			BEGIN
			ConLineOut ('Free some room there, or pick a floppy.', 39);
			res := 2;
			AnyKey;
			END;
		END;
	END;
IF made THEN
	BEGIN
	Title;
	ConLineOut ('Backing up module', 17);
	PutNum (m + 1);
	ConLineOut (' to', 3);
	NewLine (1);
	PutPath;
	NewLine (1);
	ShowLevel (lvl);
	NewLine (1);
	ConLineOut ('Code-Esc stops.', 15);
	WriteHeader (m, psize, lvl);
	BubCkReset;
	VoteReset;
	bad := 0;
	p := 0;
	stop := FALSE;
	WHILE (p < modPages) AND NOT stop AND (fwErr = okCode) DO
		BEGIN
		got := ReadPage (m, p, er, psize);
		s := lastStat;
		IF (got < psize) AND NOT Bit (s, 5) THEN
			s := s + 32;
		IF s = 0 THEN
			s := 20H;
		FOR i := 0 TO psize - 1 DO
			BEGIN
			IF i < got THEN
				b := BubRdByte (i)
			ELSE
				b := 0;
			FwByte (b);
			BubCkAdd (b);
			pgBuf[i] := b;
			END;
		pstat[p] := CHR (s);
		IF NOT StatGood (s) THEN
			bad := bad + 1
		ELSE IF lvl <> 1 THEN
			BEGIN
			t := HeaderAt (m);
			IF t >= 0 THEN
				Vote (m, t, p);
			END;
		p := p + 1;
		IF (p MOD 32) = 0 THEN
			BEGIN
			ConMoveCsr (0, row + 2);
			ConLineOut ('Page', 4);
			PutNum (p);
			ConLineOut (' of 2048, errors', 16);
			PutNum (bad);
			;
			stop := StopAsked;
			END;
		END;
	{ the rest as zeros, not read }
	FOR i := p TO modPages - 1 DO
		BEGIN
		FOR b := 1 TO psize DO
			BEGIN
			FwByte (0);
			BubCkAdd (0);
			END;
		pstat[i] := CHR (0);
		END;
	FOR i := 0 TO modPages - 1 DO
		FwByte (ORD (pstat[i]));
	FOR i := 1 TO 8 DO
		FwByte (ORD (tailMagic[i]));
	FwWord (p);
	FOR i := 0 TO 3 DO
		FwByte (BubCkGet (i));
	IF lvl = 1 THEN
		off := 0
	ELSE
		off := BestOff;
	IF off < 0 THEN
		BEGIN
		FwByte (255);
		FwByte (255);
		END
	ELSE
		FwWord (off);
	made := FwClose;
	row := row + 3;
	NewLine (1);
	TxModule (m);
	IF NOT made THEN
		BEGIN
		ConLineOut ('Writing the file failed,', 24);
		ShowFileError (fwErr);
		TxPut ('backup FAILED, file error', 25);
		TxNum (ORD (fwErr));
		TxEnd;
		res := 2;
		END
	ELSE
		BEGIN
		bkRes[m] := bad;
		PutNum (p);
		ConLineOut (' pages saved,', 13);
		PutNum (bad);
		ConLineOut (' with errors.', 13);
		TxPut ('backed up to', 12);
		TxPath;
		TxChar (ORD (':'));
		TxNum (p);
		TxPut (' pages,', 7);
		TxNum (bad);
		TxPut (' with errors,', 13);
		TxLevel (lvl);
		TxEnd;
		IF lvl <> 1 THEN
			BEGIN
			NewLine (1);
			IF off >= 0 THEN
				BEGIN
				ConLineOut ('Page shift found from files:', 28);
				PutNum (off);
				END
			ELSE
				BEGIN
				ConLineOut ('No file headers: page shift unknown.', 36);
				END;
			END;
		IF stop THEN
			BEGIN
			NewLine (1);
			ConLineOut ('Stopped: the rest is left empty.', 32);
			res := 2;
			bkRes[m] := -4;
			END;
		{ read the file back: is it on the disk the way it was meant? }
		IF OpenBackup THEN
			BEGIN
			CheckBackup (m);
			IF NOT bkTailOk THEN
				BEGIN
				NewLine (1);
				ConLineOut ('The disk did not give the file back right. Use', 46);
				NewLine (1);
				ConLineOut ('another floppy or disk.', 23);
				NewLine (1);
				TxPut (' READ-BACK CHECK FAILED', 23);
				TxEnd;
				bkRes[m] := -3;
				END
			ELSE
				BEGIN
				TxPut (' read back and checked: OK', 26);
				TxEnd;
				END;
			END;
		END;
	IF all AND (res = 0) THEN
		OsDelay (1500)
	ELSE
		AnyKey;
	END;
BackupModule := res;
END;

{ 1-1 and 1-2: back up all modules, or one. }
PROCEDURE DoBackup (all: BOOLEAN);
VAR m, first, last, key, er, psize, r: INTEGER;
	ok: BOOLEAN;
BEGIN
Title;
NewLine (1);
IF all THEN
	BEGIN
	ConLineOut ('Back up all modules, one file each.', 35);
	NewLine (1);
	first := 0;
	last := nMbm - 1;
	ok := TRUE;
	END
ELSE
	BEGIN
	ConLineOut ('Back up one module into a file.', 31);
	NewLine (1);
	first := ChooseModule (FALSE);
	last := first;
	ok := first >= 0;
	IF ok THEN
		BEGIN
		Title;
		NewLine (1);
		ConLineOut ('Back up module', 14);
		PutNum (first + 1);
		NewLine (1);
		END;
	END;
IF ok THEN
	BEGIN
	ConLineOut ('This only reads the bubble.', 27);
	NewLine (1);
	NewLine (1);
	ConLineOut ('C  corrected, the way GRiD-OS reads it (64 bytes a', 50);
	NewLine (1);
	ConLineOut ('   page, ~Bin~). Best for a module that works.', 46);
	NewLine (1);
	ConLineOut ('R  raw, no error correction (68 bytes a page, ~Raw~).', 53);
	NewLine (1);
	ConLineOut ('   Keeps everything, even bits the correction would', 51);
	NewLine (1);
	ConLineOut ('   get wrong: best for a failing module.', 40);
	NewLine (1);
	ConLineOut ('Each file is about 131K (C) or 139K (R).', 40);
	REPEAT
		key := UpKey (GetKey);
	UNTIL IsCancel (key) OR (key = ORD ('C')) OR (key = ORD ('R'));
	ok := NOT IsCancel (key);
	IF key = ORD ('R') THEN
		BEGIN
		er := 0;
		psize := pageBytes;
		bkExt := 3;
		END
	ELSE
		BEGIN
		er := enGrid;
		psize := eccBytes;
		bkExt := 2;
		END;
	END;
IF ok THEN
	BEGIN
	Title;
	ok := ChooseDest (FALSE);
	END;
IF ok THEN
	BEGIN
	Title;
	ConLineOut ('Backups go to', 13);
	PutDest;
	NewLine (1);
	IF destRemovable THEN
		BEGIN
		ConLineOut ('A floppy holds two modules. When it is full you are', 51);
		NewLine (1);
		ConLineOut ('asked for another one.', 22);
		NewLine (1);
		END;
	SetBaseName;
	ok := AskName (2);
	IF ok THEN
		KeepBaseName;
	END;
IF ok THEN
	BEGIN
	swapped := FALSE;
	FOR m := 0 TO maxMbm - 1 DO
		bkRes[m] := -2;
	m := first;
	r := 0;
	WHILE (m <= last) AND (r < 2) DO
		BEGIN
		r := BackupModule (m, er, psize, all);
		m := m + 1;
		END;
	IF RunCmd (cmdResetFifo, 500) THEN;
	initN := EnsureInit;
	IF all OR swapped THEN
		BEGIN
		Title;
		NewLine (1);
		IF r < 2 THEN
			BEGIN
			ConLineOut ('Backup finished.', 16);
			NewLine (1);
			END
		ELSE
			BEGIN
			ConLineOut ('Backup stopped.', 15);
			NewLine (1);
			END;
		NewLine (1);
		FOR m := first TO last DO
			BEGIN
			ConLineOut ('Module', 6);
			PutNum (m + 1);
			ConCharOut (':');
			IF bkRes[m] >= 0 THEN
				BEGIN
				ConLineOut ('saved,', 6);
				PutNum (bkRes[m]);
				ConLineOut (' bad pages', 10);
				END
			ELSE IF bkRes[m] = -1 THEN
				BEGIN
				ConLineOut ('skipped', 7);
				END
			ELSE IF bkRes[m] = -3 THEN
				BEGIN
				ConLineOut ('saved, READ-BACK FAILED', 23);
				END
			ELSE IF bkRes[m] = -4 THEN
				BEGIN
				ConLineOut ('stopped part way', 16);
				END
			ELSE
				BEGIN
				ConLineOut ('not saved', 9);
				END;
			NewLine (1);
			END;
		IF swapped OR destRemovable THEN
			BEGIN
			NewLine (1);
			ConLineOut ('If you changed floppies: put the Bubble Fix floppy', 50);
			NewLine (1);
			ConLineOut ('back before you quit.', 21);
			NewLine (1);
			END;
		ConLineOut ('Write a report (menu 4) to keep a log.', 38);
		AnyKey;
		END;
	END;
END;

.

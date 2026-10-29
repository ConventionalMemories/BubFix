$COMPACT SS(32)
MODULE bfio;

{ GRiD Bubble Fix 2, by Conventional Memories (C.M._).
  Part of bubfix (see bubfix.pas): typing names and maps, map files, devices, file reading and writing. }

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

PRIVATE bfio;

{ ---------- typing ---------- }

{ Shows nameBuf on line y with the cursor at pos. }
PROCEDURE DrawName (y, pos: INTEGER);
VAR i: INTEGER;
BEGIN
ConMoveCsr (0, y);
FOR i := 0 TO nameLen - 1 DO
	ConCharOut (nameBuf[i]);
ConCharOut (' ');
ConMoveCsr (pos, y);
END;

{ Edits nameBuf (nameLen characters) on line y, with a cursor: the
  arrows move it, typing puts characters in at the cursor, Backspace
  takes away the one before it. Return accepts, Code-Esc cancels. }
FUNCTION EditName (y: INTEGER): BOOLEAN;
VAR key, i, pos: INTEGER;
	done, ok: BOOLEAN;
BEGIN
pos := nameLen;
ConDefCsr (TRUE);
DrawName (y, pos);
done := FALSE;
ok := FALSE;
REPEAT
	key := GetKey;
	IF (key = returnKey) OR (key = confirmKey) THEN
		BEGIN
		done := TRUE;
		ok := nameLen > 0;
		END
	ELSE IF IsCancel (key) THEN
		done := TRUE
	ELSE IF key = leftArrowKey THEN
		BEGIN
		IF pos > 0 THEN
			pos := pos - 1;
		END
	ELSE IF key = rightArrowKey THEN
		BEGIN
		IF pos < nameLen THEN
			pos := pos + 1;
		END
	ELSE IF (key = upArrowKey) OR (key = leftMarginKey) THEN
		pos := 0
	ELSE IF (key = downArrowKey) OR (key = rightMarginKey) THEN
		pos := nameLen
	ELSE IF (key = bsKey) AND (pos > 0) THEN
		BEGIN
		FOR i := pos TO nameLen - 1 DO
			nameBuf[i - 1] := nameBuf[i];
		nameLen := nameLen - 1;
		pos := pos - 1;
		END
	ELSE IF (key >= 32) AND (key < 127) AND (nameLen < 60) THEN
		BEGIN
		FOR i := nameLen - 1 DOWNTO pos DO
			nameBuf[i + 1] := nameBuf[i];
		nameBuf[pos] := CHR (key);
		nameLen := nameLen + 1;
		pos := pos + 1;
		END;
	DrawName (y, pos);
UNTIL done;
ConDefCsr (FALSE);
EditName := ok;
END;

{ Asks for a name only; the type is added by MakePath.
    kind 0 map file to load, 1 map file to save (last map name filled
    in), 2 name for a backup, 3 backup file to read (last backup name
    filled in), 4 report.
  A type typed in anyway (from ~ on) is dropped. }
FUNCTION AskName (kind: INTEGER): BOOLEAN;
VAR i, n: INTEGER;
	ok: BOOLEAN;
BEGIN
IF kind <= 1 THEN
	BEGIN
	nameLen := mapLen;
	FOR i := 0 TO mapLen - 1 DO
		nameBuf[i] := mapName[i];
	END;
NewLine (2);
IF kind = 0 THEN
	BEGIN
	ConLineOut ('Name of the map file to load:', 29);
	NewLine (1);
	END
ELSE IF kind = 1 THEN
	BEGIN
	ConLineOut ('Name for the map file:', 22);
	NewLine (1);
	END
ELSE IF kind = 2 THEN
	BEGIN
	ConLineOut ('Name for the backup (" Module 1" and the type are', 49);
	NewLine (1);
	ConLineOut ('added for each module):', 23);
	NewLine (1);
	END
ELSE IF kind = 3 THEN
	BEGIN
	ConLineOut ('Name of the backup file to read:', 32);
	NewLine (1);
	END
ELSE
	BEGIN
	ConLineOut ('Name for the report:', 20);
	NewLine (1);
	END;
ConLineOut ('(arrows move, Return accepts, Code-Esc cancels)', 47);
NewLine (1);
ok := EditName (row);
n := 0;
WHILE (n < nameLen) AND (nameBuf[n] <> '~') DO
	n := n + 1;
nameLen := n;
IF nameLen = 0 THEN
	ok := FALSE;
IF ok AND (kind <= 1) THEN
	BEGIN
	mapLen := nameLen;
	FOR i := 0 TO nameLen - 1 DO
		mapName[i] := nameBuf[i];
	END;
AskName := ok;
END;

{ Builds pathBuf: [`device`BubFix`] name [ Module m+1] type.
  dev: put the backup device (destDev) and the BubFix subject in front. m < 0: no module.
  ext: 0 none, 1 ~Bootloop~, 2 ~Bin~, 3 ~Raw~, 4 ~Text~. }
PROCEDURE MakePath (dev: BOOLEAN; m, ext: INTEGER);
VAR i, n: INTEGER;
BEGIN
n := 0;
{ a name typed with its own device in front keeps that one }
FOR i := 0 TO nameLen - 1 DO
	IF nameBuf[i] = '`' THEN
		dev := FALSE;
IF dev THEN
	BEGIN
	n := n + 1;
	pathBuf[n] := '`';
	FOR i := 0 TO destLen - 1 DO
		BEGIN
		n := n + 1;
		pathBuf[n] := destDev[i];
		END;
	n := n + 1;
	pathBuf[n] := '`';
	{ in the BubFix subject: GRiD-OS wants files in a subject, not at
	  the top of a device (OsAttach makes the subject when needed) }
	FOR i := 1 TO 6 DO
		pathBuf[n + i] := bakSubject[i];
	n := n + 7;
	pathBuf[n] := '`';
	END;
FOR i := 0 TO nameLen - 1 DO
	BEGIN
	n := n + 1;
	pathBuf[n] := nameBuf[i];
	END;
IF m >= 0 THEN
	BEGIN
	FOR i := 1 TO 8 DO
		pathBuf[n + i] := modWord[i];
	n := n + 9;
	pathBuf[n] := CHR (ORD ('1') + m);
	END;
IF ext = 1 THEN
	BEGIN
	FOR i := 1 TO 10 DO
		pathBuf[n + i] := extMap[i];
	n := n + 10;
	END
ELSE IF ext = 2 THEN
	BEGIN
	FOR i := 1 TO 5 DO
		pathBuf[n + i] := extBin[i];
	n := n + 5;
	END
ELSE IF ext = 3 THEN
	BEGIN
	FOR i := 1 TO 5 DO
		pathBuf[n + i] := extRaw[i];
	n := n + 5;
	END
ELSE IF ext = 4 THEN
	BEGIN
	FOR i := 1 TO 6 DO
		pathBuf[n + i] := extText[i];
	n := n + 6;
	END;
pathBuf[0] := CHR (n);
END;

PROCEDURE SetBaseName;
VAR i: INTEGER;
BEGIN
nameLen := baseLen;
FOR i := 0 TO baseLen - 1 DO
	nameBuf[i] := baseName[i];
END;

PROCEDURE KeepBaseName;
VAR i: INTEGER;
BEGIN
baseLen := nameLen;
FOR i := 0 TO nameLen - 1 DO
	baseName[i] := nameBuf[i];
END;

{ Shows a file error with what it usually means. }
PROCEDURE ShowFileError (e: WORD);
BEGIN
ConLineOut ('error', 5);
PutNum (ORD (e));
IF ORD (e) = 32 THEN
	BEGIN
	ConLineOut (' (exists already)', 17);
	END
ELSE IF ORD (e) = 33 THEN
	BEGIN
	ConLineOut (' (not found)', 12);
	END
ELSE IF ORD (e) = 41 THEN
	BEGIN
	ConLineOut (' (full)', 7);
	END
ELSE IF ORD (e) = 106 THEN
	BEGIN
	ConLineOut (' (write protected)', 18);
	END
ELSE IF ORD (e) = 107 THEN
	BEGIN
	ConLineOut (' (not ready)', 12);
	END
ELSE IF (ORD (e) = 227) OR (ORD (e) = 231) THEN
	BEGIN
	ConLineOut (' (no such device)', 17);
	END
ELSE IF (ORD (e) = 103) OR (ORD (e) = 105) THEN
	BEGIN
	ConLineOut (' (medium error)', 15);
	END;
END;

{ Takes the 80 hex digits from a module's label into newMap. Shown as
  5 lines of 16 digits, like the label, with a cursor: the arrows
  move it, a digit goes in where it is and moves it on, Backspace
  moves it back without wiping anything. When the map was typed for
  this module before in this run, it starts filled in, so a single
  digit can be fixed. TRUE when all 80 digits are there and Return
  is given. }
FUNCTION TypeMap (m: INTEGER): BOOLEAN;
VAR dg: ARRAY [0..79] OF INTEGER;
	n, pos, key, d, top, nSet: INTEGER;
	done, ok: BOOLEAN;
BEGIN
NewLine (1);
ConLineOut ('Type the 80 hex digits from the label. Arrows move,', 51);
NewLine (1);
ConLineOut ('Backspace goes back, Return accepts, Code-Esc', 45);
NewLine (1);
ConLineOut ('cancels.', 8);
NewLine (1);
top := row + 1;
FOR n := 0 TO 79 DO
	BEGIN
	IF typedFor = m THEN
		BEGIN
		IF (n MOD 2) = 0 THEN
			dg[n] := newMap[n DIV 2] DIV 16
		ELSE
			dg[n] := newMap[n DIV 2] MOD 16;
		END
	ELSE
		dg[n] := -1;
	ConMoveCsr (2 + n MOD 16, top + n DIV 16);
	IF dg[n] >= 0 THEN
		ConCharOut (HexChar (dg[n]))
	ELSE
		ConCharOut ('.');
	END;
row := top + 6;
pos := 0;
done := FALSE;
ok := FALSE;
ConDefCsr (TRUE);
REPEAT
	nSet := 0;
	FOR n := 0 TO 79 DO
		IF dg[n] >= 0 THEN
			nSet := nSet + 1;
	ConMoveCsr (0, top + 6);
	PutNum (nSet);
	ConLineOut (' of 80 digits typed', 19);
	ConMoveCsr (2 + pos MOD 16, top + pos DIV 16);
	key := UpKey (GetKey);
	d := DigitOf (key);
	IF (key >= ORD ('A')) AND (key <= ORD ('F')) THEN
		d := key - ORD ('A') + 10;
	IF IsCancel (key) THEN
		done := TRUE
	ELSE IF d >= 0 THEN
		BEGIN
		dg[pos] := d;
		ConCharOut (HexChar (d));
		IF pos < 79 THEN
			pos := pos + 1;
		END
	ELSE IF (key = leftArrowKey) OR (key = bsKey) THEN
		BEGIN
		IF pos > 0 THEN
			pos := pos - 1;
		END
	ELSE IF key = rightArrowKey THEN
		BEGIN
		IF pos < 79 THEN
			pos := pos + 1;
		END
	ELSE IF key = upArrowKey THEN
		BEGIN
		IF pos >= 16 THEN
			pos := pos - 16;
		END
	ELSE IF key = downArrowKey THEN
		BEGIN
		IF pos < 64 THEN
			pos := pos + 16;
		END
	ELSE IF (key = returnKey) OR (key = confirmKey) THEN
		BEGIN
		IF nSet = 80 THEN
			BEGIN
			done := TRUE;
			ok := TRUE;
			END
		ELSE
			BEGIN
			ConMoveCsr (0, top + 7);
			ConLineOut ('Not all 80 digits are typed yet.', 32);
			END;
		END;
UNTIL done;
ConDefCsr (FALSE);
IF ok THEN
	BEGIN
	FOR n := 0 TO mapBytes - 1 DO
		newMap[n] := 16 * dg[2 * n] + dg[2 * n + 1];
	typedFor := m;
	row := top + 8;
	ConMoveCsr (0, row);
	IF newMap[0] <> 255 THEN
		BEGIN
ConLineOut ('On real modules the first map byte reads FF, even', 49);
NewLine (1);
ConLineOut ('when the label shows something else. F uses FF', 46);
NewLine (1);
ConLineOut ('(recommended), K keeps the typed value.', 39);
		REPEAT
			key := UpKey (GetKey);
		UNTIL (key = ORD ('F')) OR (key = ORD ('K')) OR IsCancel (key);
		IF key = ORD ('F') THEN
			newMap[0] := 255
		ELSE IF IsCancel (key) THEN
			ok := FALSE;
		NewLine (1);
		END;
	END
ELSE
	BEGIN
	row := top + 8;
	ConMoveCsr (0, row);
	END;
TypeMap := ok;
END;

{ ---------- map files ---------- }

{ Writes maps/mapOk of all modules to the file in pathBuf. }
FUNCTION SaveFile: BOOLEAN;
VAR conn, error, pw: WORD;
	m, i, p: INTEGER;
BEGIN
FOR i := 0 TO 7 DO
	fbuf[i] := fileMagic[i + 1];
fbuf[8] := CHR (nMbm);
p := 9;
FOR m := 0 TO maxMbm - 1 DO
	BEGIN
	IF (m < nMbm) AND mapOk[m] THEN
		BEGIN
		fbuf[p] := CHR (1);
		FOR i := 0 TO mapBytes - 1 DO
			fbuf[p + 1 + i] := CHR (maps[m][i]);
		END
	ELSE
		FOR i := 0 TO mapBytes DO
			fbuf[p + i] := CHR (0);
	p := p + 1 + mapBytes;
	END;
pw := 0;
conn := OsAttach (pathBuf, newFileMode, pw, writeAccess, error);
IF error = okCode THEN
	BEGIN
	OsOpen (conn, 1, error);
	IF error = okCode THEN
		OsWrite (conn, fbuf, fileBytes, error);
	IF error = okCode THEN
		OsClose (conn, error)
	ELSE
		OsClose (conn, pw);
	pw := 0;
	OsDetach (conn, pw);
	END;
IF error <> okCode THEN
	BEGIN
	NewLine (2);
	ConLineOut ('Could not write the file,', 25);
	ShowFileError (error);
	END;
SaveFile := error = okCode;
END;

{ Reads the map of module m from the file in pathBuf into newMap. }
FUNCTION LoadFile (m: INTEGER): BOOLEAN;
VAR conn, error, pw, n: WORD;
	i, p: INTEGER;
	ok: BOOLEAN;
BEGIN
ok := FALSE;
n := 0;
pw := 0;
conn := OsAttach (pathBuf, oldFileMode, pw, readAccess, error);
IF error = okCode THEN
	BEGIN
	OsOpen (conn, 1, error);
	IF error = okCode THEN
		n := OsRead (conn, fbuf, fileBytes, error);
	OsClose (conn, pw);
	pw := 0;
	OsDetach (conn, pw);
	NewLine (2);
	IF n < fileBytes THEN
		BEGIN
		ConLineOut ('That is not a Bubble Fix map file.', 34);
		END
	ELSE
		BEGIN
		ok := TRUE;
		FOR i := 0 TO 7 DO
			IF fbuf[i] <> fileMagic[i + 1] THEN
				ok := FALSE;
		p := 9 + m * (1 + mapBytes);
		IF NOT ok THEN
			BEGIN
			ConLineOut ('That is not a Bubble Fix map file.', 34);
			END
		ELSE IF ORD (fbuf[p]) <> 1 THEN
			BEGIN
			ok := FALSE;
			ConLineOut ('The file has no map for module', 30);
			PutNum (m + 1);
			ConCharOut ('.');
			END
		ELSE
			BEGIN
			FOR i := 0 TO mapBytes - 1 DO
				newMap[i] := ORD (fbuf[p + 1 + i]);
			IF ORD (fbuf[8]) <> nMbm THEN
				BEGIN
				ConLineOut ('Note: the file is from a bubble with', 36);
				NewLine (1);
				PutNum (ORD (fbuf[8]));
				ConLineOut (' modules.', 9);
				END;
			END;
		END;
	END
ELSE
	BEGIN
	NewLine (2);
	ConLineOut ('Could not open the file,', 24);
	ShowFileError (error);
	END;
LoadFile := ok;
END;

{ ---------- devices ---------- }

{ Sets destDev: 1 Hard Disk, 2 Floppy Disk, 3 Portable Floppy, 4 the
  device Bubble Fix runs from. }
PROCEDURE SetDest (d: INTEGER);
VAR i: INTEGER;
BEGIN
IF d = 1 THEN
	BEGIN
	destLen := 9;
	FOR i := 1 TO 9 DO destDev[i - 1] := devHard[i];
	END
ELSE IF d = 2 THEN
	BEGIN
	destLen := 11;
	FOR i := 1 TO 11 DO destDev[i - 1] := devFloppy[i];
	END
ELSE IF d = 3 THEN
	BEGIN
	destLen := 15;
	FOR i := 1 TO 15 DO destDev[i - 1] := devPort[i];
	END
ELSE
	BEGIN
	destLen := ownLen;
	FOR i := 0 TO ownLen - 1 DO destDev[i] := ownDev[i];
	END;
{ a floppy can be changed for another one when it is full }
destRemovable := FALSE;
FOR i := 0 TO destLen - 6 DO
	IF (destDev[i] = 'F') AND (destDev[i + 1] = 'l') AND
	   (destDev[i + 2] = 'o') AND (destDev[i + 3] = 'p') THEN
		destRemovable := TRUE;
END;

{ Is destDev the bubble? Backups must never go there. }
FUNCTION DestIsBubble: BOOLEAN;
VAR i: INTEGER;
	same: BOOLEAN;
BEGIN
same := destLen = 13;
IF same THEN
	FOR i := 1 TO 13 DO
		IF destDev[i - 1] <> devBubble[i] THEN
			same := FALSE;
DestIsBubble := same;
END;

FUNCTION OwnIsBubble: BOOLEAN;
VAR i: INTEGER;
	same: BOOLEAN;
BEGIN
same := ownLen = 13;
IF same THEN
	FOR i := 1 TO 13 DO
		IF ownDev[i - 1] <> devBubble[i] THEN
			same := FALSE;
OwnIsBubble := same;
END;

{ The device of the prefix: `Floppy Disk`Bubble Fix gives Floppy Disk }
PROCEDURE FindOwnDevice;
VAR p: ShortStringPtr;
	j: INTEGER;
BEGIN
ownLen := 0;
p := OsGetPrefix;
IF p^.length > 1 THEN
	BEGIN
	j := 1;
	WHILE (j < p^.length) AND (p^.chars[j] <> '`') AND (ownLen < 80) DO
		BEGIN
		ownDev[ownLen] := p^.chars[j];
		ownLen := ownLen + 1;
		j := j + 1;
		END;
	END;
END;

PROCEDURE PutDest;
VAR i: INTEGER;
BEGIN
FOR i := 0 TO destLen - 1 DO
	ConCharOut (destDev[i]);
END;

PROCEDURE PutOwn;
VAR i: INTEGER;
BEGIN
FOR i := 0 TO ownLen - 1 DO
	ConCharOut (ownDev[i]);
END;

{ Is destDev there, with a readable medium in it? Only looks: asks
  for a file that does not exist; "not found" means the device
  answered. }
FUNCTION DestThere: BOOLEAN;
VAR i, n: INTEGER;
	conn, error, pw: WORD;
BEGIN
n := 0;
n := n + 1;
pathBuf[n] := '`';
FOR i := 0 TO destLen - 1 DO
	BEGIN
	n := n + 1;
	pathBuf[n] := destDev[i];
	END;
n := n + 1;
pathBuf[n] := '`';
FOR i := 1 TO 21 DO
	pathBuf[n + i] := probeName[i];
pathBuf[0] := CHR (n + 21);
pw := 0;
conn := OsAttach (pathBuf, oldFileMode, pw, readAccess, error);
IF error = okCode THEN
	BEGIN
	pw := 0;
	OsDetach (conn, pw);
	END;
DestThere := (ORD (error) = okCode) OR (ORD (error) = 33) OR
             (ORD (error) = 234);
END;

{ Lets the user pick where backups or a report go (or, reading,
  where a backup is). Shows which devices answer. FALSE for
  Code-Esc. }
FUNCTION ChooseDest (reading: BOOLEAN): BOOLEAN;
VAR d, key: INTEGER;
	there: ARRAY [1..4] OF BOOLEAN;
	ok: BOOLEAN;
BEGIN
NewLine (2);
IF reading THEN
	BEGIN
	ConLineOut ('Where is it? (looking at the devices)', 37);
	NewLine (1);
	END
ELSE
	BEGIN
	ConLineOut ('Where to? (looking at the devices...)', 37);
	NewLine (1);
	END;
FOR d := 1 TO 4 DO
	BEGIN
	SetDest (d);
	there[d] := (destLen > 0) AND NOT DestIsBubble AND DestThere;
	END;
FOR d := 1 TO 4 DO
	BEGIN
	PutNum (d);
	;
	IF d = 1 THEN
		BEGIN
		ConLineOut ('Hard Disk', 9);
		END
	ELSE IF d = 2 THEN
		BEGIN
		ConLineOut ('Floppy Disk', 11);
		END
	ELSE IF d = 3 THEN
		BEGIN
		ConLineOut ('Portable Floppy', 15);
		END
	ELSE
		BEGIN
		ConLineOut ('Where Bubble Fix runs:', 22);
		PutOwn;
		END;
	IF NOT there[d] THEN
		BEGIN
		ConLineOut (' (not there)', 12);
		END;
	NewLine (1);
	END;
IF NOT reading THEN
	BEGIN
	ConLineOut ('A floppy must have been through Initialize Media', 48);
	NewLine (1);
	ConLineOut ('before.', 7);
	NewLine (1);
	END;
REPEAT
	key := GetKey;
	d := DigitOf (key);
UNTIL IsCancel (key) OR ((d >= 1) AND (d <= 4));
ok := FALSE;
IF NOT IsCancel (key) THEN
	BEGIN
	SetDest (d);
	IF DestIsBubble OR (destLen = 0) THEN
		BEGIN
		NewLine (1);
		ConLineOut ('Not on the bubble: pick another.', 32);
		NewLine (1);
		AnyKey;
		END
	ELSE IF NOT there[d] THEN
		BEGIN
		NewLine (1);
		ConLineOut ('That device did not answer. Use it', 34);
		NewLine (1);
		ConLineOut ('anyway? Code-Return yes, Code-Esc no.', 37);
		ok := Confirmed;
		END
	ELSE
		ok := TRUE;
	END;
ChooseDest := ok;
END;

{ ---------- files written and read a byte at a time ---------- }

PROCEDURE FwFlush;
BEGIN
IF (fwN > 0) AND (fwErr = okCode) THEN
	OsWrite (fwConn, fwBuf, fwN, fwErr);
fwN := 0;
END;

PROCEDURE FwByte (b: INTEGER);
BEGIN
fwBuf[fwN] := CHR (b);
fwN := fwN + 1;
IF fwN >= 1024 THEN
	FwFlush;
END;

{ Closes the file being written; TRUE when all went well. }
FUNCTION FwClose: BOOLEAN;
VAR e: WORD;
BEGIN
FwFlush;
IF fwErr = okCode THEN
	OsClose (fwConn, fwErr)
ELSE
	OsClose (fwConn, e);
e := 0;
OsDetach (fwConn, e);
FwClose := fwErr = okCode;
END;

{ Deletes the file in pathBuf (when it is there). }
PROCEDURE DeleteFile;
VAR conn, error, e: WORD;
BEGIN
e := 0;
conn := OsAttach (pathBuf, oldFileMode, e, updateAccess, error);
IF error = okCode THEN
	BEGIN
	OsOpen (conn, 1, error);
	IF error = okCode THEN
		OsDelete (conn, error)
	ELSE
		BEGIN
		e := 0;
		OsDetach (conn, e);
		END;
	END;
END;

{ Makes the file in pathBuf for writing, when the volume has room for
  needK kilobytes. Result: 0 made (fwConn open), 1 no room (nothing
  left behind), 2 exists already, 3 other error (fwErr). freeK gives
  the room there was. }
FUNCTION FwCreate (needK: INTEGER; VAR freeK: INTEGER): INTEGER;
VAR st: VolStatus;
	e: WORD;
	res, freeP, bpp, needP: INTEGER;
BEGIN
fwN := 0;
freeK := 0;
e := 0;
fwConn := OsAttach (pathBuf, newFileMode, e, writeAccess, fwErr);
IF fwErr = okCode THEN
	BEGIN
	OsOpen (fwConn, 1, fwErr);
	IF fwErr <> okCode THEN
		BEGIN
		e := 0;
		OsDetach (fwConn, e);
		END;
	END;
IF ORD (fwErr) = 32 THEN
	res := 2
ELSE IF fwErr <> okCode THEN
	res := 3
ELSE
	BEGIN
	res := 0;
	OsGetStatus (fwConn, st, 17, e);
	IF e = okCode THEN
		BEGIN
		bpp := ORD (st.bytesPerPage);
		IF bpp < 64 THEN
			bpp := 504;
		freeP := ORD (st.numPages) - ORD (st.numAlloc);
		IF freeP < 0 THEN
			freeP := 0;
		{ pages the file takes: the data plus a few for its header
		  and page lists; counted a little high }
		needP := (needK * 64) DIV (bpp DIV 16) + 6;
		freeK := (freeP DIV 64) * (bpp DIV 16);
		IF freeP < needP THEN
			BEGIN
			res := 1;
			OsDelete (fwConn, e);
			END;
		END;
	END;
FwCreate := res;
END;

PROCEDURE FrOpen;
VAR e: WORD;
BEGIN
frN := 0;
frPos := 0;
frEnd := FALSE;
e := 0;
frConn := OsAttach (pathBuf, oldFileMode, e, readAccess, frErr);
IF frErr = okCode THEN
	BEGIN
	OsOpen (frConn, 1, frErr);
	IF frErr <> okCode THEN
		BEGIN
		e := 0;
		OsDetach (frConn, e);
		END;
	END;
END;

{ The next byte of the file being read, or -1 at its end. }
FUNCTION FrByte: INTEGER;
VAR got: WORD;
BEGIN
IF (frPos >= frN) AND NOT frEnd THEN
	BEGIN
	got := OsRead (frConn, frBuf, 1024, frErr);
	frN := ORD (got);
	frPos := 0;
	IF (frN = 0) OR (frErr <> okCode) THEN
		frEnd := TRUE;
	END;
IF frPos < frN THEN
	BEGIN
	FrByte := ORD (frBuf[frPos]);
	frPos := frPos + 1;
	END
ELSE
	FrByte := -1;
END;

PROCEDURE FrClose;
VAR e: WORD;
BEGIN
e := 0;
OsClose (frConn, e);
e := 0;
OsDetach (frConn, e);
END;

.

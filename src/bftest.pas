$COMPACT SS(32)
MODULE bftest;

{ GRiD Bubble Fix 2, by Conventional Memories (C.M._).
  Part of bubfix (see bubfix.pas): map rebuild (menu 2, 5) and tests and tools (menu 3). }

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

PRIVATE bftest;


{ ---------- rebuilding a lost map (menu 2-5, experimental) ---------- }

{ Byte i of test page j: a mix of ones and zeros in every loop. }
FUNCTION Pattern (i, j: INTEGER): INTEGER;
BEGIN
Pattern := (i * 37 + j * 91 + 90) MOD 256;
END;

{ Writes the test pages of module m raw, reads each back and gives
  the number of bits that came back wrong. The FSA must hold a map. }
FUNCTION RunTestPages (m: INTEGER): INTEGER;
VAR i, j, n, got: INTEGER;
BEGIN
n := 0;
FOR j := 0 TO testPages - 1 DO
	BEGIN
	FOR i := 0 TO pageBytes - 1 DO
		BubSetW (i, Pattern (i, j));
	IF WritePage (m, testBase + j, 0, pageBytes) THEN
		BEGIN
		got := ReadPage (m, testBase + j, 0, pageBytes);
		n := n + BubDiff (pageBytes);
		END
	ELSE
		n := n + 272;
	END;
RunTestPages := n;
END;

{ Loads exactly the loops of s (Write Bootloop Register, not masked)
  and tests them. -1 when the controller does not take the map. }
FUNCTION TestErr (m: INTEGER; VAR s: MapType): INTEGER;
VAR i: INTEGER;
	ok: BOOLEAN;
BEGIN
ok := ResetBmc;
IF ok THEN
	BEGIN
	BubParams (blrOne, 0, m * 2048);
	ok := RunCmd (cmdResetFifo, 500);
	END;
IF ok THEN
	BEGIN
	BubSelFifo;
	FOR i := 0 TO mapBytes - 1 DO
		BubFifoW (s[i]);
	ok := RunCmd (cmdWrBLR, 500);
	END;
IF ok THEN
	TestErr := RunTestPages (m)
ELSE
	TestErr := -1;
END;

{ Finds which loops of module m work. Starts from the first 136
  loops of each half (most loops are good). Swapping one of them for
  a loop outside shows how much worse or better that one is than the
  outside one; the median over all of them is what a good loop gives.
  A good loop found that way is then swapped for each outside loop. }
PROCEDURE RebuildMap;
VAR m, h, k, o, e0, e, med, g, i, j, tests, key: INTEGER;
	s0, t: MapType;
	ok, stop, moving: BOOLEAN;
BEGIN
Title;
NewLine (1);
ConLineOut ('Rebuild a lost map (EXPERIMENTAL)', 33);
NewLine (1);
NewLine (1);
ConLineOut ('For a module whose map is lost and has no label. It', 51);
NewLine (1);
ConLineOut ('tests every loop by writing patterns to pages', 45);
NewLine (1);
ConLineOut ('2040-2047 and reading them back. Data on those 8', 48);
NewLine (1);
ConLineOut ('pages is LOST: back up (raw) first. It takes several', 52);
NewLine (1);
ConLineOut ('minutes. The bootloop is only written if you ask at', 51);
NewLine (1);
ConLineOut ('the end.', 8);
NewLine (1);
m := ChooseModule (FALSE);
ok := m >= 0;
IF ok THEN
	BEGIN
	NewLine (2);
	ConLineOut ('Code-Return starts, Code-Esc cancels.', 37);
	ok := Confirmed;
	END;
IF ok THEN
	BEGIN
	Title;
	NewLine (1);
	ConLineOut ('Rebuilding the map of module', 28);
	PutNum (m + 1);
	NewLine (1);
	ConLineOut ('Code-Esc stops.', 15);
	initN := EnsureInit;
	FOR i := 0 TO mapBytes - 1 DO
		s0[i] := 0;
	FOR h := 0 TO 1 DO
		FOR k := 0 TO needLoops - 1 DO
			SetMapBit (s0, 2 * k + h, TRUE);
	e0 := TestErr (m, s0);
	IF e0 < 0 THEN
		BEGIN
		NewLine (2);
		ConLineOut ('The controller would not take a map', 35);
		ShowStat;
		ok := FALSE;
		END;
	tests := 1;
	stop := FALSE;
	h := 0;
	WHILE ok AND NOT stop AND (h <= 1) DO
		BEGIN
		{ each starting loop against the first outside loop }
		o := needLoops;
		k := 0;
		WHILE (k < needLoops) AND NOT stop DO
			BEGIN
			t := s0;
			SetMapBit (t, 2 * k + h, FALSE);
			SetMapBit (t, 2 * o + h, TRUE);
			e := TestErr (m, t);
			delta[k] := e - e0;
			k := k + 1;
			tests := tests + 1;
			IF (tests MOD 4) = 0 THEN
				BEGIN
				ConMoveCsr (0, row + 2);
				ConLineOut ('Test', 4);
				PutNum (tests);
				ConLineOut (' of 321, bad bits at start', 26);
				PutNum (e0);
				;
				stop := StopAsked;
				END;
			END;
		{ the median: what swapping out a good loop gives }
		FOR k := 0 TO needLoops - 1 DO
			BEGIN
			j := k;
			moving := TRUE;
			WHILE moving DO
				IF j = 0 THEN
					moving := FALSE
				ELSE IF sorted[j - 1] > delta[k] THEN
					BEGIN
					sorted[j] := sorted[j - 1];
					j := j - 1;
					END
				ELSE
					moving := FALSE;
			sorted[j] := delta[k];
			END;
		med := sorted[needLoops DIV 2];
		g := 0;
		FOR k := 0 TO needLoops - 1 DO
			BEGIN
			quality[2 * k + h] := med - delta[k];
			IF quality[2 * k + h] < quality[2 * g + h] THEN
				g := k;
			END;
		{ a good loop against every outside loop }
		o := needLoops;
		WHILE (o < 160) AND NOT stop DO
			BEGIN
			t := s0;
			SetMapBit (t, 2 * g + h, FALSE);
			SetMapBit (t, 2 * o + h, TRUE);
			e := TestErr (m, t);
			quality[2 * o + h] := e - e0;
			o := o + 1;
			tests := tests + 1;
			IF (tests MOD 4) = 0 THEN
				BEGIN
				ConMoveCsr (0, row + 2);
				ConLineOut ('Test', 4);
				PutNum (tests);
				stop := StopAsked;
				END;
			END;
		h := h + 1;
		END;
	IF stop THEN
		BEGIN
		NewLine (3);
		ConLineOut ('Stopped: no map made.', 21);
		ok := FALSE;
		END;
	IF ok THEN
		BEGIN
		{ good: at most 3 bits of 16 wrong }
		FOR i := 0 TO mapBytes - 1 DO
			newMap[i] := 0;
		FOR i := 0 TO 319 DO
			SetMapBit (newMap, i, quality[i] <= 3);
		e := -1;
		IF LoadMapFsa (m, 0, newMap) THEN
			e := RunTestPages (m);
		newFor := m;
		Title;
		NewLine (1);
		ConLineOut ('Rebuilt map of module', 21);
		PutNum (m + 1);
		ConCharOut (',');
		ShowCounts (newMap);
		ShowMap (newMap);
		NewLine (1);
		ConLineOut ('Bad bits with this map:', 23);
		PutNum (e);
		ConLineOut (' of 4352', 8);
		TxModule (m);
		TxPut ('map rebuilt,', 12);
		TxCounts (newMap);
		TxPut (', bad bits', 10);
		TxNum (e);
		TxEnd;
		TxMap (newMap);
		NewLine (2);
		IF NOT MapUsable (newMap) THEN
			BEGIN
			ConLineOut ('Too few good loops were found: the module may be', 48);
			NewLine (1);
			ConLineOut ('failing or its seeds lost (see Tests 2).', 40);
			NewLine (1);
			END
		ELSE IF e > 40 THEN
			BEGIN
			ConLineOut ('Still many bad bits: be careful.', 32);
			NewLine (1);
			END;
		ConLineOut ('S saves it to a map file, C checks it', 37);
		NewLine (1);
		ConLineOut ('by listing files (and can write it), Code-Esc goes', 50);
		NewLine (1);
		ConLineOut ('back.', 5);
		REPEAT
			key := UpKey (GetKey);
		UNTIL IsCancel (key) OR (key = ORD ('S')) OR (key = ORD ('C'));
		IF key = ORD ('S') THEN
			BEGIN
			FOR i := 0 TO maxMbm - 1 DO
				mapOk[i] := FALSE;
			maps[m] := newMap;
			mapOk[m] := TRUE;
			mapLen := 11;
			FOR i := 0 TO 10 DO
				mapName[i] := rebuiltName[i + 1];
			IF AskName (1) THEN
				BEGIN
				MakePath (FALSE, -1, 1);
				IF SaveFile THEN
					BEGIN
					NewLine (2);
					ConLineOut ('Saved.', 6);
					END;
				AnyKey;
				END;
			END
		ELSE IF key = ORD ('C') THEN
			TryMap (m);
		END
	ELSE
		AnyKey;
	initN := EnsureInit;
	END;
END;

{ ---------- menu 3: tests and tools ---------- }

{ 3-1 for one module. }
PROCEDURE ScanHealth (m: INTEGER; all: BOOLEAN);
VAR lvl, p, got, s, good, corr, failed, i: INTEGER;
	stop: BOOLEAN;
BEGIN
stop := FALSE;
Title;
ConLineOut ('Health scan of module', 21);
PutNum (m + 1);
NewLine (1);
ConLineOut ('Getting the module ready...', 27);
lvl := Prepare (m, enGrid, NOT all);
NewLine (1);
ShowLevel (lvl);
NewLine (1);
TxModule (m);
IF lvl = 0 THEN
	BEGIN
	ConLineOut ('Skipped: no usable map.', 23);
	TxPut ('health scan skipped, no usable map', 34);
	TxEnd;
	END
ELSE
	BEGIN
	ConLineOut ('Code-Esc stops.', 15);
	good := 0;
	corr := 0;
	failed := 0;
	p := 0;
	stop := FALSE;
	WHILE (p < modPages) AND NOT stop DO
		BEGIN
		got := ReadPage (m, p, enGrid, eccBytes);
		s := lastStat;
		IF PageGood (got, eccBytes, s) THEN
			BEGIN
			IF Bit (s, 3) THEN
				corr := corr + 1
			ELSE
				good := good + 1;
			END
		ELSE
			BEGIN
			IF failed < 8 THEN
				delta[failed] := p;
			failed := failed + 1;
			END;
		p := p + 1;
		IF (p MOD 32) = 0 THEN
			BEGIN
			ConMoveCsr (0, row + 1);
			ConLineOut ('Page', 4);
			PutNum (p);
			ConLineOut (', corrected', 11);
			PutNum (corr);
			ConLineOut (', failed', 8);
			PutNum (failed);
			;
			stop := StopAsked;
			END;
		END;
	row := row + 1;
	NewLine (2);
	ConLineOut ('Pages read:', 11);
	PutNum (p);
	NewLine (1);
	ConLineOut ('Good:', 5);
	PutNum (good);
	ConLineOut ('  corrected:', 12);
	PutNum (corr);
	ConLineOut ('  failed:', 9);
	PutNum (failed);
	IF failed > 0 THEN
		BEGIN
		NewLine (1);
		ConLineOut ('First failed pages:', 19);
		FOR i := 0 TO failed - 1 DO
			IF i < 8 THEN
				BEGIN
				ConCharOut (' ');
				PutNum (delta[i]);
				END;
		END;
	NewLine (2);
	IF stop THEN
		BEGIN
		ConLineOut ('Stopped before the end.', 23);
		END
	ELSE IF failed > 0 THEN
		BEGIN
		ConLineOut ('Pages fail: back it up (raw) now.', 33);
		NewLine (1);
		END
	ELSE IF corr > 0 THEN
		BEGIN
		ConLineOut ('Errors were corrected: the module may be wearing.', 49);
		NewLine (1);
		ConLineOut ('Keep a backup.', 14);
		NewLine (1);
		END
	ELSE
		BEGIN
		ConLineOut ('Every page read cleanly.', 24);
		NewLine (1);
		END;
	TxPut ('health scan:', 12);
	TxNum (p);
	TxPut (' pages,', 7);
	TxNum (good);
	TxPut (' good,', 6);
	TxNum (corr);
	TxPut (' corrected,', 11);
	TxNum (failed);
	TxPut (' failed,', 8);
	TxLevel (lvl);
	TxEnd;
	END;
AnyKey;
END;

PROCEDURE HealthScan;
VAR m, i: INTEGER;
BEGIN
Title;
NewLine (1);
ConLineOut ('Health scan: reads every page of a module the way', 49);
NewLine (1);
ConLineOut ('GRiD-OS does and counts good, corrected and failed', 50);
NewLine (1);
ConLineOut ('pages. Only reads. Takes about a minute a module.', 49);
NewLine (1);
m := ChooseModule (TRUE);
IF m = -2 THEN
	BEGIN
	FOR i := 0 TO nMbm - 1 DO
		ScanHealth (i, TRUE);
	initN := EnsureInit;
	Title;
	NewLine (1);
	ConLineOut ('Done. Write a report to keep it.', 32);
	AnyKey;
	END
ELSE IF m >= 0 THEN
	BEGIN
	ScanHealth (m, FALSE);
	initN := EnsureInit;
	END;
END;

{ 3-2 for one module: Intel's seed check (AP-150), but the page used
  is put back afterwards. }
PROCEDURE SeedOne (m: INTEGER; all: BOOLEAN);
VAR lvl, got, i, nff: INTEGER;
	kept, w1, back, ok: BOOLEAN;
BEGIN
Title;
ConLineOut ('Seed test of module', 19);
PutNum (m + 1);
NewLine (1);
ConLineOut ('Getting the module ready...', 27);
lvl := Prepare (m, 0, NOT all);
NewLine (1);
ShowLevel (lvl);
TxModule (m);
ok := lvl > 0;
IF NOT ok THEN
	BEGIN
	NewLine (1);
	ConLineOut ('Skipped: no usable map.', 23);
	TxPut ('seed test skipped, no usable map', 32);
	TxEnd;
	END;
IF ok THEN
	BEGIN
	{ keep page 2047 aside }
	got := ReadPage (m, seedPage, 0, pageBytes);
	kept := PageGood (got, pageBytes, lastStat);
	FOR i := 0 TO pageBytes - 1 DO
		orig[i] := BubRdByte (i);
	IF NOT kept THEN
		BEGIN
		NewLine (2);
		ConLineOut ('Page 2047 cannot be read, so it cannot be put back', 50);
		NewLine (1);
		ConLineOut ('afterwards. Code-Return tests anyway, Code-Esc skips.', 53);
		ok := Confirmed;
		IF NOT ok THEN
			BEGIN
			TxPut ('seed test skipped, page unreadable', 34);
			TxEnd;
			END;
		END;
	END;
IF ok THEN
	BEGIN
	FOR i := 0 TO pageBytes - 1 DO
		BubSetW (i, 255);
	w1 := WritePage (m, seedPage, 0, pageBytes);
	got := ReadPage (m, seedPage, 0, pageBytes);
	nff := 0;
	FOR i := 0 TO got - 1 DO
		IF BubRdByte (i) = 255 THEN
			nff := nff + 1;
	NewLine (2);
	ConLineOut ('FFH written', 11);
	IF NOT w1 THEN
		BEGIN
		ConLineOut (' (write failed)', 15);
		END;
	ConLineOut (', read back', 11);
	PutNum (nff);
	ConLineOut (' of 68.', 7);
	NewLine (1);
	FOR i := 0 TO 15 DO
		PutHex2 (BubRdByte (i));
	{ put the old page back }
	FOR i := 0 TO pageBytes - 1 DO
		BubSetW (i, orig[i]);
	back := FALSE;
	IF WritePage (m, seedPage, 0, pageBytes) THEN
		BEGIN
		got := ReadPage (m, seedPage, 0, pageBytes);
		back := PageGood (got, pageBytes, lastStat) AND (BubDiff (pageBytes) = 0);
		END;
	NewLine (2);
	IF nff = pageBytes THEN
		BEGIN
		ConLineOut ('All FFH: the seeds are there.', 29);
		NewLine (1);
		TxPut ('seed test: seeds OK', 19);
		END
	ELSE IF nff = 0 THEN
		BEGIN
		ConLineOut ('No FFH at all: the seeds look lost. Only Intel''s seed', 53);
		NewLine (1);
		ConLineOut ('module can fix that.', 20);
		NewLine (1);
		TxPut ('seed test: SEEDS LOST', 21);
		END
	ELSE
		BEGIN
		ConLineOut ('Unclear: only some bytes came back FFH.', 39);
		NewLine (1);
		TxPut ('seed test: unclear,', 19);
		TxNum (nff);
		TxPut (' of 68 FFH', 10);
		END;
	IF back THEN
		BEGIN
		ConLineOut ('Page 2047 put back: OK.', 23);
		TxPut (', page put back', 15);
		TxEnd;
		END
	ELSE IF kept THEN
		BEGIN
		ConLineOut ('Page 2047 could NOT be put back.', 32);
		TxPut (', page NOT put back', 19);
		TxEnd;
		END
	ELSE
		BEGIN
		ConLineOut ('Page 2047 was unreadable before.', 32);
		TxPut (', page was unreadable', 21);
		TxEnd;
		END;
	END;
AnyKey;
END;

PROCEDURE SeedTest;
VAR m, i: INTEGER;
BEGIN
Title;
NewLine (1);
ConLineOut ('Seed test: can the module still store data? It', 46);
NewLine (1);
ConLineOut ('borrows page 2047: keeps what is there, writes FFH,', 51);
NewLine (1);
ConLineOut ('reads it back, then writes the old contents back. If', 52);
NewLine (1);
ConLineOut ('the seeds are lost the old page cannot be put back', 50);
NewLine (1);
ConLineOut ('(the module cannot store anything then).', 40);
NewLine (1);
m := ChooseModule (TRUE);
IF m <> -1 THEN
	BEGIN
	NewLine (2);
	ConLineOut ('Code-Return tests, Code-Esc cancels.', 36);
	IF Confirmed THEN
		BEGIN
		IF m = -2 THEN
			FOR i := 0 TO nMbm - 1 DO
				SeedOne (i, TRUE)
		ELSE
			SeedOne (m, FALSE);
		END;
	initN := EnsureInit;
	END;
END;

{ A number typed on line y (Return accepts); -1 for Code-Esc. }
FUNCTION AskNumber (y, max: INTEGER): INTEGER;
VAR key, n, d, len: INTEGER;
	done: BOOLEAN;
BEGIN
n := 0;
len := 0;
done := FALSE;
ConDefCsr (TRUE);
REPEAT
	ConMoveCsr (0, y);
	IF len > 0 THEN
		PutNum (n);
	;
	ConMoveCsr (len, y);
	key := GetKey;
	d := DigitOf (key);
	IF IsCancel (key) THEN
		BEGIN
		n := -1;
		done := TRUE;
		END
	ELSE IF (key = returnKey) OR (key = confirmKey) THEN
		done := len > 0
	ELSE IF (key = bsKey) AND (len > 0) THEN
		BEGIN
		n := n DIV 10;
		len := len - 1;
		END
	ELSE IF (d >= 0) AND (len < 4) THEN
		IF n * 10 + d <= max THEN
			BEGIN
			n := n * 10 + d;
			len := len + 1;
			END;
UNTIL done;
ConDefCsr (FALSE);
AskNumber := n;
END;

{ 3-3: shows one page at a time in hex and as text. }
PROCEDURE PageViewer;
VAR m, p, n, er, got, i, j, b, key, lvl: INTEGER;
	raw, done: BOOLEAN;
BEGIN
Title;
NewLine (1);
ConLineOut ('Page viewer: shows a page of a module in hex and as', 51);
NewLine (1);
ConLineOut ('text. Only reads.', 17);
NewLine (1);
m := ChooseModule (FALSE);
IF m >= 0 THEN
	BEGIN
	raw := FALSE;
	er := enGrid;
	NewLine (2);
	ConLineOut ('Getting the module ready...', 27);
	lvl := Prepare (m, er, TRUE);
	done := lvl = 0;
	IF done THEN
		BEGIN
		NewLine (1);
		ConLineOut ('No usable map: nothing to show.', 31);
		AnyKey;
		END;
	p := 0;
	WHILE NOT done DO
		BEGIN
		IF raw THEN
			n := pageBytes
		ELSE
			n := eccBytes;
		got := ReadPage (m, p, er, n);
		Title;
		ConLineOut ('Module', 6);
		PutNum (m + 1);
		ConLineOut (' page', 5);
		PutNum (p);
		IF raw THEN
			BEGIN
			ConLineOut (' raw', 4);
			END
		ELSE
			BEGIN
			ConLineOut (' corrected', 10);
			END;
		ShowStat;
		NewLine (1);
		IF lvl <> 1 THEN
			BEGIN
			ConLineOut ('(page 0 not known: may be shifted)', 34);
			END
		ELSE
			BEGIN
			ConLineOut ('block', 5);
			PutNum ((m * 2048 + p) DIV 4);
			ConLineOut (', part', 6);
			PutNum (p MOD 4 + 1);
			ConLineOut (' of 4', 5);
			END;
		NewLine (1);
		FOR i := 0 TO (n - 1) DIV 8 DO
			BEGIN
			NewLine (1);
			PutHex2 (i * 8);
			ConCharOut (' ');
			FOR j := 0 TO 7 DO
				IF i * 8 + j < n THEN
					BEGIN
					PutHex2 (BubRdByte (i * 8 + j));
					ConCharOut (' ');
					END;
			ConMoveCsr (28, row);
			FOR j := 0 TO 7 DO
				IF i * 8 + j < n THEN
					BEGIN
					b := BubRdByte (i * 8 + j);
					IF (b >= 32) AND (b < 127) THEN
						ConCharOut (CHR (b))
					ELSE
						ConCharOut ('.');
					END;
			END;
		IF got < n THEN
			BEGIN
			NewLine (1);
			ConLineOut ('Only', 4);
			PutNum (got);
			ConLineOut (' bytes came.', 12);
			END;
		NewLine (2);
		ConLineOut ('Left/Right: page -1/+1, Up/Down: -4/+4', 38);
		NewLine (1);
		ConLineOut ('G goes to a page, R raw/corrected,', 34);
		NewLine (1);
		ConLineOut ('Code-Esc goes back.', 19);
		key := UpKey (GetKey);
		IF IsCancel (key) THEN
			done := TRUE
		ELSE IF (key = rightArrowKey) OR (key = ORD ('N')) THEN
			p := (p + 1) MOD modPages
		ELSE IF (key = leftArrowKey) OR (key = ORD ('P')) THEN
			p := (p + modPages - 1) MOD modPages
		ELSE IF key = downArrowKey THEN
			p := (p + 4) MOD modPages
		ELSE IF key = upArrowKey THEN
			p := (p + modPages - 4) MOD modPages
		ELSE IF key = ORD ('G') THEN
			BEGIN
			NewLine (2);
			ConLineOut ('Page (0-2047), Return:', 22);
			i := AskNumber (row + 1, modPages - 1);
			IF i >= 0 THEN
				p := i;
			END
		ELSE IF key = ORD ('R') THEN
			BEGIN
			raw := NOT raw;
			IF raw THEN
				er := 0
			ELSE
				er := enGrid;
			lvl := Prepare (m, er, FALSE);
			IF lvl = 0 THEN
				done := TRUE;
			END;
		END;
	initN := EnsureInit;
	END;
END;

{ 3-4: the files on a module, found from their header blocks. }
PROCEDURE ListModule;
VAR m, lvl, good, nRead, off: INTEGER;
BEGIN
Title;
NewLine (1);
ConLineOut ('List the files on a module, found from their header', 51);
NewLine (1);
ConLineOut ('blocks, even when GRiD-OS cannot start the bubble.', 50);
NewLine (1);
ConLineOut ('Only reads.', 11);
NewLine (1);
m := ChooseModule (FALSE);
IF m >= 0 THEN
	BEGIN
	NewLine (2);
	ConLineOut ('Getting the module ready...', 27);
	lvl := Prepare (m, enGrid, TRUE);
	NewLine (1);
	ShowLevel (lvl);
	IF lvl = 0 THEN
		AnyKey
	ELSE
		BEGIN
		good := ScanModule (m, nRead);
		ScanResult (m, good, nRead);
		AnyKey;
		IF lvl = 1 THEN
			off := 0
		ELSE
			off := BestOff;
		ShowDir (m, off);
		END;
	initN := EnsureInit;
	END;
END;

{ 3-5: Initialize, the way GRiD-OS does it at start-up. }
PROCEDURE TestInit;
BEGIN
Title;
NewLine (1);
ConLineOut ('Initialize of the bubble...', 27);
TxPut ('Initialize of all modules:', 26);
IF InitAll THEN
	BEGIN
	ConLineOut (' OK', 3);
	ShowStat;
	TxPut (' OK', 3);
	END
ELSE
	BEGIN
	ConLineOut (' failed', 7);
	ShowStat;
	NewLine (1);
	ConLineOut ('Menu 2, 1 shows which map is bad.', 33);
	TxPut (' FAILED', 7);
	END;
TxStat;
TxEnd;
AnyKey;
END;

.

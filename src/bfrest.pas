$COMPACT SS(32)
MODULE bfrest;

{ GRiD Bubble Fix 2, by Conventional Memories (C.M._).
  Part of bubfix (see bubfix.pas): verify, restore and list a backup (menu 1, 3 to 5). }

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

PRIVATE bfrest;

{ 1-3: compare a backup with its module, page by page. Only reads. }
PROCEDURE Verify;
VAR m, er, lvl, off, p, q, got, same, differ, unread, skipped: INTEGER;
	stop: BOOLEAN;
BEGIN
Title;
NewLine (1);
ConLineOut ('Compare a backup with the bubble. This only reads.', 50);
NewLine (1);
ConLineOut ('Use it right after a backup to be sure the copy is', 50);
NewLine (1);
ConLineOut ('good.', 5);
NewLine (1);
IF AskBackup THEN
	BEGIN
	m := bkModule;
	IF bkPsize = pageBytes THEN
		er := 0
	ELSE
		er := enGrid;
	NewLine (2);
	ConLineOut ('Getting the module ready...', 27);
	lvl := Prepare (m, er, FALSE);
	NewLine (1);
	ShowLevel (lvl);
	IF lvl = 0 THEN
		BEGIN
		NewLine (1);
		ConLineOut ('Restore the module''s map first.', 31);
		AnyKey;
		END
	ELSE IF OpenBackup THEN
		BEGIN
		IF (lvl <> 1) OR ((bkSynced <> 1) AND (bkOff < 0)) THEN
			BEGIN
			NewLine (1);
			ConLineOut ('Page 0 is not known on one side: the pages may not', 50);
			NewLine (1);
			ConLineOut ('line up and differ.', 19);
			NewLine (1);
			END;
		off := 0;
		IF (bkSynced <> 1) AND (bkOff > 0) THEN
			off := bkOff;
		NewLine (1);
		ConLineOut ('Code-Esc stops.', 15);
		same := 0;
		differ := 0;
		unread := 0;
		skipped := 0;
		p := 0;
		stop := FALSE;
		WHILE (p < modPages) AND NOT stop DO
			BEGIN
			IF NOT FrPage THEN
				stop := TRUE
			ELSE IF NOT StatGood (ORD (pstat[p])) THEN
				skipped := skipped + 1
			ELSE
				BEGIN
				FOR q := 0 TO bkPsize - 1 DO
					BubSetW (q, pgBuf[q]);
				q := (p + off) MOD modPages;
				got := ReadPage (m, q, er, bkPsize);
				IF NOT PageGood (got, bkPsize, lastStat) THEN
					unread := unread + 1
				ELSE IF BubDiff (bkPsize) = 0 THEN
					same := same + 1
				ELSE
					differ := differ + 1;
				END;
			p := p + 1;
			IF (p MOD 32) = 0 THEN
				BEGIN
				ConMoveCsr (0, row + 1);
				ConLineOut ('Page', 4);
				PutNum (p);
				ConLineOut (', same', 6);
				PutNum (same);
				ConLineOut (', differ', 8);
				PutNum (differ);
				;
				IF StopAsked THEN
					stop := TRUE;
				END;
			END;
		FrClose;
		row := row + 1;
		NewLine (2);
		ConLineOut ('Same:', 5);
		PutNum (same);
		ConLineOut ('  different:', 12);
		PutNum (differ);
		NewLine (1);
		ConLineOut ('Unreadable on the bubble:', 25);
		PutNum (unread);
		NewLine (1);
		ConLineOut ('Bad or missing in the backup:', 29);
		PutNum (skipped);
		NewLine (2);
		IF (differ = 0) AND (unread = 0) AND (same > 0) THEN
			BEGIN
			ConLineOut ('The backup matches the bubble.', 30);
			END
		ELSE
			BEGIN
			ConLineOut ('They differ: see above.', 23);
			END;
		TxModule (m);
		TxPut ('verify:', 7);
		TxNum (same);
		TxPut (' same,', 6);
		TxNum (differ);
		TxPut (' different,', 11);
		TxNum (unread);
		TxPut (' unreadable,', 12);
		TxNum (skipped);
		TxPut (' not in backup', 14);
		TxEnd;
		AnyKey;
		END
	ELSE
		AnyKey;
	END;
END;

{ 1-4: write a backup back onto its module. }
PROCEDURE RestoreBackup;
VAR m, er, lvl, off, p, q, i, key, done, failed, skipped: INTEGER;
	wrF, rdF, dfF, firstP, firstS: INTEGER;
	ok, stop: BOOLEAN;
BEGIN
Title;
NewLine (1);
ConLineOut ('Restore a backup: writes it back onto the module it', 51);
NewLine (1);
ConLineOut ('came from.', 10);
NewLine (1);
NewLine (1);
ConLineOut ('WARNING: everything now on that module is replaced.', 51);
NewLine (1);
ConLineOut ('Only for a module that initializes (restore its map', 51);
NewLine (1);
ConLineOut ('first, menu 2). Back the module up first if anything', 52);
NewLine (1);
ConLineOut ('on it may still be needed.', 26);
NewLine (1);
ok := AskBackup;
IF ok THEN
	BEGIN
	m := bkModule;
	IF bkPsize = pageBytes THEN
		er := 0
	ELSE
		er := enGrid;
	NewLine (1);
	IF NOT bkTailOk THEN
		BEGIN
		ConLineOut ('The file is damaged: it will not be written back.', 49);
		ok := FALSE;
		AnyKey;
		END
	ELSE IF bkUnread + bkBad >= modPages THEN
		BEGIN
		ConLineOut ('The backup holds no good pages.', 31);
		ok := FALSE;
		AnyKey;
		END;
	END;
IF ok THEN
	BEGIN
	ConLineOut ('Getting the module ready...', 27);
	lvl := Prepare (m, er, FALSE);
	IF lvl <> 1 THEN
		BEGIN
		NewLine (1);
		ConLineOut ('Module', 6);
		PutNum (m + 1);
		ConLineOut (' does not initialize. Restore its map first', 43);
		NewLine (1);
		ConLineOut ('(menu 2, 3), then try again.', 28);
		ok := FALSE;
		AnyKey;
		END
	ELSE
		BEGIN
		ConLineOut (' OK', 3);
		END;
	END;
IF ok THEN
	BEGIN
	off := 0;
	IF bkSynced <> 1 THEN
		BEGIN
		NewLine (1);
		IF bkOff >= 0 THEN
			BEGIN
			off := bkOff;
			ConLineOut ('Pages are moved back by the shift', 33);
			NewLine (1);
			ConLineOut ('found from the file headers:', 28);
			PutNum (off);
			END
		ELSE
			BEGIN
			ConLineOut ('Page 0 of this backup is not known, and no file', 47);
			NewLine (1);
			ConLineOut ('headers were found: the pages may land shifted.', 47);
			END;
		END;
	NewLine (2);
	ConLineOut ('This replaces ALL data on module', 32);
	PutNum (m + 1);
	ConCharOut ('.');
	NewLine (1);
	PutNum (modPages - bkUnread - bkBad);
	ConLineOut (' pages are written, bad ones are left.', 38);
	NewLine (2);
	ConLineOut ('Code-Return goes on, Code-Esc cancels.', 38);
	ok := Confirmed;
	END;
IF ok THEN
	BEGIN
	NewLine (2);
	ConLineOut ('To be sure, type the module number (', 36);
	PutNum (m + 1);
	ConLineOut (').', 2);
	key := GetKey;
	ok := key = ORD ('1') + m;
	IF NOT ok THEN
		BEGIN
		NewLine (1);
		ConLineOut ('Not the same: nothing written.', 30);
		AnyKey;
		END;
	END;
IF ok THEN
	ok := OpenBackup;
IF ok THEN
	BEGIN
	Title;
	NewLine (1);
	ConLineOut ('Restoring module', 16);
	PutNum (m + 1);
	ConLineOut ('...', 3);
	NewLine (1);
	ConLineOut ('Code-Esc stops (leaves it half done).', 37);
	lvl := Prepare (m, er, FALSE);
	done := 0;
	failed := 0;
	skipped := 0;
	wrF := 0;
	rdF := 0;
	dfF := 0;
	firstP := -1;
	firstS := 0;
	p := 0;
	stop := lvl <> 1;
	WHILE (p < modPages) AND NOT stop DO
		BEGIN
		IF NOT FrPage THEN
			stop := TRUE
		ELSE IF NOT StatGood (ORD (pstat[p])) THEN
			skipped := skipped + 1
		ELSE
			BEGIN
			FOR i := 0 TO bkPsize - 1 DO
				BubSetW (i, pgBuf[i]);
			q := (p + off) MOD modPages;
			IF WritePage (m, q, er, bkPsize) THEN
				BEGIN
				i := ReadPage (m, q, er, bkPsize);
				IF NOT PageGood (i, bkPsize, lastStat) THEN
					rdF := rdF + 1
				ELSE IF BubDiff (bkPsize) <> 0 THEN
					dfF := dfF + 1
				ELSE
					done := done + 1;
				END
			ELSE
				wrF := wrF + 1;
			IF (firstP < 0) AND (wrF + rdF + dfF > 0) THEN
				BEGIN
				firstP := q;
				firstS := lastStat;
				END;
			failed := wrF + rdF + dfF;
			END;
		p := p + 1;
		IF (p MOD 32) = 0 THEN
			BEGIN
			ConMoveCsr (0, row + 1);
			ConLineOut ('Page', 4);
			PutNum (p);
			ConLineOut (', written', 9);
			PutNum (done);
			ConLineOut (', failed', 8);
			PutNum (failed);
			;
			IF StopAsked THEN
				stop := TRUE;
			END;
		END;
	FrClose;
	row := row + 1;
	NewLine (2);
	ConLineOut ('Written and checked:', 20);
	PutNum (done);
	NewLine (1);
	ConLineOut ('Failed:', 7);
	PutNum (failed);
	ConLineOut (', left (bad in backup):', 23);
	PutNum (skipped);
	IF failed > 0 THEN
		BEGIN
		NewLine (1);
		ConLineOut ('Write errors:', 13);
		PutNum (wrF);
		ConLineOut (', read-back errors:', 19);
		PutNum (rdF);
		ConLineOut (', read back different:', 22);
		PutNum (dfF);
		NewLine (1);
		ConLineOut ('First failed page:', 18);
		PutNum (firstP);
		ConLineOut (', status', 8);
		PutHex2 (firstS);
		ConCharOut ('H');
		END;
	TxModule (m);
	TxPut ('restored from', 13);
	TxPath;
	TxChar (ORD (':'));
	TxNum (done);
	TxPut (' written,', 9);
	TxNum (failed);
	TxPut (' failed,', 8);
	TxNum (skipped);
	TxPut (' left', 5);
	TxEnd;
	IF failed > 0 THEN
		BEGIN
		TxPut ('  write errors', 14);
		TxNum (wrF);
		TxPut (', read-back errors', 18);
		TxNum (rdF);
		TxPut (', different', 11);
		TxNum (dfF);
		TxPut (', first page', 12);
		TxNum (firstP);
		TxPut (' status', 7);
		TxHex2 (firstS);
		TxChar (ORD ('H'));
		TxEnd;
		END;
	NewLine (1);
	ConLineOut ('Initialize of the bubble...', 27);
	IF InitAll THEN
		BEGIN
		ConLineOut (' OK', 3);
		END
	ELSE
		BEGIN
		ConLineOut (' failed', 7);
		ShowStat;
		END;
	NewLine (2);
	IF p < modPages THEN
		BEGIN
		ConLineOut ('Stopped before the end: run it again.', 37);
		NewLine (1);
		END;
	IF failed > 0 THEN
		BEGIN
		ConLineOut ('Some pages would not take: the module may be failing', 52);
		NewLine (1);
		ConLineOut ('(see Tests 1 and 2).', 20);
		NewLine (1);
		END;
	ConLineOut ('Restart the GRiD and look at the files.', 39);
	NewLine (1);
	AnyKey;
	END;
END;

{ 1-5: the files in a backup, found from their header blocks. }
PROCEDURE ListBackup;
VAR off: INTEGER;
BEGIN
Title;
NewLine (1);
ConLineOut ('List the files in a backup, found from their header', 51);
NewLine (1);
ConLineOut ('blocks. Only reads the file.', 28);
NewLine (1);
IF AskBackup THEN
	BEGIN
	off := bkOff;
	IF bkSynced = 1 THEN
		off := 0;
	NewLine (1);
	ConLineOut ('File headers found:', 19);
	PutNum (dirHeaders);
	AnyKey;
	ShowDir (bkModule, off);
	END;
END;

.

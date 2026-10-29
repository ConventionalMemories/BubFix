$COMPACT SS(32)
MODULE bfhelp;

{ GRiD Bubble Fix 2, by Conventional Memories (C.M._).
  Part of bubfix (see bubfix.pas): the report (menu 4) and the help pages. }

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

PRIVATE bfhelp;

{ ---------- menu 4: the report ---------- }

PROCEDURE Report;
VAR mark, i, m, freeK, res: INTEGER;
	ok: BOOLEAN;
BEGIN
Title;
NewLine (1);
ConLineOut ('Write a report: a text file with the maps, what', 47);
NewLine (1);
ConLineOut ('Initialize says and a log of everything done since', 50);
NewLine (1);
ConLineOut ('Bubble Fix started. Keep it with the backups, or', 48);
NewLine (1);
ConLineOut ('share it when asking for help.', 30);
NewLine (1);
ok := ChooseDest (FALSE);
IF ok THEN
	BEGIN
	Title;
	nameLen := 13;
	FOR i := 0 TO 12 DO
		nameBuf[i] := defaultReport[i + 1];
	ok := AskName (4);
	END;
IF ok THEN
	BEGIN
	NewLine (2);
	ConLineOut ('Reading the maps...', 19);
	{ room for the report part after the log }
	IF TxLen > 4500 THEN
		BEGIN
		TxCut (4500);
		TxPut ('(log cut short here)', 20);
		TxEnd;
		END;
	mark := TxLen;
	TxPut ('GRiD Bubble Fix 2.0.0 report', 28);
	TxEnd;
	TxPut ('by Conventional Memories (C.M._)', 32);
	TxEnd;
	TxEnd;
	TxPut ('Bubble modules:', 15);
	TxNum (nMbm);
	IF byHand THEN
		BEGIN
		TxPut (' (set by hand)', 14);
		END;
	TxEnd;
	TxPut ('FSA status:', 11);
	FOR i := 0 TO fsaN - 1 DO
		BEGIN
		TxChar (32);
		TxHex2 (fsaRaw[i]);
		END;
	TxEnd;
	TxPut ('Running from:', 13);
	TxChar (32);
	FOR i := 0 TO ownLen - 1 DO
		TxChar (ORD (ownDev[i]));
	TxEnd;
	TxEnd;
	initN := EnsureInit;
	FOR m := 0 TO nMbm - 1 DO
		BEGIN
		TxModule (m);
		IF ReadBootloop (m, curMap) THEN
			BEGIN
			TxCounts (curMap);
			IF NOT MapUsable (curMap) THEN
				BEGIN
				TxPut (' (DAMAGED)', 10);
				END;
			TxEnd;
			TxMap (curMap);
			END
		ELSE
			BEGIN
			TxPut ('map unreadable', 14);
			TxStat;
			TxEnd;
			END;
		END;
	TxPut ('Initialize of all modules:', 26);
	IF InitAll THEN
		BEGIN
		TxPut (' OK', 3);
		END
	ELSE
		BEGIN
		TxPut (' FAILED', 7);
		END;
	TxStat;
	TxEnd;
	TxEnd;
	TxPut ('Log of this session:', 20);
	TxEnd;
	MakePath (TRUE, -1, 4);
	res := 2;
	WHILE res = 2 DO
		BEGIN
		res := FwCreate (TxLen DIV 1024 + 2, freeK);
		IF res = 2 THEN
			BEGIN
			NewLine (2);
			ConLineOut ('The report exists already. Code-Return replaces it,', 51);
			NewLine (1);
			ConLineOut ('Code-Esc cancels.', 17);
			IF Confirmed THEN
				DeleteFile
			ELSE
				res := 4;
			END;
		END;
	NewLine (2);
	IF res = 0 THEN
		BEGIN
		FOR i := mark TO TxLen - 1 DO
			FwByte (TxByte (i));
		FOR i := 0 TO mark - 1 DO
			FwByte (TxByte (i));
		IF FwClose THEN
			BEGIN
			ConLineOut ('Report written:', 15);
			NewLine (1);
			PutPath;
			END
		ELSE
			BEGIN
			ConLineOut ('Writing the report failed,', 26);
			ShowFileError (fwErr);
			END;
		END
	ELSE IF res = 1 THEN
		BEGIN
		ConLineOut ('Not enough room there.', 22);
		END
	ELSE IF res = 3 THEN
		BEGIN
		ConLineOut ('Could not make the file,', 24);
		ShowFileError (fwErr);
		END;
	TxCut (mark);
	AnyKey;
	END;
END;

{ ---------- help ---------- }

PROCEDURE HelpPage (n: INTEGER);
BEGIN
Title;
IF n = 1 THEN
	BEGIN
	ConLineOut ('Help 1 of 9: about', 18);
	NewLine (1);
	NewLine (1);
	ConLineOut ('Version 2.0.0, by Conventional Memories (C.M._).', 48);
	NewLine (1);
	ConLineOut ('Free to share. Use at your own risk.', 36);
	NewLine (1);
	NewLine (1);
	ConLineOut ('Bubble Fix backs up the bubble memory of a GRiD', 47);
	NewLine (1);
	ConLineOut ('Compass and looks after the maps of its bubble', 46);
	NewLine (1);
	ConLineOut ('modules. It can rescue a bubble that bootloops or', 49);
	NewLine (1);
	ConLineOut ('that Initialize Media cannot format.', 36);
	NewLine (1);
	NewLine (1);
	ConLineOut ('Start the GRiD from a floppy or the hard disk, not', 50);
	NewLine (1);
	ConLineOut ('from the bubble: Bubble Fix talks to the bubble', 47);
	NewLine (1);
	ConLineOut ('controller directly and nothing else may use it.', 48);
	NewLine (1);
	NewLine (1);
	ConLineOut ('Code-Return confirms, Code-Esc goes back. Code-? or H', 53);
	NewLine (1);
	ConLineOut ('shows help.', 11);
	NewLine (1);
	END
ELSE IF n = 2 THEN
	BEGIN
	ConLineOut ('Help 2 of 9: bubble basics', 26);
	NewLine (1);
	NewLine (1);
	ConLineOut ('Each module holds 128K in 2048 pages. It has 320', 48);
	NewLine (1);
	ConLineOut ('storage loops; a few are bad from the factory. The', 50);
	NewLine (1);
	ConLineOut ('list of good loops (the map, 40 bytes) is kept in the', 53);
	NewLine (1);
	ConLineOut ('module''s bootloop and printed as 80 hex digits on its', 53);
	NewLine (1);
	ConLineOut ('label.', 6);
	NewLine (1);
	NewLine (1);
	ConLineOut ('At start-up the controller reads every module''s map.', 52);
	NewLine (1);
	ConLineOut ('If one is damaged, the bubble will not start (it', 48);
	NewLine (1);
	ConLineOut ('bootloops) and Initialize Media cannot format it. The', 53);
	NewLine (1);
	ConLineOut ('data may still be there: with the right map it can', 50);
	NewLine (1);
	ConLineOut ('often be read again.', 20);
	NewLine (1);
	NewLine (1);
	ConLineOut ('GRiD-OS sees the modules as one device:', 39);
	NewLine (1);
	ConLineOut ('module 1 is the first 128K, and so on.', 38);
	NewLine (1);
	END
ELSE IF n = 3 THEN
	BEGIN
	ConLineOut ('Help 3 of 9: backup and restore (1)', 35);
	NewLine (1);
	NewLine (1);
	ConLineOut ('1 Back up all modules: one file each, named', 43);
	NewLine (1);
	ConLineOut ('  "<name> Module N".', 20);
	NewLine (1);
	ConLineOut ('2 Back up one module. If its map is damaged, give the', 53);
	NewLine (1);
	ConLineOut ('  map from a map file or the label.', 35);
	NewLine (1);
	ConLineOut ('3 Verify: compares a backup with the bubble, page by', 52);
	NewLine (1);
	ConLineOut ('  page. Only reads.', 19);
	NewLine (1);
	ConLineOut ('4 Restore: writes a backup back onto its module,', 48);
	NewLine (1);
	ConLineOut ('  replacing all on it.', 22);
	NewLine (1);
	ConLineOut ('5 List the files inside a backup.', 33);
	NewLine (1);
	NewLine (1);
	ConLineOut ('C copies read like GRiD-OS (~Bin~).', 35);
	NewLine (1);
	ConLineOut ('R copies are raw, with the check bytes', 38);
	NewLine (1);
	ConLineOut ('(~Raw~): best for a failing module. Make both of a', 50);
	NewLine (1);
	ConLineOut ('module that matters.', 20);
	NewLine (1);
	END
ELSE IF n = 4 THEN
	BEGIN
	ConLineOut ('Help 4 of 9: where backups go', 29);
	NewLine (1);
	NewLine (1);
	ConLineOut ('Pick the hard disk or a floppy, never the bubble. A', 51);
	NewLine (1);
	ConLineOut ('floppy must have been through Initialize Media first.', 53);
	NewLine (1);
	ConLineOut ('Bubble Fix checks the room before each file, and', 48);
	NewLine (1);
	ConLineOut ('reads every file back afterwards to be sure the disk', 52);
	NewLine (1);
	ConLineOut ('holds it. Files go in the subject BubFix there.', 47);
	NewLine (1);
	NewLine (1);
	ConLineOut ('A floppy holds two modules. When it is full you are', 51);
	NewLine (1);
	ConLineOut ('asked for another one; on the hard disk you are not.', 52);
	NewLine (1);
	ConLineOut ('The Bubble Fix floppy may come out once the menu', 48);
	NewLine (1);
	ConLineOut ('shows: put it back before you quit.', 35);
	NewLine (1);
	NewLine (1);
	ConLineOut ('Code-Esc stops a backup; what was read is kept and', 50);
	NewLine (1);
	ConLineOut ('the rest left empty.', 20);
	NewLine (1);
	END
ELSE IF n = 5 THEN
	BEGIN
	ConLineOut ('Help 5 of 9: restoring a backup', 31);
	NewLine (1);
	NewLine (1);
	ConLineOut ('A restore needs a module that starts (initializes).', 51);
	NewLine (1);
	ConLineOut ('If its map is damaged, restore the map first', 44);
	NewLine (1);
	ConLineOut ('(menu 2, 3).', 12);
	NewLine (1);
	NewLine (1);
	ConLineOut ('When the module could not start at the backup, its', 50);
	NewLine (1);
	ConLineOut ('page 0 was not known. The shift is then found from', 50);
	NewLine (1);
	ConLineOut ('the file headers in the backup and the pages go back', 52);
	NewLine (1);
	ConLineOut ('where they belong. With no headers found they may', 49);
	NewLine (1);
	ConLineOut ('land shifted.', 13);
	NewLine (1);
	NewLine (1);
	ConLineOut ('Pages that were bad in the backup are left alone.', 49);
	NewLine (1);
	ConLineOut ('Each page written is read back and checked. Restart', 51);
	NewLine (1);
	ConLineOut ('the GRiD afterwards and look at the files.', 42);
	NewLine (1);
	END
ELSE IF n = 6 THEN
	BEGIN
	ConLineOut ('Help 6 of 9: bubble maps', 24);
	NewLine (1);
	NewLine (1);
	ConLineOut ('1 Shows each module''s map: compare it with the label', 52);
	NewLine (1);
	ConLineOut ('  on the module.', 16);
	NewLine (1);
	ConLineOut ('2 Saves the readable maps to a map file (~Bootloop~).', 53);
	NewLine (1);
	ConLineOut ('  Do this first, on every working GRiD, and keep it', 51);
	NewLine (1);
	ConLineOut ('  safe.', 7);
	NewLine (1);
	ConLineOut ('3 Restores a map from a map file or the label''s 80', 50);
	NewLine (1);
	ConLineOut ('  digits: it is written into the bootloop and read', 50);
	NewLine (1);
	ConLineOut ('  back.', 7);
	NewLine (1);
	ConLineOut ('4 Checks a map without writing it: it is loaded and', 51);
	NewLine (1);
	ConLineOut ('  the files it makes readable are counted. Use it', 49);
	NewLine (1);
	ConLineOut ('  before 3 when you are not sure of a map.', 42);
	NewLine (1);
	ConLineOut ('5 Rebuilds a lost map (experimental).', 37);
	NewLine (1);
	NewLine (1);
	ConLineOut ('Typing a map: arrows move, Backspace goes back,', 47);
	NewLine (1);
	ConLineOut ('digits are typed over.', 22);
	NewLine (1);
	END
ELSE IF n = 7 THEN
	BEGIN
	ConLineOut ('Help 7 of 9: rebuilding a map', 29);
	NewLine (1);
	NewLine (1);
	ConLineOut ('EXPERIMENTAL. For a module whose map is lost and that', 53);
	NewLine (1);
	ConLineOut ('has no label. It tests each loop: writes patterns to', 52);
	NewLine (1);
	ConLineOut ('pages 2040-2047, reads them back and counts bad bits.', 53);
	NewLine (1);
	ConLineOut ('Loops that keep their bits are good.', 36);
	NewLine (1);
	NewLine (1);
	ConLineOut ('It takes several minutes. The data on those 8 pages', 51);
	NewLine (1);
	ConLineOut ('is lost, so back up (raw) first. The bootloop is only', 53);
	NewLine (1);
	ConLineOut ('written if you choose so at the end.', 36);
	NewLine (1);
	NewLine (1);
	ConLineOut ('It cannot help when the seeds are lost. The result', 50);
	NewLine (1);
	ConLineOut ('may differ from the factory map; compare with the', 49);
	NewLine (1);
	ConLineOut ('label if you can.', 17);
	NewLine (1);
	END
ELSE IF n = 8 THEN
	BEGIN
	ConLineOut ('Help 8 of 9: tests, tools, report', 33);
	NewLine (1);
	NewLine (1);
	ConLineOut ('1 Health scan: counts good, corrected and failed', 48);
	NewLine (1);
	ConLineOut ('  pages. Many corrected pages: the module is wearing', 52);
	NewLine (1);
	ConLineOut ('  out.', 6);
	NewLine (1);
	ConLineOut ('2 Seed test: can the module still store data? Borrows', 53);
	NewLine (1);
	ConLineOut ('  page 2047 and puts it back. All 00H read back: the', 52);
	NewLine (1);
	ConLineOut ('  seeds are lost; only Intel''s seed module', 42);
	NewLine (1);
	ConLineOut ('  (BPK 72 kit) can fix that.', 28);
	NewLine (1);
	ConLineOut ('3 Page viewer: a page in hex and text.', 38);
	NewLine (1);
	ConLineOut ('4 Lists the files on a module, even one GRiD-OS', 47);
	NewLine (1);
	ConLineOut ('  cannot start.', 15);
	NewLine (1);
	ConLineOut ('5 Initialize, as GRiD-OS does at start.', 39);
	NewLine (1);
	NewLine (1);
	ConLineOut ('Menu 4 writes a report: the maps, the results and a', 51);
	NewLine (1);
	ConLineOut ('log of the session.', 19);
	NewLine (1);
	END
ELSE
	BEGIN
	ConLineOut ('Help 9 of 9: safety', 19);
	NewLine (1);
	NewLine (1);
	ConLineOut ('- Back up before anything that writes.', 38);
	NewLine (1);
	ConLineOut ('- Only these write to the bubble, each after', 44);
	NewLine (1);
	ConLineOut ('  Code-Return: restore a backup, restore or rebuild a', 53);
	NewLine (1);
	ConLineOut ('  map, seed test.', 17);
	NewLine (1);
	ConLineOut ('- Losing the right map can make a module useless.', 49);
	NewLine (1);
	ConLineOut ('  Save the maps and photograph the labels before you', 52);
	NewLine (1);
	ConLineOut ('  start.', 8);
	NewLine (1);
	ConLineOut ('- A wrong map can be put right by writing the right', 51);
	NewLine (1);
	ConLineOut ('  one, if you have it.', 22);
	NewLine (1);
	ConLineOut ('- Never switch off or reset during a write. Keep', 48);
	NewLine (1);
	ConLineOut ('  magnets away.', 15);
	NewLine (1);
	ConLineOut ('- A label''s first byte often differs from the map:', 50);
	NewLine (1);
	ConLineOut ('  the bootloop reads FF there. Bubble Fix offers FF', 51);
	NewLine (1);
	ConLineOut ('  when you type a label in.', 27);
	NewLine (1);
	END;
NewLine (1);
ConLineOut ('Any key: next, P: back, Code-Esc: done', 38);
END;

PROCEDURE Help (first: INTEGER);
VAR n, key: INTEGER;
BEGIN
n := first;
REPEAT
	HelpPage (n);
	key := UpKey (GetKey);
	IF key = ORD ('P') THEN
		BEGIN
		IF n > 1 THEN
			n := n - 1;
		END
	ELSE IF NOT IsCancel (key) THEN
		n := n + 1;
UNTIL IsCancel (key) OR (n > 9);
END;

FUNCTION IsHelp (key: INTEGER): BOOLEAN;
BEGIN
IsHelp := (key = helpKey) OR (UpKey (key) = ORD ('H'));
END;

.

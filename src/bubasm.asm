; bubasm.asm - direct access to the Intel 7220-1 bubble memory controller
; for GRiD Bubble Fix (bubfix.pas), by Conventional Memories (C.M._). 8086 only.
;
; The 7220 sits at memory address 0DFE80H (data/FIFO) and 0DFE82H
; (command and status), the same addresses the GRiD-OS bubble driver
; (bigbubbles.plm) uses.
;
; Writing a byte to the command port:
;   bit 4 = 1   start command (low four bits = command number)
;   bit 4 = 0   select the register the data port talks to (RAC):
;               0 = FIFO, 0AH = utility, 0BH/0CH = block length,
;               0DH = enable, 0EH/0FH = address. Every data port
;               access moves RAC on by one, except on the FIFO.
; Reading the command port gives the status register.
;
; Port access lives here, plus the page transfers that must keep up
; with the controller (Pascal is too slow for them), the two 128-byte
; page buffers (RDBUF, WRBUF, kept in the code segment), a bit compare
; and a check sum. All timing and the order of commands are in
; bubfix.pas. Nothing here enables bubble interrupts.
;
; Called from Pascal-86 (compact model): near calls, parameters pushed
; left to right, the procedure removes them, results come back in AX.

		NAME	BUBASM


CGROUP		GROUP	CODE

CODE		SEGMENT	PUBLIC 'CODE'
		ASSUME	CS:CGROUP, DS:NOTHING, ES:NOTHING

		PUBLIC	BUBPUT, BUBGET, BUBCMD, BUBSTAT, BUBSELFIFO
		PUBLIC	BUBFIFOW, BUBFIFOR, BUBPARAMS
		PUBLIC	BUBWRFILL, BUBRDDATA, BUBRDBYTE
		PUBLIC	BUBWRDATA, BUBSETW, BUBGETW, BUBDIFF
		PUBLIC	BUBCKRESET, BUBCKADD, BUBCKPAGE, BUBCKGET
		PUBLIC	TXRESET, TXPUT, TXCHAR, TXLEN, TXBYTE, TXCUT

BUBSEG		EQU	0DFE8H		; segment of the 7220
DATAP		EQU	0		; data / FIFO port
CMDP		EQU	2		; command (write) / status (read) port

; ---------- BubPut (reg, val) ----------
; Writes val into register reg (0AH..0FH).
BUBPUT		PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		MOV	AX, BUBSEG
		MOV	ES, AX
		XOR	BX, BX
		MOV	AL, BYTE PTR [BP+6]
		AND	AL, 0FH
		MOV	ES:BYTE PTR [BX+CMDP], AL
		MOV	AL, BYTE PTR [BP+4]
		MOV	ES:BYTE PTR [BX+DATAP], AL
		POP	BP
		RET	4
BUBPUT		ENDP

; ---------- BubGet (reg): INTEGER ----------
; Reads register reg (0AH, 0EH, 0FH can be read back).
BUBGET		PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		MOV	AX, BUBSEG
		MOV	ES, AX
		XOR	BX, BX
		MOV	AL, BYTE PTR [BP+4]
		AND	AL, 0FH
		MOV	ES:BYTE PTR [BX+CMDP], AL
		MOV	AL, ES:BYTE PTR [BX+DATAP]
		XOR	AH, AH
		POP	BP
		RET	2
BUBGET		ENDP

; ---------- BubCmd (cmd) ----------
; Starts 7220 command cmd (0..15).
BUBCMD		PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		MOV	AX, BUBSEG
		MOV	ES, AX
		XOR	BX, BX
		MOV	AL, BYTE PTR [BP+4]
		AND	AL, 0FH
		OR	AL, 10H
		MOV	ES:BYTE PTR [BX+CMDP], AL
		POP	BP
		RET	2
BUBCMD		ENDP

; ---------- BubStat: INTEGER ----------
; The status register: 80H busy, 40H done, 20H failed, 10H timing
; error, 08H corrected error, 04H uncorrectable error, 02H parity
; error, 01H FIFO ready.
BUBSTAT		PROC	NEAR
		MOV	AX, BUBSEG
		MOV	ES, AX
		XOR	BX, BX
		MOV	AL, ES:BYTE PTR [BX+CMDP]
		XOR	AH, AH
		RET
BUBSTAT		ENDP

; ---------- BubSelFifo ----------
; Points the data port at the FIFO.
BUBSELFIFO	PROC	NEAR
		MOV	AX, BUBSEG
		MOV	ES, AX
		XOR	BX, BX
		MOV	ES:BYTE PTR [BX+CMDP], 0
		RET
BUBSELFIFO	ENDP

; ---------- BubFifoW (val) ----------
; Puts one byte into the FIFO (call BubSelFifo first).
BUBFIFOW	PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		MOV	AX, BUBSEG
		MOV	ES, AX
		XOR	BX, BX
		MOV	AL, BYTE PTR [BP+4]
		MOV	ES:BYTE PTR [BX+DATAP], AL
		POP	BP
		RET	2
BUBFIFOW	ENDP

; ---------- BubFifoR: INTEGER ----------
; Takes one byte from the FIFO (call BubSelFifo first).
BUBFIFOR	PROC	NEAR
		MOV	AX, BUBSEG
		MOV	ES, AX
		XOR	BX, BX
		MOV	AL, ES:BYTE PTR [BX+DATAP]
		XOR	AH, AH
		RET
BUBFIFOR	ENDP

; ---------- BubParams (blr, er, ar) ----------
; Loads the parametric registers in one go, like SetParametrics in
; the GRiD-OS driver: block length (LSB, MSB), enable, address (LSB,
; MSB). Leaves the data port pointed at the FIFO.
BUBPARAMS	PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		MOV	AX, BUBSEG
		MOV	ES, AX
		XOR	BX, BX
		MOV	ES:BYTE PTR [BX+CMDP], 0BH
		MOV	AX, [BP+8]		; block length
		MOV	ES:BYTE PTR [BX+DATAP], AL
		MOV	ES:BYTE PTR [BX+DATAP], AH
		MOV	AL, BYTE PTR [BP+6]	; enable
		MOV	ES:BYTE PTR [BX+DATAP], AL
		MOV	AX, [BP+4]		; address
		MOV	ES:BYTE PTR [BX+DATAP], AL
		MOV	ES:BYTE PTR [BX+DATAP], AH
		MOV	ES:BYTE PTR [BX+CMDP], 0
		POP	BP
		RET	6
BUBPARAMS	ENDP

; ---------- BubWrFill (cmd, val, n): INTEGER ----------
; A normal Write of n bytes, every byte val (the seed test writes a
; page of FFH). Gives the command, waits for busy and FIFO ready, then
; puts each byte in as soon as the FIFO has room, the way AP-119's
; BMWRIT does: a normal Write must not be preloaded, and Pascal is
; too slow to keep up with the controller (one byte about every 80 us).
; Stops early if the controller stops being busy or after about a
; second and a half without progress.
; Result: the number of bytes written.
BUBWRFILL	PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		PUSH	SI
		PUSH	DI
		MOV	AX, BUBSEG
		MOV	ES, AX
		XOR	BX, BX
		MOV	AL, BYTE PTR [BP+8]	; command
		AND	AL, 0FH
		OR	AL, 10H
		MOV	ES:BYTE PTR [BX+CMDP], AL
		MOV	DI, [BP+4]		; bytes to write
		XOR	SI, SI			; bytes written
		MOV	DX, 16
WfStart:	MOV	CX, 0FFFFH
WfStLoop:	MOV	AL, ES:BYTE PTR [BX+CMDP]
		AND	AL, 81H
		CMP	AL, 81H			; busy and FIFO ready?
		JE	WfNext
		LOOP	WfStLoop
		DEC	DX
		JNZ	WfStart
		JMP	WfDone
WfNext:		CMP	SI, DI
		JAE	WfDone
		MOV	DX, 16
WfOuter:	MOV	CX, 0FFFFH
WfLoop:		MOV	AL, ES:BYTE PTR [BX+CMDP]
		TEST	AL, 80H			; still busy?
		JZ	WfDone
		TEST	AL, 01H			; room in the FIFO?
		JNZ	WfPut
		LOOP	WfLoop
		DEC	DX
		JNZ	WfOuter
		JMP	WfDone
WfPut:		MOV	AL, BYTE PTR [BP+6]
		MOV	ES:BYTE PTR [BX+DATAP], AL
		INC	SI
		JMP	WfNext
WfDone:		MOV	AX, SI
		POP	DI
		POP	SI
		POP	BP
		RET	6
BUBWRFILL	ENDP

; ---------- BubRdData (cmd, n): INTEGER ----------
; A normal Read of up to n bytes (at most 128) into RDBUF. Gives the
; command and takes each byte out of the FIFO as soon as it arrives:
; the FIFO holds only 40 bytes, so a 68-byte page has to be emptied
; while the command runs. Keeps going while the controller is busy or
; the FIFO still has data, or until about a second and a half passes
; without progress.
; Result: the number of bytes read. BubRdByte (i) gives byte i.
BUBRDDATA	PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		PUSH	SI
		PUSH	DI
		MOV	AX, BUBSEG
		MOV	ES, AX
		XOR	BX, BX
		MOV	AL, BYTE PTR [BP+6]	; command
		AND	AL, 0FH
		OR	AL, 10H
		MOV	ES:BYTE PTR [BX+CMDP], AL
		MOV	DI, [BP+4]		; bytes wanted
		CMP	DI, 128
		JBE	RdNOk
		MOV	DI, 128
RdNOk:		XOR	SI, SI			; bytes read
		MOV	AH, 0			; 1 once busy has been seen
RdNext:		CMP	SI, DI
		JAE	RdDone
		MOV	DX, 16
RdOuter:	MOV	CX, 0FFFFH
RdLoop:		MOV	AL, ES:BYTE PTR [BX+CMDP]
		TEST	AL, 01H			; data in the FIFO?
		JNZ	RdTake
		TEST	AL, 80H			; busy?
		JZ	RdIdle
		MOV	AH, 1
		JMP	RdCount
RdIdle:		CMP	AH, 0			; finished (after it started)?
		JNE	RdDone
RdCount:	LOOP	RdLoop
		DEC	DX
		JNZ	RdOuter
		JMP	RdDone
RdTake:		MOV	AL, ES:BYTE PTR [BX+DATAP]
		MOV	CS:BYTE PTR RDBUF[SI], AL
		INC	SI
		JMP	RdNext
RdDone:		MOV	AX, SI
		POP	DI
		POP	SI
		POP	BP
		RET	4
BUBRDDATA	ENDP

; ---------- BubRdByte (i): INTEGER ----------
; Byte i of what BubRdData read.
BUBRDBYTE	PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		MOV	BX, [BP+4]
		AND	BX, 7FH
		MOV	AL, CS:BYTE PTR RDBUF[BX]
		XOR	AH, AH
		POP	BP
		RET	2
BUBRDBYTE	ENDP

; ---------- BubWrData (cmd, n): INTEGER ----------
; A normal Write of n bytes (at most 128) taken from WRBUF (filled
; with BubSetW). Works like BubWrFill: waits for busy and FIFO ready,
; then gives each byte as soon as the FIFO has room.
; Result: the number of bytes written.
BUBWRDATA	PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		PUSH	SI
		PUSH	DI
		MOV	AX, BUBSEG
		MOV	ES, AX
		XOR	BX, BX
		MOV	AL, BYTE PTR [BP+6]	; command
		AND	AL, 0FH
		OR	AL, 10H
		MOV	ES:BYTE PTR [BX+CMDP], AL
		MOV	DI, [BP+4]		; bytes to write
		CMP	DI, 128
		JBE	WdNOk
		MOV	DI, 128
WdNOk:		XOR	SI, SI			; bytes written
		MOV	DX, 16
WdStart:	MOV	CX, 0FFFFH
WdStLoop:	MOV	AL, ES:BYTE PTR [BX+CMDP]
		AND	AL, 81H
		CMP	AL, 81H			; busy and FIFO ready?
		JE	WdNext
		LOOP	WdStLoop
		DEC	DX
		JNZ	WdStart
		JMP	WdDone
WdNext:		CMP	SI, DI
		JAE	WdDone
		MOV	DX, 16
WdOuter:	MOV	CX, 0FFFFH
WdLoop:		MOV	AL, ES:BYTE PTR [BX+CMDP]
		TEST	AL, 80H			; still busy?
		JZ	WdDone
		TEST	AL, 01H			; room in the FIFO?
		JNZ	WdPut
		LOOP	WdLoop
		DEC	DX
		JNZ	WdOuter
		JMP	WdDone
WdPut:		MOV	AL, CS:BYTE PTR WRBUF[SI]
		MOV	ES:BYTE PTR [BX+DATAP], AL
		INC	SI
		JMP	WdNext
WdDone:		MOV	AX, SI
		POP	DI
		POP	SI
		POP	BP
		RET	4
BUBWRDATA	ENDP

; ---------- BubSetW (i, val) ----------
; WRBUF[i] := val (i 0..127).
BUBSETW		PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		MOV	BX, [BP+6]
		AND	BX, 7FH
		MOV	AL, BYTE PTR [BP+4]
		MOV	CS:BYTE PTR WRBUF[BX], AL
		POP	BP
		RET	4
BUBSETW		ENDP

; ---------- BubGetW (i): INTEGER ----------
; WRBUF[i].
BUBGETW		PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		MOV	BX, [BP+4]
		AND	BX, 7FH
		MOV	AL, CS:BYTE PTR WRBUF[BX]
		XOR	AH, AH
		POP	BP
		RET	2
BUBGETW		ENDP

; ---------- BubDiff (n): INTEGER ----------
; The number of bits that differ between RDBUF and WRBUF in the first
; n bytes (at most 128): how many bits came back wrong.
BUBDIFF		PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		PUSH	SI
		MOV	CX, [BP+4]
		CMP	CX, 128
		JBE	DfNOk
		MOV	CX, 128
DfNOk:		XOR	SI, SI
		XOR	DX, DX			; bits counted
		JCXZ	DfDone
DfByte:		MOV	AL, CS:BYTE PTR RDBUF[SI]
		XOR	AL, CS:BYTE PTR WRBUF[SI]
		MOV	AH, 8
DfBit:		SHR	AL, 1
		ADC	DX, 0
		DEC	AH
		JNZ	DfBit
		INC	SI
		LOOP	DfByte
DfDone:		MOV	AX, DX
		POP	SI
		POP	BP
		RET	2
BUBDIFF		ENDP

; ---------- check sums ----------
; A Fletcher-style check sum over a stream of bytes: CKS1 is the sum
; of the bytes, CKS2 the sum of the CKS1 values, both kept to 16 bits.
; BubCkReset starts it, BubCkAdd (val) adds one byte, BubCkPage (n)
; adds the first n bytes of RDBUF, BubCkGet (k) gives byte k of the
; result (0 = CKS1 low, 1 = CKS1 high, 2 = CKS2 low, 3 = CKS2 high).
BUBCKRESET	PROC	NEAR
		MOV	CS:WORD PTR CKS1, 0
		MOV	CS:WORD PTR CKS2, 0
		RET
BUBCKRESET	ENDP

BUBCKADD	PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		MOV	AL, BYTE PTR [BP+4]
		XOR	AH, AH
		ADD	CS:WORD PTR CKS1, AX
		MOV	AX, CS:WORD PTR CKS1
		ADD	CS:WORD PTR CKS2, AX
		POP	BP
		RET	2
BUBCKADD	ENDP

BUBCKPAGE	PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		PUSH	SI
		MOV	CX, [BP+4]
		CMP	CX, 128
		JBE	CpNOk
		MOV	CX, 128
CpNOk:		XOR	SI, SI
		MOV	BX, CS:WORD PTR CKS1
		MOV	DX, CS:WORD PTR CKS2
		JCXZ	CpDone
CpByte:		MOV	AL, CS:BYTE PTR RDBUF[SI]
		XOR	AH, AH
		ADD	BX, AX
		ADD	DX, BX
		INC	SI
		LOOP	CpByte
CpDone:		MOV	CS:WORD PTR CKS1, BX
		MOV	CS:WORD PTR CKS2, DX
		POP	SI
		POP	BP
		RET	2
BUBCKPAGE	ENDP

BUBCKGET	PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		MOV	BX, [BP+4]
		AND	BX, 3
		MOV	AX, CS:WORD PTR CKS1
		CMP	BX, 2
		JB	CgSum
		MOV	AX, CS:WORD PTR CKS2
CgSum:		TEST	BX, 1
		JZ	CgLow
		MOV	AL, AH
CgLow:		XOR	AH, AH
		POP	BP
		RET	2
BUBCKGET	ENDP

; ---------- text buffer ----------
; Holds the session log and the report text (Pascal cannot pass a
; string literal to its own procedures, only to external ones like
; these). TxReset empties it, TxPut (s, n) adds n characters, TxChar
; (c) adds one, TxLen gives the length, TxByte (i) character i, TxCut
; (n) shortens it to n. Text that does not fit is dropped.
TXMAX		EQU	6000

TXRESET		PROC	NEAR
		MOV	CS:WORD PTR TXLN, 0
		RET
TXRESET		ENDP

TXPUT		PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		PUSH	SI
		PUSH	DI
		PUSH	DS
		PUSH	ES
		MOV	CX, [BP+4]
		MOV	AX, TXMAX
		SUB	AX, CS:WORD PTR TXLN
		CMP	CX, AX
		JLE	TpFit
		MOV	CX, AX
TpFit:		CMP	CX, 0
		JLE	TpEnd
		MOV	BX, CS:WORD PTR TXLN
		ADD	CS:WORD PTR TXLN, CX
		MOV	SI, [BP+6]
		MOV	DS, [BP+8]
		CLD
TpLoop:		LODSB
		MOV	CS:BYTE PTR TXBUF[BX], AL
		INC	BX
		LOOP	TpLoop
TpEnd:		POP	ES
		POP	DS
		POP	DI
		POP	SI
		POP	BP
		RET	6
TXPUT		ENDP

TXCHAR		PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		MOV	BX, CS:WORD PTR TXLN
		CMP	BX, TXMAX
		JAE	TcEnd
		MOV	AL, BYTE PTR [BP+4]
		MOV	CS:BYTE PTR TXBUF[BX], AL
		INC	CS:WORD PTR TXLN
TcEnd:		POP	BP
		RET	2
TXCHAR		ENDP

TXLEN		PROC	NEAR
		MOV	AX, CS:WORD PTR TXLN
		RET
TXLEN		ENDP

TXBYTE		PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		XOR	AX, AX
		MOV	BX, [BP+4]
		CMP	BX, CS:WORD PTR TXLN
		JAE	TbEnd
		MOV	AL, CS:BYTE PTR TXBUF[BX]
TbEnd:		POP	BP
		RET	2
TXBYTE		ENDP

TXCUT		PROC	NEAR
		PUSH	BP
		MOV	BP, SP
		MOV	AX, [BP+4]
		CMP	AX, CS:WORD PTR TXLN
		JAE	TxcEnd
		MOV	CS:WORD PTR TXLN, AX
TxcEnd:		POP	BP
		RET	2
TXCUT		ENDP

CKS1		DW	0
CKS2		DW	0
WRBUF		DB	128 DUP (0)
RDBUF		DB	128 DUP (0)
TXLN		DW	0
TXBUF		DB	TXMAX DUP (0)

CODE		ENDS
		END

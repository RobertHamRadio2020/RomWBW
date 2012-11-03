;__________________________________________________________________________________________________
;
;	PARALLEL PORT KEYBOARD DRIVER FOR N8VEM
;       SUPPORT KEYBOARD/MOUSE ON VDU AND N8
;
;	ORIGINAL CODE BY DR JAMES MOXHAM
;	ROMWBW ADAPTATION BY WAYNE WARTHEN
;__________________________________________________________________________________________________
;
;__________________________________________________________________________________________________
; DATA CONSTANTS
;__________________________________________________________________________________________________
;
#IF (PLATFORM == PLT_N8)
PPK_PPI		.EQU	084H		; PPI PORT BASE FOR N8
#ELSE 
PPK_PPI		.EQU	0F4H		; PPI PORT BASE FOR VDU
#ENDIF

PPK_PPIA	.EQU	PPK_PPI + 0	; KEYBOARD PPI PORT A
PPK_PPIB	.EQU	PPK_PPI + 1	; KEYBOARD PPI PORT B
PPK_PPIC	.EQU	PPK_PPI + 2	; KEYBOARD PPI PORT C
PPK_PPIX	.EQU	PPK_PPI + 3	; KEYBOARD PPI CONTROL PORT

PPK_DAT		.EQU	01111000B	; PPIX MASK TO MANAGE DATA LINE (C:4)
PPK_CLK		.EQU	01111010B	; PPIX MASK TO MANAGE CLOCK LINE (C:5)

PPK_WAITTO	.EQU	50 * CPUFREQ	; TUNE!!! WANT SMALL AS POSSIBLE W/O ERRORS
PPK_WAITRDY	.EQU	10 * CPUFREQ	; TUNE!!! 100US LOOP DELAY TO ENSURE DEVICE READY
;
;__________________________________________________________________________________________________
; KEYBOARD INITIALIZATION
;__________________________________________________________________________________________________
;
PPK_INIT:
	CALL 	PPK_INITPORT		; SETS PORT C SO CAN INPUT AND OUTPUT
	CALL 	PPK_RESET		; RESET TO THE KEYBOARD
	XOR	A			; SIGNAL SUCCESS
	RET
;
;__________________________________________________________________________________________________
; KEYBOARD STATUS
;__________________________________________________________________________________________________
;
; CHECKING THE KEYBOARD REQUIRES "WAITING" FOR A KEY TO BE SENT AND USING A TIMEOUT
; TO DETECT THAT NO KEY IS READY.  MANY APPS CALL STATUS REPEATEDLY.  IN ORDER TO AVOID
; SLOWING THEM DOWN, WE IGNORE 1/256 OF THE CALLS.
;
PPK_STAT:
	LD	A,(PPK_STATUS)		; GET STATUS
	AND	PPK_KEYRDY		; ISOLATE READ BIT
	JR	NZ,PPK_STAT3		; KEY READY, DONE

PPK_STAT1:
	LD	A,(PPK_IDLE)		; GET IDLE COUNT
	DEC	A			; DECREMENT IT
	LD	(PPK_IDLE),A		; SAVE IT
	JR	Z,PPK_STAT2		; ZERO?  OK, DO A REAL KEY CHECK
	XOR	A			; RETURN KEY NOT READY
	RET

PPK_STAT2:
	CALL	Z,PPK_DECODE		; NOT READY, RUN THE DECODING ENGINE
	LD	A,(PPK_STATUS)		; GET STATUS
	AND	PPK_KEYRDY		; ISOLATE READ BIT

PPK_STAT3:
	RLCA				; ROTATE READY BIT TO LOW ORDER BIT
	RET
;
;__________________________________________________________________________________________________
; KEYBOARD READ
;__________________________________________________________________________________________________
;
PPK_READ:
;	CALL	PPK_STAT		; CHECK TO SEE IF KEY READY
	LD	A,(PPK_STATUS)		; GET STATUS
	AND	PPK_KEYRDY		; ISOLIATE KEY READY BIT
	JR	NZ,PPK_READ1		; READY, GO GET THE KEY AND RETURN
	CALL	PPK_DECODE		; TRY TO GET A KEY
	JR	PPK_READ		; AND LOOP
;
PPK_READ1:
	LD	A,(PPK_KEYCODE)		; GET KEYCODE
	LD	E,A			; SAVE IT IN E
	LD	A,(PPK_STATE)		; GET STATE FLAGS
	LD	D,A			; SAVE THEM IN D
	XOR	A			; SIGNAL SUCCESS
	LD	(PPK_STATUS),A		; CLEAR STATE TO INDICATE BYTE RECEIVED
	RET
;
;__________________________________________________________________________________________________
; KEYBOARD FLUSH
;__________________________________________________________________________________________________
;
PPK_FLUSH:
	XOR	A			; A = 0
	LD	(PPK_STATE),A		; CLEAR STATE
	RET
;
;__________________________________________________________________________________________________
; HARDWARE INTERFACE
;__________________________________________________________________________________________________
;
;__________________________________________________________________________________________________
PPK_GETBYTE:
;
; GET RAW BYTE FROM KEYBOARD INTERFACE INTO A
; IF TIMEOUT, RETURN WITH A=0 AND Z SET
;
; ALL REGISTERS ARE DESTROYED
;
	CALL	PPK_CLKHI		; ALLOW KEYBOARD TO XMIT
	CALL	PPK_WTCLKLO		; WAIT FOR CLOCK LINE TO GO LOW
	JP	NZ,PPK_GETBYTE1		; IF IT WENT LOW, READ THE BYTE
	CALL	PPK_CLKLO		; SUPPRESS KEYBOARD XMIT
	XOR	A			; SIGNAL TIMEOUT
	RET
	
PPK_GETBYTE1:
	CALL 	PPK_WTCLKHI		; WAIT FOR END OF START BIT
	LD 	B,8			; SAMPLE 8 TIMES
	LD 	E,0			; START WITH E=0

PPK_GETBYTE2:
	CALL 	PPK_WTCLKLO		; WAIT TILL CLOCK GOES LOW
	IN 	A,(PPK_PPIB)		; SAMPLE THE DATA LINE
	RRA				; MOVE THE DATA BIT INTO THE CARRY REGISTER
	LD 	A,E			; GET THE BYTE WE ARE BUILDING IN E
	RRA				; MOVE THE CARRY BIT INTO BIT 7 AND SHIFT RIGHT
	LD 	E,A			; STORE IT BACK  AFTER 8 CYCLES 1ST BIT READ WILL BE IN B0
	CALL 	PPK_WTCLKHI		; WAIT TILL GOES HIGH
	DJNZ 	PPK_GETBYTE2		; DO THIS 8 TIMES
	CALL 	PPK_WTCLKLO		; GET THE PARITY BIT
	CALL 	PPK_WTCLKHI
	CALL 	PPK_WTCLKLO		; GET THE STOP BIT
	CALL 	PPK_WTCLKHI
	CALL	PPK_CLKLO		; SUPPRESS KEYBOARD XMIT
	LD 	A,E			; RETURN WITH RAW SCANCODE BYTE IN A
	
;	; *DEBUG*
;	CALL	PC_SPACE
;	CALL	PC_LT
;	CALL	PRTHEXBYTE

	OR	A
	RET
;
;__________________________________________________________________________________________________
PPK_PUTBYTE:
;
; PUT A RAW BYTE FROM A TO THE KEYBOARD INTERFACE
;
; ALL REGISTERS ARE DESTROYED
;
	LD	E,A			; STASH INCOMING BYTE VALUE IN E
	
;	; *DEBUG*
;	CALL	PC_SPACE
;	CALL	PC_GT
;	CALL	PRTHEXBYTE

	; START WITH DATA HI AND CLOCK LOW
	CALL	PPK_DATHI
	CALL 	PPK_CLKLO		; NEED CLOCK LOW TO GET DEVICE ATTENTION

	; WAIT 100US TO MAKE SURE DEVICE IS READY TO RECEIVE
	LD 	B,PPK_WAITRDY		; WAIT 100US
	DJNZ	$			; SPIN

	; SEND START BIT
	CALL 	PPK_DATLO		; SET DATA LOW - REQUEST TO SEND/START BIT
	CALL 	PPK_CLKHI		; RELEASE THE CLOCK LINE
	CALL 	PPK_WTCLKLO		; DEVICE HAS RECEIVED THE START BIT

	; SEND DATA BITS
	LD	B,8			; 8 DATA BITS
PPK_PUTBYTE1:
	RRC	E			; ROTATE LOW BIT OF E TO CARRY (NEXT BIT TO SEND)
	LD	A,PPK_DAT >> 1		; INIT A WITH DATA MASK SHIFTED RIGHT BY ONE BIT
	RLA				; SHIFT CARRY INTO LOW BIT OF A
	OUT 	(PPK_PPIX),A		; SET/RESET DATA LINE FOR NEXT BIT VALUE
	CALL 	PPK_WTCLKHI		; WAIT FOR CLOCK TO TRANSTION HI
	CALL 	PPK_WTCLKLO		; THEN LO, BIT HAS NOW BEEN RECEIVED BY DEVICE
	DJNZ	PPK_PUTBYTE1		; LOOP TO SEND 8 DATA BITS

	; SEND PARITY BIT
	XOR	A			; CLEAR A
	OR	E			; OR WITH SENT VALUE, SETS PARITY FLAG!
	LD	A,PPK_DAT		; PREPARE A WITH DATA MASK
	JP	PO,PPK_PUTBYTE2		; PARITY IS ALREADY ODD, LEAVE A ALONE
	INC	A			; SET PARITY BIT BY INCREMENTING A
PPK_PUTBYTE2:
	OUT 	(PPK_PPIX),A		; SET THE DATA LINE
	CALL 	PPK_WTCLKHI		; WAIT FOR CLOCK TO TRANSITION HI
	CALL 	PPK_WTCLKLO		; THEN LO, BIT HAS NOW BEEN RECEIVED BY DEVICE
	
	; SEND STOP BIT, NO NEED TO WATCH CLOCK, JUST WAIT FOR START OF DEVICE ACK
	CALL	PPK_DATHI		; STOP BIT IS 1 (HI)
	
	; HANDLE DEVICE ACK
	CALL	PPK_WTDATLO		; WAIT FOR DEVICE TO START ACK
	CALL	PPK_WTCLKLO		; WAIT FOR CLOCK TO TRANSITION LO
	CALL	PPK_WTCLKHI		; THEN HI
	CALL	PPK_WTDATHI		; FINALLY WAIT FOR DEVICE TO RELEASE DATA LINE
	
	; ASSERT CLOCK TO INHIBIT DEVICE FROM SENDING US ANYTHING UNTIL WE ARE READY
	CALL	PPK_CLKLO		; SET CLOCK LOW
	
	RET
;
;__________________________________________________________________________________________________
PPK_INITPORT:
;
; INITIALIZE PPI
;	
	LD 	A,10000010B		; A=OUT B=IN, C HIGH=OUT, CLOW=OUT
	OUT 	(PPK_PPIX),A		; SET PPI CONTROL PORT
	XOR	A			; A=0
	OUT	(PPK_PPIA),A		; PPI PORT A TO ZERO (REQUIRED FOR PAR PRINTER)
	CALL 	PPK_DATHI		; KBD DATA LINE HI (IDLE)
	CALL 	PPK_CLKHI		; KBD CLOCK LINE HI (IDLE)
	RET
;
;__________________________________________________________________________________________________
;
; BIT TESTING (PORT B)
;
;   B:0 = KBD DATA LINE (INPUT)
;   B:1 = KBD CLOCK LINE (INPUT)
;
;   TEST PPI PORT B BIT(S) DESIGNATED BY BITMASK IN D AFTER XOR WITH E
;   WAIT FOR ANY OF THE DESIGNATED BITS TO BE SET, THEN RETURN
;   IF TIMEOUT, RETURN WITH A=0 AND Z SET
;   HL IS DESTROYED, A IS OVERWRITTEN WITH RETURN VALUE
;
PPK_WTCLKLO:	; WAIT FOR CLOCK LINE TO BE LOW
	PUSH	DE
	LD	DE,0202H	; TEST BIT 1 AFTER INVERTING
	JR	PPK_WAIT
;
PPK_WTCLKHI:	; WAIT FOR CLOCK LINE TO BE HIGH
	PUSH	DE
	LD	DE,0200H	; TEST BIT 1
	JR	PPK_WAIT
;
PPK_WTDATLO:	; WAIT FOR DATA LINE TO BE LOW
	PUSH	DE
	LD	DE,0101H	; TEST BIT 0 AFTER INVERTING
	JR	PPK_WAIT
;
PPK_WTDATHI:	; WAIT FOR DATA LINE TO BE HIGH
	PUSH	DE
	LD	DE,0100H	; TEST BIT 0
	JR	PPK_WAIT
;
PPK_WAIT:	; COMPLETE THE WAIT PROCESSING
	LD	HL,PPK_WAITTO
PPK_WAIT1:
	IN 	A,(PPK_PPIB)	; GET BYTE FROM PORT B
	XOR	E
	AND	D
	JR 	NZ,PPK_WAIT2	; EXIT IF ANY BIT IS SET
	DEC	HL
	LD	A,H
	OR	L
	JR	NZ,PPK_WAIT1
PPK_WAIT2:
	POP	DE
	RET
;
;__________________________________________________________________________________________________
;
; BIT MANAGEMENT (PORT C)
;
;   C:4 = KBD DATA LINE (LATCHED OUTPUT)
;   C:5 = KBD CLOCK LINE (LATCHED OUTPUT)
;
;   A IS DESTROYED (OVERWRITTEN WITH PORT OUTPUT VALUE)
;
PPK_DATHI:
	LD	A,PPK_DAT + 1
	JR	PPK_SETBIT
PPK_DATLO:
	LD	A,PPK_DAT
	JR	PPK_SETBIT
PPK_CLKHI:
	LD	A,PPK_CLK + 1
	JR	PPK_SETBIT
PPK_CLKLO:
	LD	A,PPK_CLK
	JR	PPK_SETBIT
PPK_SETBIT:
	OUT 	(PPK_PPIX),A
	RET
;
;__________________________________________________________________________________________________
; RESET KEYBOARD
;__________________________________________________________________________________________________
;
PPK_RESET:
	LD	A,$FF		; RESET COMMAND
	CALL	PPK_PUTBYTE	; SEND IT
	CALL	PPK_GETBYTE	; GET THE ACK
	LD	B,0		; SETUP LOOP COUNTER
PPK_RESET0:
	PUSH	BC		; PRESERVE LOOP COUNTER
	CALL	DELAY		; DELAY 25MS
	CALL	PPK_GETBYTE	; TRY TO GET $AA
	POP	BC		; RESTORE LOOP COUNTER
	JR	NZ,PPK_RESET1	; GOT A BYTE?  IF SO, DONE (WE IGNORE RESPONSE CODE VALUE)
	DJNZ	PPK_RESET0	; KEEP TRYING UNTIL COUNTER EXPIRES
PPK_RESET1:
	XOR	A		; SIGNAL SUCCESS
	RET			; DONE
;
;__________________________________________________________________________________________________
; DECODING ENGINE
;__________________________________________________________________________________________________
;
; STATUS BITS (FOR PPK_STATUS)
;
PPK_EXT		.EQU	01H	; BIT 0, EXTENDED SCANCODE ACTIVE
PPK_BREAK	.EQU	02H	; BIT 1, THIS IS A KEY UP (BREAK) EVENT
PPK_KEYRDY	.EQU	80H	; BIT 7, INDICATES A DECODED KEYCODE IS READY
;
; STATE BITS (FOR PPK_STATE, PPK_LSTATE, PPK_RSTATE)
;
PPK_SHIFT	.EQU	01H	; BIT 0, SHIFT ACTIVE (PRESSED)
PPK_CTRL	.EQU	02H	; BIT 1, CONTROL ACTIVE (PRESSED)
PPK_ALT		.EQU	04H	; BIT 2, ALT ACTIVE (PRESSED)
PPK_WIN		.EQU	08H	; BIT 3, WIN ACTIVE (PRESSED)
PPK_SCRLCK	.EQU	10H	; BIT 4, CAPS LOCK ACTIVE (TOGGLED ON)
PPK_NUMLCK	.EQU	20H	; BIT 5, NUM LOCK ACTIVE (TOGGLED ON)
PPK_CAPSLCK	.EQU	40H	; BIT 6, SCROLL LOCK ACTIVE (TOGGLED ON)
PPK_NUMPAD	.EQU	80H	; BIT 7, NUM PAD KEY (KEY PRESSED IS ON NUM PAD)
;
PPK_SCANCODE	.DB	0	; RAW SCANCODE
PPK_KEYCODE	.DB	0	; RESULTANT KEYCODE AFTER DECODING
PPK_STATE	.DB	0	; STATE BITS (SEE ABOVE)
PPK_LSTATE	.DB	0	; STATE BITS FOR "LEFT" KEYS
PPK_RSTATE	.DB	0	; STATE BITS FOR "RIGHT" KEYS
PPK_STATUS	.DB	0	; CURRENT STATUS BITS (SEE ABOVE)
PPK_IDLE	.DB	0	; IDLE COUNT
;
;__________________________________________________________________________________________________
PPK_DECODE:
;
;  RUN THE DECODING ENGINE UNTIL EITHER: 1) A TIMEOUT OCCURS TRYING TO GET SCANCODES
;  FROM THE KEYBOARD, OR 2) A DECODED KEY VALUE IS AVAILABLE
;
;  RETURNS A=0 AND Z SET IF TIMEOUT, OTHERWISE A DECODED KEY VALUE IS AVAILABLE.
;  THE DECODED KEY VALUE AND KEY STATE IS STORED IN PPK_KEYCODE AND PPK_STATE.
;
;  PPK_KEYCODE AND PPK_STATUS ARE CLEARED AT START.  IF IS THE CALLER'S RESPONSIBILITY
;  TO RETRIEVE ANY PRIOR VALUE BEFORE CALLING THIS FUNCTION AGAIN.
;
	XOR	A			; A = ZERO
	LD	(PPK_STATUS),A		; CLEAR STATUS
	DEC	A			; A = $FF
	LD	(PPK_KEYCODE),A		; CLEAR KEYCODE

PPK_DECODENEXT:	; PROCESS NEXT SCANCODE
	CALL	PPK_GETBYTE		; GET A SCANCODE
	RET	Z			; TIMEOUT, RETURN WITH A=0, Z SET
	LD	(PPK_SCANCODE),A	; SAVE SCANCODE

PPK_DECODE1:	; HANDLE BREAK (KEYUP) F0 PREFIX
	CP	$F0			; BREAK (KEY UP) PREFIX?
	JR	NZ,PPK_DECODE2		; NOPE MOVE ON
	LD	A,(PPK_STATUS)		; GET STATUS
	OR	PPK_BREAK		; SET BREAK BIT
	LD	(PPK_STATUS),A		; SAVE STATUS
	JR	PPK_DECODENEXT		; LOOP TO DO NEXT SCANCODE

PPK_DECODE2:	; HANDLE EXTENDED KEY E0 PREFIX
	CP	$E0			; EXTENDED KEY PREFIX?
	JR	NZ,PPK_DECODE3		; NOPE MOVE ON
	LD	A,(PPK_STATUS)		; GET STATUS
	OR	PPK_EXT			; SET EXTENDED BIT
	LD	(PPK_STATUS),A		; SAVE STATUS
	JR	PPK_DECODENEXT		; LOOP TO DO NEXT SCANCODE

PPK_DECODE3:	; HANDLE SPECIAL EXTENDED KEY E1 PREFIX	
	; TODO: HANDLE PAUSE KEY HERE...

PPK_DECODE4:	; PERFORM EXTENDED MAPPING
	LD	A,(PPK_STATUS)		; GET STATUS
	AND	PPK_EXT			; EXTENDED BIT SET?
	JR	Z,PPK_DECODE5		; NOPE, MOVE ON
	LD	A,(PPK_SCANCODE)	; GET SCANCODE
	LD	E,A			; STASH IT IN E
	LD	HL,PPK_MAPEXT		; POINT TO START OF EXT MAP TABLE
PPK_DECODE4A:
	LD	A,(HL)			; GET FIRST BYTE OF PAIR
	CP	$00			; END OF TABLE?
	JP	Z,PPK_DECODE		; UNKNOWN OR BOGUS, START OVER
	INC	HL			; INC HL FOR FUTURE
	CP	E			; DOES MATCH BYTE EQUAL SCANCODE?
	JR	Z,PPK_DECODE4B		; YES! JUMP OUT
	INC	HL			; BUMP TO START OF NEXT PAIR
	JR	PPK_DECODE4A		; LOOP TO CHECK NEXT TABLE ENTRY
PPK_DECODE4B:
	LD	A,(HL)			; GET THE KEYCODE VIA MAPPING TABLE
	LD	(PPK_KEYCODE),A		; SAVE IT
	JR	PPK_DECODE6

PPK_DECODE5:	; PERFORM SHIFTED/UNSHIFTED MAPPING
	LD	A,(PPK_SCANCODE)	; GET THE SCANCODE
	CP	$85			; PAST END OF TABLE?
	JR	NC,PPK_DECODE6		; YES, SKIP OVER LOOKUP

	LD	A,(PPK_STATE)		; GET STATE
	AND	PPK_SHIFT		; SHIFT ACTIVE?
	LD	HL,PPK_MAPSTD		; LOAD ADDRESS OF NON-SHIFTED MAPPING TABLE
	JR	Z,PPK_DECODE5A		; NON-SHIFTED, MOVE ON
	LD	HL,PPK_MAPSHIFT		; LOAD ADDRESS OF SHIFTED MAPPING TABLE
PPK_DECODE5A:
	LD	A,(PPK_SCANCODE)	; GET THE SCANCODE
	LD	E,A			; SCANCODE TO E FOR TABLE OFFSET
	LD	D,0			; D -> 0
	ADD	HL,DE			; COMMIT THE TABLE OFFSET TO HL
	LD	A,(HL)			; GET THE KEYCODE VIA MAPPING TABLE
	LD	(PPK_KEYCODE),A		; SAVE IT

PPK_DECODE6:	; HANDLE MODIFIER KEY MAKE/BREAK EVENTS
	LD	A,(PPK_KEYCODE)		; MAKE SURE WE HAVE KEYCODE
	CP	$B8			; END OF MODIFIER KEYS
	JR	NC,PPK_DECODE13		; BYPASS MODIFIER KEY CHECKING
	CP	$B0			; START OF MODIFIER KEYS
	JR	C,PPK_DECODE13		; BYPASS MODIFIER KEY CHECKING
	
	; TODO: STUFF BELOW COULD BE A LOOP
	
	; HANDLE L/R SHIFT KEYS
	LD	E,PPK_SHIFT		; SETUP TO SET/CLEAR SHIFT BIT
	SUB	$B0			; L-SHIFT?
	JR	Z,PPK_DECODE7		; YES, HANDLE L-SHIFT MAKE/BREAK
	DEC	A			; R-SHIFT?
	JR	Z,PPK_DECODE8		; YES, HANDLE R-SHIFT MAKE/BREAK

	; HANDLE L/R CONTROL KEYS
	LD	E,PPK_CTRL		; SETUP TO SET/CLEAR CONTROL BIT
	DEC	A			; L-CONTROL?
	JR	Z,PPK_DECODE7		; YES, HANDLE L-CONTROL MAKE/BREAK
	DEC	A			; R-CONTROL?
	JR	Z,PPK_DECODE8		; YES, HANDLE R-CONTROL MAKE/BREAK

	; HANDLE L/R ALT KEYS
	LD	E,PPK_ALT		; SETUP TO SET/CLEAR ALT BIT
	DEC	A			; L-ALT?
	JR	Z,PPK_DECODE7		; YES, HANDLE L-ALT MAKE/BREAK
	DEC	A			; R-ALT?
	JR	Z,PPK_DECODE8		; YES, HANDLE R-ALT MAKE/BREAK

	; HANDLE L/R WIN KEYS
	LD	E,PPK_WIN		; SETUP TO SET/CLEAR WIN BIT
	DEC	A			; L-WIN?
	JR	Z,PPK_DECODE7		; YES, HANDLE L-WIN MAKE/BREAK
	DEC	A			; R-WIN?
	JR	Z,PPK_DECODE8		; YES, HANDLE R-WIN MAKE/BREAK

PPK_DECODE7:	; LEFT STATE KEY MAKE/BREAK (STATE BIT TO SET/CLEAR IN E)
	LD	HL,PPK_LSTATE
	JR	PPK_DECODE9

PPK_DECODE8:	; RIGHT STATE KEY MAKE/BREAK (STATE BIT TO SET/CLEAR IN E)
	LD	HL,PPK_RSTATE
	JR	PPK_DECODE9
	
PPK_DECODE9:	; BRANCH BASED ON WHETHER THIS IS A MAKE OR BREAK EVENT
	LD	A,(PPK_STATUS)		; GET STATUS FLAGS
	AND	PPK_BREAK		; BREAK EVENT?
	JR	Z,PPK_DECODE10		; NO, HANDLE A MODIFIER KEY MAKE EVENT
	JR	PPK_DECODE11		; YES, HANDLE A MODIFIER BREAK EVENT

PPK_DECODE10:	; HANDLE STATE KEY MAKE EVENT
	LD	A,E
	OR	(HL)
	LD	(HL),A
	JR	PPK_DECODE12

PPK_DECODE11:	; HANDLE STATE KEY BREAK EVENT
	LD	A,E
	XOR	$FF
	AND	(HL)
	LD	(HL),A
	JR	PPK_DECODE12
	
PPK_DECODE12:	; COALESCE L/R STATE FLAGS
	LD	A,(PPK_STATE)		; GET EXISTING STATE BITS
	AND	$F0			; GET RID OF OLD MODIFIER BITS
	LD	DE,(PPK_LSTATE)		; LOAD BOTH L/R STATE BYTES IN D/E
	OR	E			; MERGE IN LEFT STATE BITS
	OR	D			; MERGE IN RIGHT STATE BITS
	LD	(PPK_STATE),A		; SAVE IT
	JP	PPK_DECODE		; DONE WITH CURRENT KEYSTROKE

PPK_DECODE13:	; NO MORE BREAK KEY PROCESSING!
	LD	A,(PPK_STATUS)
	AND	PPK_BREAK
	JP	NZ,PPK_DECODE

PPK_DECODE14:	; TOGGLE KEY PROCESSING
	LD	A,(PPK_KEYCODE)
	LD	E,PPK_CAPSLCK
	CP	$BC
	JR	Z,PPK_DECODE15
	LD	E,PPK_NUMLCK
	CP	$BD
	JR	Z,PPK_DECODE15
	LD	E,PPK_SCRLCK
	CP	$BE
	JR	Z,PPK_DECODE15
	JR	PPK_DECODE16
	
PPK_DECODE15:	; RECORD THE TOGGLE
	LD	A,(PPK_STATE)
	XOR	E
	LD	(PPK_STATE),A
	
	LD	A,$ED			; SET/RESET LED'S COMMAND
	CALL	PPK_PUTBYTE
	CALL	PPK_GETBYTE
	CP	$FA			; MAKE SURE WE GET ACK
	JP	NZ,PPK_DECODE		; ABORT IF NO ACK
	LD	A,(PPK_STATE)
	RRCA
	RRCA
	RRCA
	RRCA
	AND	$07
	CALL	PPK_PUTBYTE		; SEND THE LED DATA
	CALL	PPK_GETBYTE		; READ THE ACK
	
	JP	PPK_DECODE		; DONE WITH CURRENT KEYSTROKE

PPK_DECODE16:	; CONTROL KEY PROCESSING
	LD	A,(PPK_STATE)
	AND	PPK_CTRL
	JR	Z,PPK_DECODE18		; CONTROL KEY NOT PRESSED, MOVE ON
	LD	A,(PPK_KEYCODE)
	CP	'a'
	JR	C,PPK_DECODE17
	CP	'z' + 1
	JR	NC,PPK_DECODE17
	RES	5,A			; CLEAR BIT 5 TO MAP LOWERCASE A-Z TO UPPERCASE
PPK_DECODE17:
	CP	'@'
	JR	C,PPK_DECODE18
	CP	'_' + 1
	JR	NC,PPK_DECODE18
	RES	6,A
	LD	(PPK_KEYCODE),A		; UPDATE KEYCODE TO CONTROL VALUE

PPK_DECODE18:	; CAPS LOCK KEY PROCESSING
	LD	A,(PPK_STATE)
	AND	PPK_CAPSLCK
	JR	Z,PPK_DECODE21		; CAPS LOCK NOT ACTIVE, MOVE ON
	LD	A,(PPK_KEYCODE)
	CP	'a'
	JR	C,PPK_DECODE19
	CP	'z' + 1
	JR	NC,PPK_DECODE19
	JR	PPK_DECODE20
PPK_DECODE19:
	CP	'A'
	JR	C,PPK_DECODE21
	CP	'Z' + 1
	JR	NC,PPK_DECODE21
	JR	PPK_DECODE20
PPK_DECODE20:
	LD	A,(PPK_KEYCODE)
	XOR	$20
	LD	(PPK_KEYCODE),A

PPK_DECODE21:	; NUM PAD PROCESSING
	LD	A,(PPK_STATE)
	AND	~PPK_NUMPAD
	LD	(PPK_STATE),A		; ASSUME NOT A NUMPAD KEY
	
	LD	A,(PPK_KEYCODE)
	AND	11100000B		; ISOLATE TOP 3 BITS
	CP	11000000B		; IS NUMPAD RANGE?
	JR	NZ,PPK_DECODEX		; NOPE, GET OUT
	
	LD	A,(PPK_STATE)
	OR	PPK_NUMPAD
	LD	(PPK_STATE),A		; SET NUMPAD BIT IN STATE

	AND	PPK_NUMLCK
	JR	Z,PPK_DECODE22		; SKIP NUMLOCK PROCESSING
	LD	A,(PPK_KEYCODE)
	XOR	$10			; FLIP FOR NUMLOCK
	LD	(PPK_KEYCODE),A		; SAVE IT
	
PPK_DECODE22:	; DO NUMPAD MAPPING
	LD	A,(PPK_KEYCODE)
	LD	HL,PPK_MAPNUMPAD
	SUB	$C0
	LD	E,A
	LD	D,0
	ADD	HL,DE
	LD	A,(HL)
	LD	(PPK_KEYCODE),A

PPK_DECODEX:
	LD	A,(PPK_KEYCODE)		; GET THE FINAL KEYCODE
	CP	$FF			; IS IT $FF (UNKNOWN/INVALID)
	JP	Z,PPK_DECODE		; IF SO, JUST RESTART THE ENGINE

	LD	A,(PPK_STATUS)		; GET CURRENT STATUS
	OR	PPK_KEYRDY		; SET KEY READY BIT
	LD	(PPK_STATUS),A		; SAVE IT
	XOR	A			; A=0
	INC	A			; SIGNAL SUCCESS WITH A=1
	RET
;
;__________________________________________________________________________________________________
; MAPPING TABLES
;__________________________________________________________________________________________________
;
PPK_MAPSTD:	; SCANCODE IS INDEX INTO TABLE TO RESULTANT LOOKUP KEYCODE
	.DB	$FF,$E8,$FF,$E4,$E2,$E0,$E1,$EB,$FF,$E9,$E7,$E5,$E3,$09,'`',$FF
	.DB	$FF,$B4,$B0,$FF,$B2,'q','1',$FF,$FF,$FF,'z','s','a','w','2',$FF
	.DB	$FF,'c','x','d','e','4','3',$FF,$FF,' ','v','f','t','r','5',$FF
	.DB	$FF,'n','b','h','g','y','6',$FF,$FF,$FF,'m','j','u','7','8',$FF
	.DB	$FF,',','k','i','o','0','9',$FF,$FF,'.','/','l',';','p','-',$FF
	.DB	$FF,$FF,$27,$FF,'[','=',$FF,$FF,$BC,$B1,$0D,']',$FF,'\',$FF,$FF
	.DB	$FF,$FF,$FF,$FF,$FF,$FF,$08,$FF,$FF,$C0,$FF,$C3,$C6,$FF,$FF,$FF
	.DB	$C9,$CA,$C1,$C4,$C5,$C7,$1B,$BD,$FA,$CE,$C2,$CD,$CC,$C8,$BE,$FF
	.DB	$FF,$FF,$FF,$E6,$EC
;
PPK_MAPSHIFT:	; SCANCODE IS INDEX INTO TABLE TO RESULTANT LOOKUP KEYCODE WHEN SHIFT ACTIVE
	.DB	$FF,$E8,$FF,$E4,$E2,$E0,$E1,$EB,$FF,$E9,$E7,$E5,$E3,$09,'~',$FF
	.DB	$FF,$B4,$B0,$FF,$B2,'Q','!',$FF,$FF,$FF,'Z','S','A','W','@',$FF
	.DB	$FF,'C','X','D','E','$','#',$FF,$FF,' ','V','F','T','R','%',$FF
	.DB	$FF,'N','B','H','G','Y','^',$FF,$FF,$FF,'M','J','U','&','*',$FF
	.DB	$FF,'<','K','I','O',')',')',$FF,$FF,'>','?','L',':','P','_',$FF
	.DB	$FF,$FF,$22,$FF,'{','+',$FF,$FF,$BC,$B1,$0D,'}',$FF,'|',$FF,$FF
	.DB	$FF,$FF,$FF,$FF,$FF,$FF,$08,$FF,$FF,$D0,$FF,$D3,$D6,$FF,$FF,$FF
	.DB	$D9,$DA,$D1,$D4,$D5,$D7,$1B,$BD,$FA,$DE,$D2,$DD,$DC,$D8,$BE,$FF
	.DB	$FF,$FF,$FF,$E6,$EC
;
PPK_MAPEXT:	; PAIRS ARE [SCANCODE,KEYCODE] FOR EXTENDED SCANCODES
	.DB	$11,$B5,	$14,$B3,	$1F,$B6,	$27,$B7
	.DB	$2F,$EF,	$37,$FA,	$3F,$FB,	$4A,$CB
	.DB	$5A,$CF,	$5E,$FC,	$69,$F3,	$6B,$F8
	.DB	$6C,$F2,	$70,$F0,	$71,$F1,	$72,$F7
	.DB	$74,$F9,	$75,$F6,	$7A,$F5,	$7C,$ED
	.DB	$7D,$F4,	$7E,$FD,	$00,$00
;
PPK_MAPNUMPAD:	; KEYCODE TRANSLATION FROM NUMPAD RANGE TO STD ASCII/KEYCODES
	.DB	$F3,$F7,$F5,$F8,$FF,$F9,$F2,$F6,$F4,$F0,$F1,$2F,$2A,$2D,$2B,$0D
	.DB	$31,$32,$33,$34,$35,$36,$37,$38,$39,$30,$2E,$2F,$2A,$2D,$2B,$0D

;======================================================================
;	SN76489 sound driver
;
;	WRITTEN BY: DEAN NETHERTON
;======================================================================
;
; TODO:
;
;======================================================================
; CONSTANTS
;======================================================================
;

SN76489_PORT_LEFT	.EQU	$FC	; PORTS FOR ACCESSING THE SN76489 CHIP (LEFT)
SN76489_PORT_RIGHT	.EQU	$F8	; PORTS FOR ACCESSING THE SN76489 CHIP (RIGHT)
SN7_IDAT		.EQU	0
SN7_TONECNT		.EQU	3	; COUNT NUMBER OF TONE CHANNELS
SN7_NOISECNT		.EQU	1	; COUNT NUMBER OF NOISE CHANNELS
SN7_CHCNT		.EQU	SN7_TONECNT + SN7_NOISECNT
CHANNEL_0_SILENT	.EQU	$9F
CHANNEL_1_SILENT	.EQU	$BF
CHANNEL_2_SILENT	.EQU	$DF
CHANNEL_3_SILENT	.EQU	$FF

SN7CLKDIVIDER	.EQU	4
SN7CLK		.EQU	CPUOSC / SN7CLKDIVIDER
SN7RATIO	.EQU	SN7CLK * 100 / 32


SN7_FIRST_NOTE	.EQU	5827		; A1#
SN7_LAST_NOTE	.EQU	209300		; C7

A1S		.EQU	SN7RATIO / SN7_FIRST_NOTE
C7		.EQU	SN7RATIO / SN7_LAST_NOTE

       .ECHO "SN76489: range of A1# (period: "
       .ECHO A1S
       .ECHO ") to C7 (period: "
       .ECHO C7
       .ECHO ")\n"

#INCLUDE "audio.inc"

SN76489_INIT:
	LD	IY, SN7_IDAT		; POINTER TO INSTANCE DATA

	LD	DE,STR_MESSAGELT
	CALL	WRITESTR
	LD	A, SN76489_PORT_LEFT
	CALL	PRTHEXBYTE

	LD	DE,STR_MESSAGERT
	CALL	WRITESTR
	LD	A, SN76489_PORT_RIGHT
	CALL	PRTHEXBYTE
;
SN7_INIT1:
	LD	BC, SN7_FNTBL		; BC := FUNCTION TABLE ADDRESS
	LD	DE, SN7_IDAT		; DE := SN7 INSTANCE DATA PTR
	CALL	SND_ADDENT		; ADD ENTRY, A := UNIT ASSIGNED

	CALL	SN7_VOLUME_OFF
	XOR	A			; SIGNAL SUCCESS
	RET

;======================================================================
; SN76489 DRIVER - SOUND ADAPTER (SND) FUNCTIONS
;======================================================================
;

SN7_RESET:
	AUDTRACE(SNT_INIT)
	CALL	SN7_VOLUME_OFF
	XOR	A			; SIGNAL SUCCESS
	RET

SN7_VOLUME_OFF:
	AUDTRACE(SNT_VOLOFF)

	LD	A, CHANNEL_0_SILENT
	OUT	(SN76489_PORT_LEFT), A
	OUT	(SN76489_PORT_RIGHT), A

	LD	A, CHANNEL_1_SILENT
	OUT	(SN76489_PORT_LEFT), A
	OUT	(SN76489_PORT_RIGHT), A

	LD	A, CHANNEL_2_SILENT
	OUT	(SN76489_PORT_LEFT), A
	OUT	(SN76489_PORT_RIGHT), A

	LD	A, CHANNEL_3_SILENT
	OUT	(SN76489_PORT_LEFT), A
	OUT	(SN76489_PORT_RIGHT), A

	RET

; BIT MAPPING
; SET TONE:
; 1 CC 0 PPPP (LOW)
; 0 0 PPPPPP (HIGH)

; 1 CC 1 VVVV

SN7_VOLUME:
	AUDTRACE(SNT_VOL)
	AUDTRACE_L
	AUDTRACE_CR
	LD	A, L
	LD	(SN7_PENDING_VOLUME), A

	XOR	A			; SIGNAL SUCCESS
	RET



SN7_NOTE:
	AUDTRACE(SNT_NOTE)
	AUDTRACE_HL
	AUDTRACE_CR

	LD	H,0
	ADD	HL, HL			; SHIFT RIGHT (MULT 2) -INDEX INTO SN7NOTETBL TABLE OF WORDS
					; TEST IF HL IS LARGER THAN SN7NOTETBL SIZE
	OR	A			; CLEAR CARRY FLAG
	LD	DE, SIZ_SN7NOTETBL
	SBC	HL, DE
	JR	NC, SN7_NOTE1		; INCOMING HL DOES NOT MAP INTO SN7NOTETBL

	ADD	HL, DE			; RESTORE HL
	LD	DE, SN7NOTETBL
	ADD	HL, DE

	LD	A, (HL)			; RETRIEVE PERIOD COUNT FROM SN7NOTETBL
	INC	HL
	LD	H, (HL)
	LD	L, A

	JR	SN7_PERIOD		; APPLY PERIOD

SN7_NOTE1:
	OR	$FF			; NOT IMPLEMENTED YET
	RET

SN7_PERIOD:
	AUDTRACE(SNT_PERIOD)
	AUDTRACE_HL
	AUDTRACE_CR

	LD	A, H
	CP	$04
	JP	NC, SN7_QUERY_PERIOD1	; RETURN NZ IF NUMBER TOO LARGE

	LD	(SN7_PENDING_PERIOD), HL
	XOR	A			; SIGNAL SUCCESS
	RET

SN7_QUERY_PERIOD1:			; REQUESTED PERIOD IS LARGER THAN THE SN76489 CAN SUPPORT
	LD	L, $FF
	LD	H, $FF
	LD	(SN7_PENDING_PERIOD), HL

	OR	$FF			; SIGNAL FAILURE
	RET

SN7_PLAY:
	AUDTRACE(SNT_PLAY)
	AUDTRACE_D
	AUDTRACE_CR

	LD	A, (SN7_PENDING_PERIOD + 1)
	CP	$FF
	JR	Z, SN7_PLAY1		; PERIOD IS TOO LARGE, UNABLE TO PLAY
	CALL	SN7_APPLY_VOL
	CALL	SN7_APPLY_PRD

	XOR	A			; SIGNAL SUCCESS
	RET

SN7_PLAY1:				; TURN CHANNEL VOL TO OFF AND STOP PLAYING
	LD	A, (SN7_PENDING_VOLUME)
	PUSH	AF
	LD	A, 0
	LD	(SN7_PENDING_VOLUME), A
	CALL	SN7_APPLY_VOL
	POP	AF
	LD	(SN7_PENDING_VOLUME), A

	OR	$FF			; SIGNAL FAILURE
	RET

SN7_QUERY:
	LD	A, E
	CP	BF_SNDQ_CHCNT
	JR	Z, SN7_QUERY_CHCNT

	CP	BF_SNDQ_PERIOD
	JR	Z, SN7_QUERY_PERIOD

	CP	BF_SNDQ_VOLUME
	JR	Z, SN7_QUERY_VOLUME

	CP	BF_SNDQ_DEV
	JR	Z, SN7_QUERY_DEV

	OR	$FF			; SIGNAL FAILURE
	RET

SN7_QUERY_CHCNT:
	LD	B, SN7_TONECNT
	LD	C, SN7_NOISECNT
	XOR	A
	RET

SN7_QUERY_PERIOD:
	LD	HL, (SN7_PENDING_PERIOD)
	XOR	A
	RET

SN7_QUERY_VOLUME:
	LD	A, (SN7_PENDING_VOLUME)
	LD	L, A
	LD	H, 0

	XOR	A
	RET

SN7_QUERY_DEV:

	LD	B, BF_SND_SN76489
	LD	DE, SN76489_PORT_LEFT 	; E WITH LEFT PORT
	LD	HL, SN76489_PORT_RIGHT	; L WITH RIGHT PORT

	XOR	A
	RET
;
;	UTIL FUNCTIONS
;

SN7_APPLY_VOL:				; APPLY VOLUME TO BOTH LEFT AND RIGHT CHANNELS
	PUSH	BC			; D CONTAINS THE CHANNEL NUMBER
	PUSH	AF
	LD	A, D
	AND	$3
	RLCA
	RLCA
	RLCA
	RLCA
	RLCA
	OR	$90
	LD	B, A

	LD	A, (SN7_PENDING_VOLUME)
	RRCA
	RRCA
	RRCA
	RRCA

	AND	$0F
	LD	C, A
	LD	A, $0F
	SUB	C
	AND	$0F
	OR	B			; A CONTAINS COMMAND TO SET VOLUME FOR CHANNEL

	AUDTRACE(SNT_REGWR)
	AUDTRACE_A
	AUDTRACE_CR

	OUT	(SN76489_PORT_LEFT), A
	OUT	(SN76489_PORT_RIGHT), A

	POP	AF
	POP	BC
	RET

SN7_APPLY_PRD:
	PUSH	DE
	PUSH	BC
	PUSH	AF
	LD	HL, (SN7_PENDING_PERIOD)

	LD	A, D
	AND	$3
	RLCA
	RLCA
	RLCA
	RLCA
	RLCA
	OR	$80
	LD	B, A			; PERIOD COMMAND 1 - CONTAINS CHANNEL ONLY

	LD	A, L			; GET LOWER 4 BITS FOR COMMAND 1
	AND	$F
	OR	B			; A NOW CONATINS FIRST PERIOD COMMAND

	AUDTRACE(SNT_REGWR)
	AUDTRACE_A
	AUDTRACE_CR

	OUT	(SN76489_PORT_LEFT), A
	OUT	(SN76489_PORT_RIGHT), A

	LD	A, L			; RIGHT SHIFT OUT THE LOWER 4 BITS
	RRCA
	RRCA
	RRCA
	RRCA
	AND	$F
	LD	B, A

	LD	A, H
	AND	$3
	RLCA
	RLCA
	RLCA
	RLCA				; AND PLACE IN BITS 5 AND 6
	OR	B			; OR THE TWO SETS OF BITS TO MAKE 2ND PERIOD COMMAND

	AUDTRACE(SNT_REGWR)
	AUDTRACE_A
	AUDTRACE_CR

	OUT	(SN76489_PORT_LEFT), A
	OUT	(SN76489_PORT_RIGHT), A

	POP	AF
	POP	BC
	POP	DE
	RET


SN7_FNTBL:
	.DW	SN7_RESET
	.DW	SN7_VOLUME
	.DW	SN7_PERIOD
	.DW	SN7_NOTE
	.DW	SN7_PLAY
	.DW	SN7_QUERY

#IF (($ - SN7_FNTBL) != (SND_FNCNT * 2))
	.ECHO	"*** INVALID SND FUNCTION TABLE ***\n"
	!!!!!
#ENDIF

SN7_PENDING_PERIOD
	.DW	0		; PENDING PERIOD (10 BITS)
SN7_PENDING_VOLUME
	.DB	0		; PENDING VOL (8 BITS -> DOWNCONVERTED TO 4 BITS AND INVERTED)

STR_MESSAGELT	.DB	"\r\nSN76489: LEFT IO=0x$"
STR_MESSAGERT	.DB	", RIGHT IO=0x$"

#IF AUDIOTRACE
SNT_INIT		.DB	"\r\nSN7_INIT\r\n$"
SNT_VOLOFF		.DB	"\r\nSN7_VOLUME OFF\r\n$"
SNT_VOL			.DB	"\r\nSN7_VOLUME: $"
SNT_NOTE		.DB	"\r\nSN7_NOTE: $"
SNT_PERIOD		.DB	"\r\nSN7_PERIOD: $"
SNT_PLAY		.DB	"\r\nSN7_PLAY CH: $"
SNT_REGWR		.DB	"\r\nOUT SN76489, $"
#ENDIF

; THE FREQUENCY BY QUARTER TONE STARTING AT A1#
SN7NOTETBL:
	.DW	A1S	 ; 5827
	.DW	SN7RATIO / 5912
	.DW	SN7RATIO / 5998
	.DW	SN7RATIO / 6085
	.DW	SN7RATIO / 6174
	.DW	SN7RATIO / 6264
	.DW	SN7RATIO / 6355
	.DW	SN7RATIO / 6447
	.DW	SN7RATIO / 6541
	.DW	SN7RATIO / 6636
	.DW	SN7RATIO / 6733
	.DW	SN7RATIO / 6831
	.DW	SN7RATIO / 6930
	.DW	SN7RATIO / 7031
	.DW	SN7RATIO / 7133
	.DW	SN7RATIO / 7237
	.DW	SN7RATIO / 7342
	.DW	SN7RATIO / 7449
	.DW	SN7RATIO / 7557
	.DW	SN7RATIO / 7667
	.DW	SN7RATIO / 7778
	.DW	SN7RATIO / 7891
	.DW	SN7RATIO / 8006
	.DW	SN7RATIO / 8122
	.DW	SN7RATIO / 8241
	.DW	SN7RATIO / 8361
	.DW	SN7RATIO / 8482
	.DW	SN7RATIO / 8606
	.DW	SN7RATIO / 8731
	.DW	SN7RATIO / 8858
	.DW	SN7RATIO / 8987
	.DW	SN7RATIO / 9118
	.DW	SN7RATIO / 9250
	.DW	SN7RATIO / 9385
	.DW	SN7RATIO / 9521
	.DW	SN7RATIO / 9660
	.DW	SN7RATIO / 9800
	.DW	SN7RATIO / 9943
	.DW	SN7RATIO / 10087
	.DW	SN7RATIO / 10234
	.DW	SN7RATIO / 10383
	.DW	SN7RATIO / 10534
	.DW	SN7RATIO / 10687
	.DW	SN7RATIO / 10843
	.DW	SN7RATIO / 11000
	.DW	SN7RATIO / 11160
	.DW	SN7RATIO / 11322
	.DW	SN7RATIO / 11487
	.DW	SN7RATIO / 11654
	.DW	SN7RATIO / 11824
	.DW	SN7RATIO / 11995
	.DW	SN7RATIO / 12170
	.DW	SN7RATIO / 12347
	.DW	SN7RATIO / 12527
	.DW	SN7RATIO / 12709
	.DW	SN7RATIO / 12894
	.DW	SN7RATIO / 13081
	.DW	SN7RATIO / 13271
	.DW	SN7RATIO / 13464
	.DW	SN7RATIO / 13660
	.DW	SN7RATIO / 13859
	.DW	SN7RATIO / 14061
	.DW	SN7RATIO / 14265
	.DW	SN7RATIO / 14473
	.DW	SN7RATIO / 14683
	.DW	SN7RATIO / 14897
	.DW	SN7RATIO / 15113
	.DW	SN7RATIO / 15333
	.DW	SN7RATIO / 15556
	.DW	SN7RATIO / 15782
	.DW	SN7RATIO / 16012
	.DW	SN7RATIO / 16245
	.DW	SN7RATIO / 16481
	.DW	SN7RATIO / 16721
	.DW	SN7RATIO / 16964
	.DW	SN7RATIO / 17211
	.DW	SN7RATIO / 17461
	.DW	SN7RATIO / 17715
	.DW	SN7RATIO / 17973
	.DW	SN7RATIO / 18234
	.DW	SN7RATIO / 18500
	.DW	SN7RATIO / 18769
	.DW	SN7RATIO / 19042
	.DW	SN7RATIO / 19319
	.DW	SN7RATIO / 19600
	.DW	SN7RATIO / 19885
	.DW	SN7RATIO / 20174
	.DW	SN7RATIO / 20468
	.DW	SN7RATIO / 20765
	.DW	SN7RATIO / 21067
	.DW	SN7RATIO / 21373
	.DW	SN7RATIO / 21684
	.DW	SN7RATIO / 22000
	.DW	SN7RATIO / 22320
	.DW	SN7RATIO / 22645
	.DW	SN7RATIO / 22974
	.DW	SN7RATIO / 23308
	.DW	SN7RATIO / 23647
	.DW	SN7RATIO / 23991
	.DW	SN7RATIO / 24340
	.DW	SN7RATIO / 24694
	.DW	SN7RATIO / 25053
	.DW	SN7RATIO / 25418
	.DW	SN7RATIO / 25787
	.DW	SN7RATIO / 26163
	.DW	SN7RATIO / 26544
	.DW	SN7RATIO / 26930
	.DW	SN7RATIO / 27321
	.DW	SN7RATIO / 27718
	.DW	SN7RATIO / 28121
	.DW	SN7RATIO / 28530
	.DW	SN7RATIO / 28945
	.DW	SN7RATIO / 29366
	.DW	SN7RATIO / 29793
	.DW	SN7RATIO / 30226
	.DW	SN7RATIO / 30666
	.DW	SN7RATIO / 31113
	.DW	SN7RATIO / 31566
	.DW	SN7RATIO / 32025
	.DW	SN7RATIO / 32490
	.DW	SN7RATIO / 32963
	.DW	SN7RATIO / 33442
	.DW	SN7RATIO / 33929
	.DW	SN7RATIO / 34422
	.DW	SN7RATIO / 34923
	.DW	SN7RATIO / 35431
	.DW	SN7RATIO / 35946
	.DW	SN7RATIO / 36469
	.DW	SN7RATIO / 36999
	.DW	SN7RATIO / 37537
	.DW	SN7RATIO / 38083
	.DW	SN7RATIO / 38637
	.DW	SN7RATIO / 39200
	.DW	SN7RATIO / 39770
	.DW	SN7RATIO / 40349
	.DW	SN7RATIO / 40936
	.DW	SN7RATIO / 41530
	.DW	SN7RATIO / 42134
	.DW	SN7RATIO / 42747
	.DW	SN7RATIO / 43369
	.DW	SN7RATIO / 44000
	.DW	SN7RATIO / 44640
	.DW	SN7RATIO / 45289
	.DW	SN7RATIO / 45948
	.DW	SN7RATIO / 46616
	.DW	SN7RATIO / 47294
	.DW	SN7RATIO / 47982
	.DW	SN7RATIO / 48680
	.DW	SN7RATIO / 49388
	.DW	SN7RATIO / 50106
	.DW	SN7RATIO / 50835
	.DW	SN7RATIO / 51575
	.DW	SN7RATIO / 52325
	.DW	SN7RATIO / 53086
	.DW	SN7RATIO / 53858
	.DW	SN7RATIO / 54642
	.DW	SN7RATIO / 55437
	.DW	SN7RATIO / 56243
	.DW	SN7RATIO / 57061
	.DW	SN7RATIO / 57891
	.DW	SN7RATIO / 58733
	.DW	SN7RATIO / 59587
	.DW	SN7RATIO / 60454
	.DW	SN7RATIO / 61333
	.DW	SN7RATIO / 62225
	.DW	SN7RATIO / 63130
	.DW	SN7RATIO / 64048
	.DW	SN7RATIO / 64980
	.DW	SN7RATIO / 65925
	.DW	SN7RATIO / 66884
	.DW	SN7RATIO / 67857
	.DW	SN7RATIO / 68844
	.DW	SN7RATIO / 69846
	.DW	SN7RATIO / 70862
	.DW	SN7RATIO / 71893
	.DW	SN7RATIO / 72938
	.DW	SN7RATIO / 73999
	.DW	SN7RATIO / 75075
	.DW	SN7RATIO / 76167
	.DW	SN7RATIO / 77275
	.DW	SN7RATIO / 78399
	.DW	SN7RATIO / 79539
	.DW	SN7RATIO / 80696
	.DW	SN7RATIO / 81870
	.DW	SN7RATIO / 83061
	.DW	SN7RATIO / 84269
	.DW	SN7RATIO / 85495
	.DW	SN7RATIO / 86738
	.DW	SN7RATIO / 88000
	.DW	SN7RATIO / 89280
	.DW	SN7RATIO / 90579
	.DW	SN7RATIO / 91896
	.DW	SN7RATIO / 93233
	.DW	SN7RATIO / 94589
	.DW	SN7RATIO / 95965
	.DW	SN7RATIO / 97361
	.DW	SN7RATIO / 98777
	.DW	SN7RATIO / 100214
	.DW	SN7RATIO / 101671
	.DW	SN7RATIO / 103150
	.DW	SN7RATIO / 104650
	.DW	SN7RATIO / 106172
	.DW	SN7RATIO / 107716
	.DW	SN7RATIO / 109283
	.DW	SN7RATIO / 110873
	.DW	SN7RATIO / 112486
	.DW	SN7RATIO / 114122
	.DW	SN7RATIO / 115782
	.DW	SN7RATIO / 117466
	.DW	SN7RATIO / 119175
	.DW	SN7RATIO / 120908
	.DW	SN7RATIO / 122667
	.DW	SN7RATIO / 124451
	.DW	SN7RATIO / 126261
	.DW	SN7RATIO / 128098
	.DW	SN7RATIO / 129961
	.DW	SN7RATIO / 131851
	.DW	SN7RATIO / 133769
	.DW	SN7RATIO / 135715
	.DW	SN7RATIO / 137689
	.DW	SN7RATIO / 139691
	.DW	SN7RATIO / 141723
	.DW	SN7RATIO / 143784
	.DW	SN7RATIO / 145876
	.DW	SN7RATIO / 147998
	.DW	SN7RATIO / 150151
	.DW	SN7RATIO / 152335
	.DW	SN7RATIO / 154550
	.DW	SN7RATIO / 156798
	.DW	SN7RATIO / 159079
	.DW	SN7RATIO / 161393
	.DW	SN7RATIO / 163740
	.DW	SN7RATIO / 166122
	.DW	SN7RATIO / 168538
	.DW	SN7RATIO / 170990
	.DW	SN7RATIO / 173477
	.DW	SN7RATIO / 176000
	.DW	SN7RATIO / 178560
	.DW	SN7RATIO / 181157
	.DW	SN7RATIO / 183792
	.DW	SN7RATIO / 186466
	.DW	SN7RATIO / 189178
	.DW	SN7RATIO / 191930
	.DW	SN7RATIO / 194722
	.DW	SN7RATIO / 197553
	.DW	SN7RATIO / 200426
	.DW	SN7RATIO / 203342
	.DW	SN7RATIO / 206299
	.DW	C7	 ; 209300

SIZ_SN7NOTETBL	.EQU	$ - SN7NOTETBL
		.ECHO	"SN76489 approx "
		.ECHO	SIZ_SN7NOTETBL / 2 / 4 /12
		.ECHO	" Octaves.  Last note index supported: "

		.ECHO SIZ_SN7NOTETBL / 2
		.ECHO "\n"

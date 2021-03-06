/* round.s - Motorola 68040 FP rounding routines (EXC) */

/* Copyright 1991-1993 Wind River Systems, Inc. */
	.data
	.globl	_copyright_wind_river
	.long	_copyright_wind_river

/*
modification history
--------------------
01g,21jul93,kdl  added .text (SPR #2372).
01f,23aug92,jcf  changed bxxx to jxx.
01e,26may92,rrr  the tree shuffle
01d,10jan92,kdl  general cleanup.
01c,01jan92,jcf	 reversed order of cmp <reg>,<reg>
01b,17dec91,kdl	 put in changes from Motorola v3.4 (from FPSP 2.1):
		 use register for fixing "lsll 29" problem (01a);
		 add check for negative loop count in __x_dnrm_lp.
01a,31jul91,kdl  original version, from Motorola FPSP v2.0;
		 divided "lsll #29" into smaller bit shifts.
*/

/*
DESCRIPTION


	roundsa 3.2 2/18/91

	handle rounding and normalization tasks


		Copyright (C) Motorola, Inc. 1990
			All Rights Reserved

	THIS IS UNPUBLISHED PROPRIETARY SOURCE CODE OF MOTOROLA
	The copyright notice above does not evidence any
	actual or intended publication of such source code.

ROUND	idnt    2,1 Motorola 040 Floating Point Software Package

	section	8

NOMANUAL
*/

#include "fpsp040E.h"

|
|	__x_round --- round result according to precision/mode
|
|	a0 points to the input operand in the internal extended format
|	d1(high word) contains rounding precision:
|		ext = 0x0000xxxx
|		sgl = 0x0001xxxx
|		dbl = 0x0002xxxx
|	d1(low word) contains rounding mode:
|		RN  = $xxxx0000
|		RZ  = $xxxx0001
|		RM  = $xxxx0010
|		RP  = $xxxx0011
|	d0{31:29} contains the g,r,s bits (extended)
|
|	On return the value pointed to by a0 is correctly rounded,
|	a0 is preserved and the g-r-s bits in d0 are cleared.
|	The result is not typed - the tag field is invalid.  The
|	result is still in the internal extended format.
|
|	The INEX bit of USER_FPSR will be set if the rounded result was
|	inexact (i.e. if any of the g-r-s bits were set).
|

	.globl	__x_round

	.text

__x_round:
| If g=r=s=0 then result is exact and round is done, else set
| the inex flag in status reg and continue.
|
	bsrl	ext_grs			| this subroutine looks at the
|					| rounding precision and sets
|					| the appropriate g-r-s bits.
	tstl	d0			| if grs are zero, go force
	jne 	rnd_cont		| lower bits to zero for size

	swap	d1			| set up d1:w for round prec.
	jra 	truncate

rnd_cont:
|
| Use rounding mode as an index into a jump table for these modes.
|
	orl	#inx2a_mask,a6@(USER_FPSR) | set inex2/ainex
	lea	mode_tab,a1
	movel	a1@(d1:w:4),a1
	jmp	a1@
|
| Jump table indexed by rounding mode in d1:w.  All following assumes
| grs != 0.
|
mode_tab:
	.long	rnd_near
	.long	rnd_zero
	.long	rnd_mnus
	.long	rnd_plus
|
|	ROUND PLUS INFINITY
|
|	If sign of fp number = 0 (positive), then add 1 to l.
|
rnd_plus:
	swap 	d1			| set up d1 for round prec.
	tstb	a0@(LOCAL_SGN)		| check for sign
	jmi 	truncate		| if positive then truncate
	movel	#0xffffffff,d0		/* | force g,r,s to be all f's */
	lea	add_to_l,a1
	movel	a1@(d1:w:4),a1
	jmp	a1@
|
|	ROUND MINUS INFINITY
|
|	If sign of fp number = 1 (negative), then add 1 to l.
|
rnd_mnus:
	swap 	d1			| set up d1 for round prec.
	tstb	a0@(LOCAL_SGN)		| check for sign
	jpl 	truncate		| if negative then truncate
	movel	#0xffffffff,d0		/* | force g,r,s to be all f's */
	lea	add_to_l,a1
	movel	a1@(d1:w:4),a1
	jmp	a1@
|
|	ROUND ZERO
|
|	Always truncate.
rnd_zero:
	swap 	d1			| set up d1 for round prec.
	jra 	truncate
|
|
|	ROUND NEAREST
|
|	If (g=1), then add 1 to l and if (r=s=0), then clear l
|	Note that this will round to even in case of a tie.
|
rnd_near:
	swap 	d1			| set up d1 for round prec.
	asll	#1,d0			| shift g-bit to c-bit
	jcc 	truncate		| if (g=1) then
	lea	add_to_l,a1
	movel	a1@(d1:w:4),a1
	jmp	a1@

|
|	ext_grs --- extract guard, round and sticky bits
|
| Input:	d1 =		PREC:ROUND
| Output:  	d0{31:29}=	guard, round, sticky
|
| The ext_grs extract the guard/round/sticky bits according to the
| selected rounding precision. It is called by the round subroutine
| only.  All registers except d0 are kept intact. d0 becomes an
| updated guard,round,sticky in d0{31:29}
|
| Notes: the ext_grs uses the round PREC, and therefore has to swap d1
|	 prior to usage, and needs to restore d1 to original.
|
ext_grs:
	swap	d1			| have d1:w point to round precision
	cmpiw	#0,d1
	jne 	sgl_or_dbl
	jra 	end_ext_grs

sgl_or_dbl:
	moveml	d2/d3,a7@-		| make some temp registers
	cmpiw	#1,d1
	jne 	grs_dbl
grs_sgl:
	bfextu	a0@(LOCAL_HI){#24:#2},d3	| sgl prec. g-r are 2 bits right
	movel	#30,d2			| of the sgl prec. limits
	lsll	d2,d3			| shift g-r bits to MSB of d3
	movel	a0@(LOCAL_HI),d2	| get word 2 for s-bit test
	andil	#0x0000003f,d2		| s bit is the or of all other
	jne 	st_stky			| bits to the right of g-r
	tstl	a0@(LOCAL_LO)		| test lower mantissa
	jne 	st_stky			| if any are set, set sticky
	tstl	d0			| test original g,r,s
	jne 	st_stky			| if any are set, set sticky
	jra 	end_sd			| if words 3 and 4 are clr, exit
grs_dbl:
	bfextu	a0@(LOCAL_LO){#21:#2},d3	| dbl-prec. g-r are 2 bits right
	movel	#30,d2			| of the dbl prec. limits
	lsll	d2,d3			| shift g-r bits to the MSB of d3
	movel	a0@(LOCAL_LO),d2	| get lower mantissa  for s-bit test
	andil	#0x000001ff,d2		| s bit is the or-ing of all
	jne 	st_stky			| other bits to the right of g-r
	tstl	d0			| test word original g,r,s
	jne 	st_stky			| if any are set, set sticky
	jra 	end_sd			| if clear, exit
st_stky:
	bset	#rnd_stky_bit,d3
end_sd:
	movel	d3,d0			| return grs to d0
	moveml	a7@+,d2/d3		| restore scratch registers
end_ext_grs:
	swap	d1			| restore d1 to original
	rts

|*******************  Local Equates
#define	ad_1_sgl 	0x00000100  /* constant to add 1 to l-bit in sgl prec */
#define	ad_1_dbl 	0x00000800  /* constant to add 1 to l-bit in dbl prec */


|Jump table for adding 1 to the l-bit indexed by rnd prec

add_to_l:
	.long	add_ext
	.long	add_sgl
	.long	add_dbl
	.long	add_dbl
|
|	ADD SINGLE
|
add_sgl:
	addl	#ad_1_sgl,a0@(LOCAL_HI)
	jcc 	scc_clr			| no mantissa overflow
	roxrw 	a0@(LOCAL_HI)		| shift v-bit back in
	roxrw 	a0@(LOCAL_HI+2)		| shift v-bit back in
	addw	#0x1,a0@(LOCAL_EX)	| and incr exponent
scc_clr:
	tstl	d0			| test for rs = 0
	jne 	sgl_done
	andiw  #0xfe00,a0@(LOCAL_HI+2)	| clear the l-bit
sgl_done:
	andil	#0xffffff00,a0@(LOCAL_HI) | truncate bits beyond sgl limit
	clrl	a0@(LOCAL_LO)		| clear d2
	rts

|
|	ADD EXTENDED
|
add_ext:
	addql  #1,a0@(LOCAL_LO)		| add 1 to l-bit
	jcc 	xcc_clr			| test for carry out
	addql  #1,a0@(LOCAL_HI)		| propogate carry
	jcc 	xcc_clr
	roxrw 	a0@(LOCAL_HI)		| mant is 0 so restore v-bit
	roxrw 	a0@(LOCAL_HI+2)		| mant is 0 so restore v-bit
	roxrw	a0@(LOCAL_LO)
	roxrw	a0@(LOCAL_LO+2)
	addw	#0x1,a0@(LOCAL_EX)	| and inc exp
xcc_clr:
	tstl	d0			| test rs = 0
	jne 	add_ext_done
	andib	#0xfe,a0@(LOCAL_LO+3)	| clear the l bit
add_ext_done:
	rts
|
|	ADD DOUBLE
|
add_dbl:
	addl	#ad_1_dbl,a0@(LOCAL_LO)
	jcc 	dcc_clr
	addql	#1,a0@(LOCAL_HI)		| propogate carry
	jcc 	dcc_clr
	roxrw	a0@(LOCAL_HI)		| mant is 0 so restore v-bit
	roxrw	a0@(LOCAL_HI+2)		| mant is 0 so restore v-bit
	roxrw	a0@(LOCAL_LO)
	roxrw	a0@(LOCAL_LO+2)
	addw	#0x1,a0@(LOCAL_EX)	| incr exponent
dcc_clr:
	tstl	d0			| test for rs = 0
	jne 	dbl_done
	andiw	#0xf000,a0@(LOCAL_LO+2)	| clear the l-bit

dbl_done:
	andil	#0xfffff800,a0@(LOCAL_LO) | truncate bits beyond dbl limit
	rts

error:
	rts
|
| Truncate all other bits
|
trunct:
	.long	end_rnd
	.long	sgl_done
	.long	dbl_done
	.long	dbl_done

truncate:
	lea	trunct,a1
	movel	a1@(d1:w:4),a1
	jmp	a1@

end_rnd:
	rts

|
|	NORMALIZE
|
| These routines (nrm_zero # __x_nrm_set) normalize the unnorm.  This
| is done by shifting the mantissa left while decrementing the
| exponent.
|
| NRM_SET shifts and decrements until there is a 1 set in the integer
| bit of the mantissa (msb in d1).
|
| NRM_ZERO shifts and decrements until there is a 1 set in the integer
| bit of the mantissa (msb in d1) unless this would mean the exponent
| would go less than 0.  In that case the number becomes a denorm - the
| exponent	d0@ is set to 0 and the mantissa (d1 # d2) is not
| normalized.
|
| Note that both routines have been optimized (for the worst case) and
| therefore do not have the easy to follow decrement/shift loop.
|
|	NRM_ZERO
|
|	Distance to first 1 bit in mantissa = X
|	Distance to 0 from exponent = Y
|	If X < Y
|	Then
|	  __x_nrm_set
|	Else
|	  shift mantissa by Y
|	  set exponent = 0
|
|input:
|	FP_SCR1 = exponent, ms mantissa part, ls mantissa part
|output:
|	L_SCR1{4} = fpte15 or ete15 bit
|
	.globl	__x_nrm_zero
__x_nrm_zero:
	movew	a0@(LOCAL_EX),d0
	cmpw   #64,d0          | see if exp > 64
	jmi 	d0_less
	bsrl	__x_nrm_set		/* | exp > 64 so exp won't exceed 0  */
	rts
d0_less:
	moveml	d2/d3/d5/d6,a7@-
	movel	a0@(LOCAL_HI),d1
	movel	a0@(LOCAL_LO),d2

	bfffo	d1{#0:#32},d3	| get the distance to the first 1
|				| in ms mant
	jeq 	ms_clr		| branch if no bits were set
	cmpw	d3,d0		| of X>Y
	jmi 	greater		| then exp will go past 0 (neg) if
|				| it is just shifted
	bsrl	__x_nrm_set		/* | else exp won't go past 0 */
	moveml	a7@+,d2/d3/d5/d6
	rts
greater:
	movel	d2,d6		| save ls mant in d6
	lsll	d0,d2		| shift ls mant by count
	lsll	d0,d1		| shift ms mant by count
	movel	#32,d5
	subl	d0,d5		| make op a denorm by shifting bits
	lsrl	d5,d6		| by the number in the exp, then
|				| set exp = 0.
	orl	d6,d1		| shift the ls mant bits into the ms mant
	movel	#0,d0		| same as if decremented exp to 0
|				| while shifting
	movew	d0,a0@(LOCAL_EX)
	movel	d1,a0@(LOCAL_HI)
	movel	d2,a0@(LOCAL_LO)
	moveml	a7@+,d2/d3/d5/d6
	rts
ms_clr:
	bfffo	d2{#0:#32},d3	| check if any bits set in ls mant
	jeq 	all_clr		| branch if none set
	addw	#32,d3
	cmpw	d3,d0		| if X>Y
	jmi 	greater		| then branch
	bsrl	__x_nrm_set		/* | else exp won't go past 0 */
	moveml	a7@+,d2/d3/d5/d6
	rts
all_clr:
	movew	#0,a0@(LOCAL_EX)	| no mantissa bits set. Set exp = 0.
	moveml	a7@+,d2/d3/d5/d6
	rts
|
|	NRM_SET
|
	.globl	__x_nrm_set
__x_nrm_set:
	movel	d7,a7@-
	bfffo	a0@(LOCAL_HI){#0:#32},d7 | find first 1 in ms mant to d7)
	jeq 	lower		/* | branch if ms mant is all 0's */

	movel	d6,a7@-

	subw	d7,a0@(LOCAL_EX)	| sub exponent by count
	movel	a0@(LOCAL_HI),d0	| d0 has ms mant
	movel	a0@(LOCAL_LO),d1 | d1 has ls mant

	lsll	d7,d0		| shift first 1 to j bit position
	movel	d1,d6		| copy ls mant into d6
	lsll	d7,d6		| shift ls mant by count
	movel	d6,a0@(LOCAL_LO)	| store ls mant into memory
	moveql	#32,d6
	subl	d7,d6		| continue shift
	lsrl	d6,d1		| shift off all bits but those that will
|				| be shifted into ms mant
	orl	d1,d0		| shift the ls mant bits into the ms mant
	movel	d0,a0@(LOCAL_HI)	| store ms mant into memory
	moveml	a7@+,d7/d6	| restore registers
	rts

|
| We get here if ms mant was = 0, and we assume ls mant has bits
| set (otherwise this would have been tagged a zero not a denorm).
|
lower:
	movew	a0@(LOCAL_EX),d0	| d0 has exponent
	movel	a0@(LOCAL_LO),d1	| d1 has ls mant
	subw	#32,d0		| account for ms mant being all zeros
	bfffo	d1{#0:#32},d7	| find first 1 in ls mant to d7)
	subw	d7,d0		| subtract shift count from exp
	lsll	d7,d1		| shift first 1 to integer bit in ms mant
	movew	d0,a0@(LOCAL_EX)	| store ms mant
	movel	d1,a0@(LOCAL_HI)	| store exp
	clrl	a0@(LOCAL_LO)	| clear ls mant
	movel	a7@+,d7
	rts
|
|	__x_denorm --- denormalize an intermediate result
|
|	Used by underflow.
|
| Input:
|	a0	 points to the operand to be denormalized
|		 (in the internal extended format)
|
|	d0: 	 rounding precision
| Output:
|	a0	 points to the denormalized result
|		 (in the internal extended format)
|
|	d0 	is guard,round,sticky
|
| d0 comes into this routine with the rounding precision. It
| is then loaded with the denormalized exponent threshold for the
| rounding precision.
|

	.globl	__x_denorm
__x_denorm:
	btst	#6,a0@(LOCAL_EX)	| check for exponents between 0x7fff-0x4000
	jeq 	no_sgn_ext
	bset	#7,a0@(LOCAL_EX)	| sign extend if it is so
no_sgn_ext:

	cmpib	#0,d0		| if 0 then extended precision
	jne 	not_ext		| else branch

	clrl	d1		| load d1 with ext threshold
	clrl	d0		| clear the sticky flag
	bsrl	__x_dnrm_lp		| denormalize the number
	tstb	d1		| check for inex
	jeq 	no_inex		| if clr, no inex
	jra 	dnrm_inex	| if set, set inex

not_ext:
	cmpil	#1,d0		| if 1 then single precision
	jeq 	load_sgl	| else must be 2, double prec

load_dbl:
	movew	#dbl_thresh,d1	| put copy of threshold in d1
	movel	d1,d0		| copy d1 into d0
	subw	a0@(LOCAL_EX),d0	| diff = threshold - exp
	cmpw	#67,d0		| if diff > 67 (mant + grs bits)
	jpl 	chk_stky	| then branch (all bits would be
|				|  shifted off in denorm routine)
	clrl	d0		| else clear the sticky flag
	bsrl	__x_dnrm_lp		| denormalize the number
	tstb	d1		| check flag
	jeq 	no_inex		| if clr, no inex
	jra 	dnrm_inex	| if set, set inex

load_sgl:
	movew	#sgl_thresh,d1	| put copy of threshold in d1
	movel	d1,d0		| copy d1 into d0
	subw	a0@(LOCAL_EX),d0	| diff = threshold - exp
	cmpw	#67,d0		| if diff > 67 (mant + grs bits)
	jpl 	chk_stky	| then branch (all bits would be
|				|  shifted off in __x_denorm routine)
	clrl	d0		| else clear the sticky flag
	bsrl	__x_dnrm_lp		| denormalize the number
	tstb	d1		| check flag
	jeq 	no_inex		| if clr, no inex
	jra 	dnrm_inex	| if set, set inex

chk_stky:
	tstl	a0@(LOCAL_HI)	| check for any bits set
	jne 	set_stky
	tstl	a0@(LOCAL_LO)	| check for any bits set
	jne 	set_stky
	jra 	clr_mant
set_stky:
	orl	#inx2a_mask,a6@(USER_FPSR) | set inex2/ainex
	movel	#0x20000000,d0	| set sticky bit in return value
clr_mant:
	movew	d1,a0@(LOCAL_EX)		| load exp with threshold
	movel	#0,a0@(LOCAL_HI) 	| set d1 = 0 (ms mantissa)
	movel	#0,a0@(LOCAL_LO)		| set d2 = 0 (ms mantissa)
	rts
dnrm_inex:
	orl	#inx2a_mask,a6@(USER_FPSR) | set inex2/ainex
no_inex:
	rts

|
|	__x_dnrm_lp --- normalize exponent/mantissa to specified threshhold
|
| Input:
|	a0		points to the operand to be denormalized
|	d0{31:29} 	initial guard,round,sticky
|	d1{15:0}	denormalization threshold
| Output:
|	a0		points to the denormalized operand
|	d0{31:29}	final guard,round,sticky
|	d1b		inexact flag:  all ones means inexact result
|
| The LOCAL_LO and LOCAL_GRS parts of the value are copied to FP_SCR2
| so that bfext can be used to extract the new low part of the mantissa.
| Dnrm_lp can be called with a0 pointing to ETEMP or WBTEMP and there
| is no LOCAL_GRS scratch word following it on the fsave frame.
|
	.globl	__x_dnrm_lp
__x_dnrm_lp:
	movel	d2,a7@-		| save d2 for temp use
	btst	#E3,a6@(E_BYTE)		| test for type E3 exception
	jeq 	not_E3			| not type E3 exception
	clrl	d0			| guard,round,sticky init.
	bfextu	a6@(WBTEMP_GRS){#6:#3},d2	| extract guard,round, sticky  bit

|  The following bit shift specifies a larger number of bits than actually
|  allowed (8).  So, it was divided into a series of smaller shifts.
| 	lsll	#29,d2			| original shift g,r,s to their postions
|
|
|	lsll	#8,d2			| shift g,r,s 8 bits
|	lsll	#8,d2			| shift g,r,s 8 bits (total 16)
|	lsll	#8,d2			| shift g,r,s 8 bits (total 24)
|	lsll	#5,d2			| shift g,r,s 5 bits (total 29)
|	orl	d2,d0			| in d0

	movel	#29,d0
	lsll	d0,d2			| shift g,r,s to their postions
	movel	d2,d0

not_E3:
	movel	a7@+,d2		| restore d2
	movel	a0@(LOCAL_LO),a6@(FP_SCR2+LOCAL_LO)
	movel	d0,a6@(FP_SCR2+LOCAL_GRS)
	movel	d1,d0			| copy the denorm threshold
	subw	a0@(LOCAL_EX),d1		| d1 = threshold - uns exponent
	jle 	no_lp			| d1 <= 0
	cmpw	#32,d1
	jlt 	case_1			| 0 = d1 < 32
	cmpw	#64,d1
	jlt 	case_2			| 32 <= d1 < 64
	jra 	case_3			| d1 >= 64
|
| No normalization necessary
|
no_lp:
	clrb	d1			| set no inex2 reported
	movel	a6@(FP_SCR2+LOCAL_GRS),d0	| restore original g,r,s
	rts
|
| case (0<d1<32)
|
case_1:
	movel	d2,a7@-
	movew	d0,a0@(LOCAL_EX)		| exponent = denorm threshold
	movel	#32,d0
	subw	d1,d0			| d0 = 32 - d1
	bfextu	a0@(LOCAL_EX){d0:#32},d2
	bfextu	d2{d1:d0},d2		| d2 = new LOCAL_HI
	bfextu	a0@(LOCAL_HI){d0:#32},d1	| d1 = new LOCAL_LO
	bfextu	a6@(FP_SCR2+LOCAL_LO){d0:#32},d0	| d0 = new G,R,S
	movel	d2,a0@(LOCAL_HI)		| store new LOCAL_HI
	movel	d1,a0@(LOCAL_LO)		| store new LOCAL_LO
	clrb	d1
	bftst	d0{#2:#30}
	jeq 	c1nstky
	bset	#rnd_stky_bit,d0
	st	d1
c1nstky:
	movel	a6@(FP_SCR2+LOCAL_GRS),d2	| restore original g,r,s
	andil	#0xe0000000,d2		| clear all but G,R,S
	tstl	d2			| test if original G,R,S are clear
	jeq 	grs_clear
	orl	#0x20000000,d0		| set sticky bit in d0
grs_clear:
	andil	#0xe0000000,d0		| clear all but G,R,S
	movel	a7@+,d2
	rts
|
| case (32<=d1<64)
|
case_2:
	movel	d2,a7@-
	movew	d0,a0@(LOCAL_EX)		| unsigned exponent = threshold
	subw	#32,d1			| d1 now between 0 and 32
	movel	#32,d0
	subw	d1,d0			| d0 = 32 - d1
	bfextu	a0@(LOCAL_EX){d0:#32},d2
	bfextu	d2{d1:d0},d2		| d2 = new LOCAL_LO
	bfextu	a0@(LOCAL_HI){d0:#32},d1	| d1 = new G,R,S
	bftst	d1{#2:#30}
	jne 	c2_sstky		| jra  if sticky bit to be set
	bftst	a6@(FP_SCR2+LOCAL_LO){d0:#32}
	jne 	c2_sstky		| jra  if sticky bit to be set
	movel	d1,d0
	clrb	d1
	jra 	end_c2
c2_sstky:
	movel	d1,d0
	bset	#rnd_stky_bit,d0
	st	d1
end_c2:
	clrl	a0@(LOCAL_HI)		| store LOCAL_HI = 0
	movel	d2,a0@(LOCAL_LO)		| store LOCAL_LO
	movel	a6@(FP_SCR2+LOCAL_GRS),d2	| restore original g,r,s
	andil	#0xe0000000,d2		| clear all but G,R,S
	tstl	d2			| test if original G,R,S are clear
	jeq 	clear_grs
	orl	#0x20000000,d0		| set sticky bit in d0
clear_grs:
	andil	#0xe0000000,d0		| get rid of all but G,R,S
	movel	a7@+,d2
	rts
|
| d1 >= 64 Force the exponent to be the denorm threshold with the
| correct sign.
|
case_3:
	movew	d0,a0@(LOCAL_EX)
	tstw	a0@(LOCAL_SGN)
	jge 	c3con
c3neg:
	orl	#0x80000000,a0@(LOCAL_EX)
c3con:
	cmpw	#64,d1
	jeq 	sixty_four
	cmpw	#65,d1
	jeq 	sixty_five
|
| Shift value is out of range.  Set d1 for inex2 flag and
| return a zero with the given threshold.
|
	clrl	a0@(LOCAL_HI)
	clrl	a0@(LOCAL_LO)
	movel	#0x20000000,d0
	st	d1
	rts

sixty_four:
	movel	a0@(LOCAL_HI),d0
	bfextu	d0{#2:#30},d1
	andil	#0xc0000000,d0
	jra 	c3com

sixty_five:
	movel	a0@(LOCAL_HI),d0
	bfextu	d0{#1:#31},d1
	andil	#0x80000000,d0
	lsrl	#1,d0			| shift high bit into R bit

c3com:
	tstl	d1
	jne 	c3ssticky
	tstl	a0@(LOCAL_LO)
	jne 	c3ssticky
	tstb	a6@(FP_SCR2+LOCAL_GRS)
	jne 	c3ssticky
	clrb	d1
	jra 	c3end

c3ssticky:
	bset	#rnd_stky_bit,d0
	st	d1
c3end:
	clrl	a0@(LOCAL_HI)
	clrl	a0@(LOCAL_LO)
	rts

|	end

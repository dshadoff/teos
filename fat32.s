; ***************************************************************************
; ***************************************************************************
;
; fat32.s
;
; Functions for using a FAT32-formatted SD card on the Turbo Everdrive v2.
;
; Copyright John Brandwood 2019.
;
; Distributed under the Boost Software License, Version 1.0.
; (See accompanying file LICENSE_1_0.txt or copy at
;  http://www.boost.org/LICENSE_1_0.txt)
;
; ***************************************************************************
; ***************************************************************************
;
; For FAT32 programming information, see ...
;
;   "FAT32 File System Specification" at
;     https://msdn.microsoft.com/en-us/windows/hardware/gg463080.aspx
;
;   "exFAT File System Specification" at
;     https://docs.microsoft.com/en-us/windows/win32/fileio/exfat-specification
;
; ***************************************************************************
; ***************************************************************************



; ***************************************************************************
; ***************************************************************************
;
; Data
;

		.bss

		if	0
		PAGE_ALIGN
f32_file_map:					; Map of file fragments.
f32_long_name:	ds	256			; Lo-Byte of a long filename.
f32_cache_buf	ds	512			; Sector cache (FAT/DIR).
		else
f32_long_name	=	$3D00			; Lo-Byte of a long filename.
f32_cache_buf	=	$3E00			; Sector cache (FAT/DIR).
f32_file_map	=	f32_long_name		; Map of file fragments.
		endif

f32_file_pos:	ds	8			; Current fragment within map.

f32_cache_sec:	ds	4			; Sector number in the cache.

f32_boot_sector:ds	4			; SD card block #.
f32_fat1_begins:ds	4			; SD card block #.
f32_fat2_begins:ds	4			; SD card block #.
f32_data_begins:ds	4			; SD card block #.
f32_cluster_cnt:ds	4			; # of clusters in volume.
f32_root_extent:ds	4			; 1st cluster in root dir.

f32_dir_cluster:ds	4			; 1st cluster in current dir.
f32_fil_cluster:ds	4			; 1st cluster in current file.

f32_cur_cluster:ds	4			; Current cluster number.
f32_sector_num:	ds	4			; Current stored sector.

f32_file_length:ds	4			; Length of current file.
f32_file_mutex:	ds	1			; Only allow one open file.

f32_cluster_idx:ds	1			; Sector # within cluster.
f32_sec2cls_cnt:ds	1			; # sectors in a cluster.
f32_sec2cls_rot:ds	1			; ^ same, as a shift count.
f32_fat_ext_flg:ds	1

f32_long_next:	ds	1			; Next ORD of long name.
f32_long_csum:	ds	1			; Checksum of long name.
f32_name_length:ds	1			; StrLen of the name.

		.code



; ***************************************************************************
; ***************************************************************************
;
; Definitions
;

; Return Codes for the FAT32 functions.
;
; N.B. Error codes from SD.S can also
;      be returned!

F32_FOUND_FAT	=	0
F32_FOUND_MBR	=	1
F32_FOUND_UNK	=	2

F32_OK		=	$00
F32_ERR_DSK_RD	=	$90
F32_ERR_NO_DSK	=	$91
F32_ERR_NO_VOL	=	$92
F32_ERR_BAD_FAT	=	$93
F32_ERR_INVALID	=	$94
F32_ERR_NO_NAME	=	$95
F32_ERR_FRAGGED	=	$96
F32_EOC_CLUSTER	=	$97
F32_ERR_EOF	=	$98
F32_ERR_MUTEX	=	$99

; BPB definitions for FAT32/FAT16/FAT12

BPB_jmpBoot	=	(f32_cache_buf +  0)
BPB_OEMName	=	(f32_cache_buf +  3)
BPB_BytsPerSec	=	(f32_cache_buf + 11)
BPB_SecPerClus	=	(f32_cache_buf + 13)
BPB_RsvdSecCnt	=	(f32_cache_buf + 14)
BPB_NumFATs	=	(f32_cache_buf + 16)
BPB_RootEntCnt	=	(f32_cache_buf + 17)
BPB_TotSec16	=	(f32_cache_buf + 19)
BPB_Media	=	(f32_cache_buf + 21)
BPB_FATSz16	=	(f32_cache_buf + 22)
BPB_SecPerTrk	=	(f32_cache_buf + 24)
BPB_NumHeads	=	(f32_cache_buf + 26)
BPB_HiddSec	=	(f32_cache_buf + 28)
BPB_TotSec32	=	(f32_cache_buf + 32)

; BPB definitions for FAT32-only

BPB_FATSz32	=	(f32_cache_buf + 36)
BPB_ExtFlags	=	(f32_cache_buf + 40)
BPB_FSVer	=	(f32_cache_buf + 42)
BPB_RootClus	=	(f32_cache_buf + 44)
BPB_FSInfo	=	(f32_cache_buf + 48)
BPB_BkBootSec	=	(f32_cache_buf + 50)

BS_DrvNum32	=	(f32_cache_buf + 64)
BS_BootSig32	=	(f32_cache_buf + 66)
BS_VolID32	=	(f32_cache_buf + 67)
BS_VolLab32	=	(f32_cache_buf + 71)
BS_FilSysType	=	(f32_cache_buf + 82)

; BPB definitions for MBR/FAT

BS_Offset01FE	=	(f32_cache_buf + 510)
BS_Offset01FF	=	(f32_cache_buf + 511)

; DIR definitions for FAT32/FAT16/FAT12

ATTR_Read_Only	=	$01
ATTR_Hidden	=	$02
ATTR_System	=	$04
ATTR_Volume_ID	=	$08
ATTR_Directory	=	$10
ATTR_Archive	=	$20

ATTR_Type_Mask	=	$18
ATTR_Long_Mask	=	$3F
ATTR_Long_Name	=	$0F

DIR_Name	=	 0
DIR_Attr	=	11
DIR_NTres	=	12
DIR_CrtTime	=	14
DIR_CrtDate	=	16
DIR_FstClusHI	=	20
DIR_WrtTime	=	22
DIR_WrtDate	=	24
DIR_FstClusLO	=	26
DIR_FileSize	=	28

LDIR_Ord	=	 0
LDIR_Name1	=	 1
LDIR_Attr	=	11
LDIR_Type	=	12
LDIR_Chksum	=	13
LDIR_Name2	=	14
LDIR_FstClusLO	=	26
LDIR_Name3	=	28

FLAG_Last_Ord	=	$40



; ****************************************************************************
; ****************************************************************************
;
; f32_mount_vol - Initialize the SD Card and mount the first FAT32 partition.
;
; Returns: X = F32_OK (and Z flag) or an error code.
;

f32_mount_vol:	; Initialize the SD Card.

		if	REALHW

		jsr	sdc_initialize
		beq	.find_volume

.no_disk:	ldx	#F32_ERR_NO_DSK
		rts

		endif

		; Read the SD Card's Boot Sector.

.find_volume:	stz	f32_boot_sector + 0
		stz	f32_boot_sector + 1
		stz	f32_boot_sector + 2
		stz	f32_boot_sector + 3

		; Is it a FAT32 BPB?

		jsr	.check_bpb
		beq	.found_fat

		; Is it an MBR?

		cpx	#F32_FOUND_MBR
		bne	.no_volume

		; Select the first valid FAT32 partition.

		ldx	#$FC
		cly

.find_partition:lda	f32_cache_buf + $01BE + $00,y
		and	#$7F 			; Invalid Partition?
		bne	.next_partition
		lda	f32_cache_buf + $01BE + $04,y
		cmp	#$0B 			; Win95 FAT32 CHS/LBA < 8GB
		beq	.got_partition
		cmp	#$0C 			; Win95 FAT32 LBA     > 8GB
		beq	.got_partition
.next_partition:tya
		clc
		adc	#$10
		tay
		cpy	#$40
		bne	.find_partition
		bra	.no_volume

		; Read the partition's Boot Sector.

.got_partition:	lda	f32_cache_buf + $01BE + $08,y
		sta	f32_boot_sector - $FC,x
		iny
		inx
		bne	.got_partition

		; Is it a FAT32 BPB?

		jsr	.check_bpb
		beq	.found_fat

.no_volume:	ldx	#F32_ERR_NO_VOL
		rts

.found_fat:	; Make sure the volume uses 512 bytes-per-sector (SDC standard).

		lda	BPB_BytsPerSec + 0
		bne	.no_volume
		lda	BPB_BytsPerSec + 1
		cmp	#>(512)
		bne	.no_volume

		; Make sure that the volume is > 65535 sectors total.

		lda	BPB_TotSec16 + 0
		ora	BPB_TotSec16 + 1
		bne	.no_volume

		; Make sure that there are zero entries in the root.

		lda	BPB_RootEntCnt + 0
		ora	BPB_RootEntCnt + 1
		bne	.no_volume

		; Make sure that there are only 1 or 2 copies of the FAT.

		lda	BPB_ExtFlags
		sta	f32_fat_ext_flg

		ldy	BPB_NumFATs
		beq	.no_volume
		cpy	#3
		bcs	.no_volume

		; Extend BPB_RsvdSecCnt to a 32-bit value.

		stz	BPB_NumFATs

		; Calc f32_fat1_begins = f32_boot_sector + BPB_RsvdSecCnt
		; Save f32_root_extent & f32_dir_cluster

		ldx	#$FC
		clc
.long1:		lda	f32_boot_sector - $FC,x
		adc	BPB_RsvdSecCnt  - $FC,x
		sta	f32_fat1_begins - $FC,x
		sta	f32_fat2_begins - $FC,x

		lda	BPB_RootClus    - $FC,x
		sta	f32_root_extent - $FC,x
		sta	f32_dir_cluster - $FC,x
		inx
		bne	.long1

		; Calc f32_fat2_begins = f32_fat1_begins + BPB_FATSz32

		cpy	#1 ; BPB_NumFATs
		beq	.no_fat2

		ldx	#$FC
		clc
.long2:		lda	f32_fat1_begins - $FC,x
		adc	BPB_FATSz32     - $FC,x
		sta	f32_fat2_begins - $FC,x
		inx
		bne	.long2

		; Calc f32_data_begins = f32_fat2_begins + BPB_FATSz32

.no_fat2:	ldx	#$FC
		clc
.long3:		lda	f32_fat2_begins - $FC,x
		adc	BPB_FATSz32     - $FC,x
		sta	f32_data_begins - $FC,x
		inx
		bne	.long3

		; Calc NumHeadSectors = f32_data_begins - f32_boot_sector

		ldx	#$FC
		sec
.long4:		lda	f32_data_begins - $FC,x
		sbc	f32_boot_sector - $FC,x
		sta	f32_cluster_cnt - $FC,x
		inx
		bne	.long4

		; Calc NumDataSectors = BPB_TotSec32 - HeadSectors

		ldx	#$FC
		sec
.long5:		lda	BPB_TotSec32    - $FC,x
		sbc	f32_cluster_cnt - $FC,x
		sta	f32_cluster_cnt - $FC,x
		inx
		bne	.long5

		; ClusterCnt = NumDataSectors / BPB_SecPerClus

		lda	BPB_SecPerClus
		sta	f32_sec2cls_cnt
		cly
		bra	.skip0
.long6:		ldx	#3
		clc
.long7:		ror	f32_cluster_cnt,x
		dex
		bpl	.long7
		iny
.skip0:		lsr	a
		bcc	.long6
		bne	.not_fat32		; Fail if not a power-of-2.
		sty	f32_sec2cls_rot

		; FAT entries are 32-bit if ClusterCnt >= 65525

		ldx	#$FC
		sec
.compare:	lda	f32_cluster_cnt - $FC,x
		sbc	f32_minimum_cnt - $FC,x
		inx
		bne	.compare
		bcc	.not_fat32

		; So many clusters that BAD_CLUSTER is a possible value?

		ldx	#$FC
		sec
.maximum:	lda	f32_cluster_cnt - $FC,x
		sbc	f32_illegal_cnt - $FC,x
		inx
		bne	.maximum
		bcc	.got_fat32

		; Clamp the number of clusters.

		ldx	#$FC
.clamp:		lda	f32_illegal_cnt - $FC,x
		sta	f32_cluster_cnt - $FC,x
		inx
		bne	.clamp
		bra	.got_fat32

.not_fat32:	ldx	#F32_ERR_BAD_FAT
		rts

		;
		; Check if the sector contents look like a BPB.
		;

.check_bpb:	tii	f32_boot_sector, sdc_block_num, 4

		lda	#$01
		sta	sdc_block_cnt + 0
		stz	sdc_block_cnt + 1
		stw	#f32_cache_buf, <sdc_data_addr

		jsr	sdc_read_data
		beq	.got_sector

		ldx	#F32_ERR_DSK_RD
		rts

.got_sector:	ldx	#F32_FOUND_UNK

		; Check for the boot sector signature.

		lda	BS_Offset01FE
		cmp	#$55
		bne	.finished
		lda	BS_Offset01FF
		cmp	#$AA
		bne	.finished

		ldx	#F32_FOUND_MBR

		; Check for the FAT32 ID in the BPB.

		ldy	#7
.strcmp:	lda	BS_FilSysType,y
		cmp	.signature,y
		bne	.finished
		dey
		bpl	.strcmp

.got_fat32:	ldx	#F32_FOUND_FAT
.finished:	rts

.signature:	db	"FAT32   "

f32_minimum_cnt:db	$F5,$FF,$00,$00		; 65525 clusters
f32_illegal_cnt:db	$F5,$FF,$FF,$0F		; Too many clusters.
f32_cluster_bad:db	$F7,$FF,$FF,$0F		; Test if == val.
f32_cluster_eoc:db	$F8,$FF,$FF,$0F		; Test if >= val.
f32_cluster_msk:db	$FF,$FF,$FF,$0F		; Mask out the top 4-bits.



; ****************************************************************************
; ****************************************************************************
;
; f32_clear_cache - Clear the sector cache.
;
; Sector #0 is the MBR/BPB.
; Sector #1 is the FSINFO sector if SD card is formatted as a floppy.
; Sector #2 is never read, so set that as the current cache contents.
;

f32_clear_cache:lda	#$02
		sta	f32_cache_sec + 0
		stz	f32_cache_sec + 1
		stz	f32_cache_sec + 2
		stz	f32_cache_sec + 3
		rts



; ****************************************************************************
; ****************************************************************************
;
; f32_load_cache - Load up the sector cache from the SD card.
;
; Returns: X = F32_OK (and Z flag) or an error code.
;

f32_load_cache:	ldx	#$FC			; Is the sector cached?
.test:		lda	f32_sector_num - $FC,x
		cmp	f32_cache_sec  - $FC,x
		bne	.load
		inx
		bne	.test
		rts				; Return F32_OK.

.load:		lda	#$01
		sta	sdc_block_cnt + 0
		stz	sdc_block_cnt + 1

		lda	#<f32_cache_buf
		sta	<sdc_data_addr + 0
		lda	#>f32_cache_buf
		sta	<sdc_data_addr + 1

		tii	f32_sector_num, f32_cache_sec, 4
		tii	f32_sector_num, sdc_block_num, 4

		jsr	sdc_read_data
		beq	.done

		ldx	#F32_ERR_DSK_RD
.done:		rts



; ****************************************************************************
; ****************************************************************************
;
; f32_nxt_sector - Inc sector # within a cluster (returns C if over cluster).
; f32_inc_sector - Inc sector # without any checks (for scanning FAT).
;

f32_nxt_sector:	lda	f32_cluster_idx
		inc	a
		cmp	f32_sec2cls_cnt
		bcs	f32_got_sector		; C flag state is returned.
		sta	f32_cluster_idx

f32_inc_sector:	ldx	#$FC
.inc_byte:	inc	f32_sector_num - $FC,x
		bne	f32_got_sector
		inx
		bne	.inc_byte
f32_got_sector:	rts



; ****************************************************************************
; ****************************************************************************
;
; f32_nxt_cluster - Follow the FAT32 cluster chain to the next cluster.
;
; Uses __bp = Pointer to the cluster number in the cached FAT.
;
; Returns: X = F32_OK (and Z flag) or an error code.
;

f32_nxt_cluster:lda	f32_cur_cluster		; Ptr = (cluster * 4) % 512
		tax
		asl	a
		asl	a
		sta	<__bp + 0
		cla
		rol	a
		adc	#>f32_cache_buf
		sta	<__bp + 1

		txa				; Sec = (cluster * 4) / 512
		asl	a			;     = (cluster * 2) / 256
		ldx	#$FD
.rotate_byte:	lda	f32_cur_cluster + 1 - $FD,x
		rol	a
		sta	f32_sector_num  + 0 - $FD,x
		inx
		bne	.rotate_byte
		stz	f32_sector_num + 3

.add_long:	ldx	#$FC			; f32_sector_num =
		clc				;    f32_sector_num + f32_fat1_begins.
.add_byte:	lda	f32_fat1_begins - $FC,x
		adc	f32_sector_num  - $FC,x
		sta	f32_sector_num  - $FC,x
		inx
		bne	.add_byte

		jsr	f32_load_cache		; Load a FAT32 sector.
		beq	f32_use_cluster		; Get the next cluster #.

		rts				; Return the error code.



; ****************************************************************************
; ****************************************************************************
;
; f32_change_dir  - Change dir to one in directory entry ptr in __bp.
; f32_select_root - Change dir to root directory.
;
; Args __bp = Pointer to directory entry in cache.
;
; Returns: X = F32_OK (and Z flag) or an error code.
;

f32_change_dir:	lda	[__bp]			; End of directory?
		beq	.not_directory
		cmp	#$E5			; Empty entry?
		beq	.not_directory

		ldy	#DIR_Attr		; Is this a directory?
		lda	[__bp],y
		and	#ATTR_Type_Mask
		cmp	#ATTR_Directory
		beq	.got_directory

.not_directory:	ldx	#F32_ERR_INVALID
		rts

.got_directory:	jsr	f32_set_cluster		; From cur directory entry.

		tii	f32_cur_cluster, f32_dir_cluster, 4

f32_dir_chosen:	lda	f32_dir_cluster + 0	; Check for a zero cluster.
		ora	f32_dir_cluster + 1
		ora	f32_dir_cluster + 2
		ora	f32_dir_cluster + 3
		bne	f32_rewind_dir		; Finished if non-zero.

f32_select_root:tii	f32_root_extent, f32_dir_cluster, 4
		bra	f32_rewind_dir



; ****************************************************************************
; ****************************************************************************
;
; f32_rewind_dir  - Goto the 1st cluster of the current directory.
; f32_rewind_file - Goto the 1st cluster of the current file.
; f32_use_cluster - Calc a sector addr (from ptr to cluster # in __bp).
;
; Uses __bp = Pointer to variable holding the cluster number.
;
; Returns: X = F32_OK (and Z flag) or an error code.
;

f32_rewind_dir:	lda	#$FF			; Signal no long name.
		sta	f32_long_next
		stz	f32_name_length		; Reset the long name length.

		lda	#<f32_dir_cluster	; Goto 1st cluster in the
		sta	<__bp + 0		; current directory.
		lda	#>f32_dir_cluster
		sta	<__bp + 1
		bra	f32_use_cluster

		;

f32_rewind_file:lda	#<f32_fil_cluster	; Goto 1st cluster in the
		sta	<__bp + 0		; current file.
		lda	#>f32_fil_cluster
		sta	<__bp + 1
;		bra	f32_use_cluster

		;

f32_use_cluster:ldy	#3			; Copy the cluster # from the
.copy:		lda	[__bp],y		; pointer in __bp.
		and	f32_cluster_msk,y
		sta	f32_cur_cluster,y
		sta	f32_sector_num,y
		dey
		bpl	.copy

		ldx	#$FC			; Cluster # == EOC?
		sec
.compare_eoc:	lda	f32_sector_num  - $FC,x
		sbc	f32_cluster_eoc - $FC,x
		inx
		bne	.compare_eoc
		bcs	.eoc_cluster

		ldx	#$FC			; Subtract 2 from cluster #.
		clc
		lda	#$FE			
.subtract:	adc	f32_sector_num  - $FC,x
		sta	f32_sector_num  - $FC,x
		lda	#$FF
		inx
		bne	.subtract
		bcc	.bad_cluster

		ldx	#$FC			; Cluster # too big?
		sec
.compare_bad:	lda	f32_sector_num  - $FC,x
		sbc	f32_cluster_cnt - $FC,x
		inx
		bne	.compare_bad
		bcs	.bad_cluster

		ldy	f32_sec2cls_rot		; f32_sector_num =
		beq	.add_long               ; f32_cur_cluster * f32_sec2cls.
.rotate_long:	asl	f32_sector_num + 0
		rol	f32_sector_num + 1
		rol	f32_sector_num + 2
		rol	f32_sector_num + 3
		dey
		bne	.rotate_long

.add_long:	ldx	#$FC			; f32_sector_num =
		clc				; f32_sector_num + f32_data_begins.
.add_byte:	lda	f32_data_begins - $FC,x
		adc	f32_sector_num  - $FC,x
		sta	f32_sector_num  - $FC,x
		inx
		bne	.add_byte

		stz	f32_cluster_idx		; Reset sector idx within cluster.

		ldx	#F32_OK
		rts		

.eoc_cluster:	ldx	#F32_EOC_CLUSTER	; Invalid cluster.
		rts		

.bad_cluster:	ldx	#F32_ERR_INVALID	; Invalid cluster.
		rts		



; ****************************************************************************
; ****************************************************************************
;
; f32_set_cluster - Set the cluster from the directory entry ptr in __bp.
;
; Uses __bp = Pointer to directory entry in cache.
;

f32_set_cluster:clx				; Copy the cluster # from the
		ldy	#DIR_FstClusLO          ; directory entry in __bp.
.copy_word:	lda	[__bp],y
		sta	f32_cur_cluster,x
		inx
		iny
		lda	[__bp],y
		sta	f32_cur_cluster,x
		inx
		ldy	#DIR_FstClusHI
		cpx	#4
		bne	.copy_word
		rts



; ****************************************************************************
; ****************************************************************************
;
; f32_1st_entry - Get the 1st short entry in the current directory.
; f32_nxt_entry - Get the next short entry in the current directory.
;
; N.B. This includes unused ($E5) and end-of-directory ($00) entries.
;
; Uses: __bp = Pointer to directory entry in cache.
; Uses: __dh = Temporary variable (trashed).
;
; Returns: X = F32_OK (and Z flag) or an error code.
;

f32_1st_entry:	jsr	f32_rewind_dir		; Goto 1st cluster in dir.
		bra	f32_get_entry

f32_nxt_entry:	clc				; Inc directory pointer.
		lda	<__bp + 0
		adc	#32
		sta	<__bp + 0
		lda	<__bp + 1
		adc	#0
		sta	<__bp + 1

		cmp	#>(f32_cache_buf + 512)	; Any entries left in cache?
		bne	f32_tst_entry

		jsr	f32_nxt_sector		; Increment the sector.
		bcc	f32_get_entry		; Still within the cluster?

		jsr	f32_nxt_cluster		; Increment the cluster.
		beq	f32_get_entry

		rts				; Return the error code.

		; Refresh the directory cache.

f32_get_entry:	ldx	#F32_ERR_MUTEX		; The f32_file_map shares space
		lda	f32_file_mutex		; with the f32_long_name, so
		bne	.error			; abort if a file is open.

		jsr	f32_load_cache		; Load a directory sector.
		beq	.loaded

.error:		rts				; Return the error code.

.loaded:	stz	<__bp + 0		; Reset directory pointer.
		lda	#>f32_cache_buf
		sta	<__bp + 1

		; Test the current directory entry.

f32_tst_entry:	lda	[__bp]			; End of Directory?
		beq	.no_long
		cmp	#$E5			; Empty entry?
		beq	.no_long

		ldy	#DIR_Attr		; Part of a long name?
		lda	[__bp],y
		and	#ATTR_Long_Mask
		cmp	#ATTR_Long_Name
		beq	.long_name

		;
		; Got a short-name entry.
		;

.short_name:	lda	f32_long_next		; Is there a long name?
		bmi	.no_long		; If no long name.
		bne	.no_long		; If long name not completed.

		cly				; Calc the short name's
		cla				; checksum.
.calc_csum:	lsr	a
		bcc	.skip_set_hi
		adc	#$7F
.skip_set_hi:	adc	[__bp],y
		iny
		cpy	#11
		bne	.calc_csum

		cmp	f32_long_csum		; Does it match the long name?
		beq	.got_long

.no_long:	lda	#$FF			; Signal no long name.
		sta	f32_long_next

		clx
.copy_name:	cly				; Copy the short name.
		lda	[__bp],y
		cmp	#$05			; SJIS??? Really???
		bne	.name_loop
		lda	#$E5			; Repair leading SJIS.
		bra	.sjis_name
.name_loop:	lda	[__bp],y
		cmp	#$20
		beq	.copy_extn
.sjis_name:	sta	f32_long_name,x
		inx
		iny
		cpy	#8
		bne	.name_loop

.copy_extn:	ldy	#8			; Copy the short extn.
		lda	[__bp],y
		cmp	#$20
		beq	.copy_done
		lda	#'.'
		sta	f32_long_name,x
		inx
.extn_loop:	lda	[__bp],y
		cmp	#$20
		beq	.copy_done
		sta	f32_long_name,x
		inx
		iny
		cpy	#11
		bne	.extn_loop

.copy_done:	stz	f32_long_name,x		; Terminate the string.
		stx	f32_name_length		; Save the name length.

.got_long:	ldx	#F32_OK			; Return OK, with Z.
		rts

		;
		;
		;

.bad_entry:	lda	#$FF			; Signal no long name.
		sta	f32_long_next

		stz	f32_name_length		; Reset the name length.

		jmp	f32_nxt_entry		; Bad long name!

		;
		; Got a long-name entry (with 13 UTF16 glyphs).
		;

.long_name:	lda	[__bp]			; Get the ORD#.
		tax
		ldy	#LDIR_Chksum

		bit	#FLAG_Last_Ord		; Begin a new long name?
		beq	.nxt_long_part

.new_long_name:	and	#FLAG_Last_Ord - 1	; Save which ORD# is next.
		sta	f32_long_next
		lda	[__bp],y		; Save short name checksum.
		sta	f32_long_csum

.nxt_long_part:	lda	[__bp],y		; Is the checksum consistent?
		cmp	f32_long_csum
		bne	.bad_entry

		txa				; Check ORD# value is 1..20.
		and	#FLAG_Last_Ord - 1
		beq	.bad_entry		; Reject ORD# == 0.
		cmp	#(255/13)+1+1
		bcs	.bad_entry		; Reject ORD# >= 256 glyphs.

		cmp	f32_long_next		; Is this ORD# in sequence?
		bne	.bad_entry
		dec	a			; First ORD# is 1, not 0.
		sta	f32_long_next		; Update next expected ORD#.

		clc				; Multiply by 13 to get the
		asl	a			; offset in the long name.
		adc	f32_long_next
		asl	a
		asl	a
		adc	f32_long_next
		tax

		ldy	#LDIR_Name1		; 1st block of 5 UTF16 glyphs.
		lda	#LDIR_Name1 + 10
		bsr	.copy_utf16		; N.B. May not return!

		ldy	#LDIR_Name2		; 2nd block of 6 UTF16 glyphs.
		lda	#LDIR_Name2 + 12
		bsr	.copy_utf16		; N.B. May not return!

		ldy	#LDIR_Name3		; 3rd block of 2 UTF16 glyphs.
		lda	#LDIR_Name3 +  4
		bsr	.copy_utf16		; N.B. May not return!

		bsr	.got_part		; N.B. Does not return!

.got_part:	lda	[__bp]			; Is this the last part of the
		bit	#FLAG_Last_Ord          ; long filename?
		beq	.next_part

		db	$89			; Code a BIT # instruction to
.too_long:	dex				; skip the dex.

		stz	f32_long_name,x		; Length may be multiple of 13.

.name_ends:	stx	f32_name_length		; Save the long name length.

.next_part:	pla				; Remove the return address.
		pla
		jmp	f32_nxt_entry		; Get the next part of it!

.copy_utf16:	sta	<__dh			; Copy UTF16 glyphs to the
.copy_loop:	lda	[__bp],y		; long name buffer.
		sta	f32_long_name,x
		iny
		asl	a
		lda	[__bp],y		; Get UTF16 hi-byte.
		bne	.replace_utf16		; Reject UTF16 $0100..$FFFF.

		if	1			; Remove for CP1252 accents.
		bcs	.replace_utf16		; Reject UTF16 $0080..$00FF.
		endif

.is_ascii:	ora	f32_long_name,x		; UTF16 zero terminator?
		beq	.name_ends
.copy_next:	iny
		inx
		beq	.too_long		; Is name > than 255 glyphs?
		cpy	<__dh
		bne	.copy_loop
		rts

.replace_utf16:	lda	#'?'			; Replace non-ASCII glyph.
		sta	f32_long_name,x
		bra	.copy_next



; ****************************************************************************
; ****************************************************************************
;
; f32_find_name - Locate a specifc named entry in the current directory.
;
; Args: __ax = Pointer to the name to search for.
; Uses: __bp = Pointer to directory entry in cache.
;
; This is a case-insensitive compare, just like on MS-DOS/Windows.
;
; UTF16 values have the following structure (in the region $0000..$00FF) ...
;
;   %000xxxxx ASCII illegal in a FAT32 name
;   %001xxxxx ASCII punctuation
;   %010xxxxx ASCII upper case
;   %011xxxxx ASCII lower case
;
;   %100xxxxx UTF16 illegal in a FAT32 name
;   %101xxxxx UTF16 punctuation         (equivalent to Microsoft CP-1252)
;   %110xxxxx UTF16 upper case accented (equivalent to Microsoft CP-1252)
;   %111xxxxx UTF16 lower case accented (equivalent to Microsoft CP-1252)
;

f32_find_name:	jsr	f32_1st_entry		; Start at the top of the dir.
		bra	.test_name

.next_name:	jsr	f32_nxt_entry		; Get the next directory entry.

.test_name:	bmi	.error			; Was there an error?

		lda	[__bp]			; Is this the end of the directory?
		beq	.not_found
		cmp	#$E5			; Is this an empty entry?
		beq	.next_name

.str_test:	cly				; Start comparing the names.
		bra	.chr_test

.chr_loop:	iny				; Assume same if > 256 chrs.
		beq	.str_same

.chr_test:	lda	[__ax],y		; End of name?
		beq	.chr_last
		bmi	.next_name		; Fail if UTF16 $80..$FF glyph.

		eor	f32_long_name,y		; Are both chrs the same?
		beq	.chr_loop

		and	#%11011111		; Do they differ by exactly 32?
		bne	.next_name		; Only in $40..$7F or $C0..$FF.

		if	1

		lda	f32_long_name,y		; Compare case in ASCII range.
		and	#%00011111		; Reject if == $40 or $60.
		beq	.next_name
		cmp	#%00011011		; A..Z a..z  < $5B or $7B.
		bcc	.chr_loop
		bra	.next_name

		else

		lda	f32_long_name,y		; Compare in UTF16 $00..$FF.
		and	#%10011111		; Reject if == $40 or $60.
		beq	.next_name
		cmp	#%00011011		; A..Z a..z  < $5B or $7B.
		bcc	.chr_loop
		and	#%10010111		; Reject if  < $C0.
		bpl	.next_name		
		cmp	#%10010111		; Reject if == $D7 or $DF.
		beq	.next_name		; Reject if == $F7 or $FF.
		bra	.chr_loop

		endif

.chr_last:	cmp	f32_long_name,y		; Make sure that both strings
		bne	.next_name		; end at the same point!

.str_same:	ldx	#F32_OK
		rts
		
.not_found:	ldx	#F32_ERR_NO_NAME	; Can't find the named entry!
.error:		rts



; ****************************************************************************
; ****************************************************************************
;
; f32_map_file - Create a list of contiguous sector fragments in the file.
;
; Uses: f32_file_map = 256-byte data buffer for the file map (PAGE_ALIGNED).
;
; Returns: X = F32_OK (and Z flag) or an error code.
;
; Each entry in the list is ...
;
;   4-bytes Sector Number (zero marks the end-of-file)
;   4-bytes Sector Count
;
; There can be a maximum of 31 fragments in the 256-bytes of f32_file_map.
;

f32_map_file:	jsr	f32_rewind_file		; Start at the beginning.
		bne	.failed

		stz	<__di + 0		; Page-aligned map.
		lda	#>f32_file_map
		sta	<__di + 1

.copy_cluster:	cly				; Save f32_sector_num and
.copy_byte:	lda	f32_cur_cluster,y	; remember f32_cur_cluster.
		sta	__ax,y
		lda	f32_sector_num,y
		sta	[__di],y
		iny
		cpy	#4
		bne	.copy_byte

		lda	f32_sec2cls_cnt		; Initialize fragment length.
		sta	[__di],y
		iny
		cla
		sta	[__di],y
		iny
		sta	[__di],y
		iny
		sta	[__di],y

.next_cluster:	jsr	f32_nxt_cluster		; Find the next cluster in the
		beq	.sub_long		; file.

		cpx	#F32_EOC_CLUSTER	; EOC cluster?
		bne	.failed

		clc				; Mark the end of the file map.
		lda	<__di + 0
		adc	#8
		sta	<__di + 0
		beq	.too_fragged
		ldy	#7			
		cla
.end_of_map:	sta	[__di],y
		dey
		bpl	.end_of_map

		jsr	f32_rewind_file		; Rewind to the beginning.

		ldx	#F32_OK
.failed:	rts

.sub_long:	ldx	#$FC			; Subtract current and previous
		sec				; cluster numbers.
.sub_byte:	lda	f32_cur_cluster - $FC,x
		tay
		sbc	<(__ax - $FC) & 255,x
		sta	<(__cx - $FC) & 255,x
		sty	<(__ax - $FC) & 255,x
		inx
		bne	.sub_byte

		lda	<__cx + 0		; Do they differ by 1?
		dec	a
		ora	<__cx + 1
		ora	<__cx + 2
		ora	<__cx + 3
		bne	.next_frag

.same_frag:	lda	f32_sec2cls_cnt		; Increment the length of the
		clc				; fragment.
		ldy	#4
.add_loop:	adc	[__di],y
		sta	[__di],y
		bne	.next_cluster
		iny
		cla
		bra	.add_loop

.next_frag:	clc				; Start a new fragment.
		lda	<__di + 0
		adc	#8
		sta	<__di + 0
		bne	.copy_cluster

.too_fragged:	ldx	#F32_ERR_FRAGGED	; Too many fragments!
		rts



; ****************************************************************************
; ****************************************************************************
;
; f32_open_file - Open the file in the directory entry ptr in __bp.
;
; Args: __bp = Pointer to directory entry in cache.
;
; Returns: X = F32_OK (and Z flag) or an error code.
;
; Uses: f32_file_map = Data buffer containing the file map.
; Uses: f32_file_pos = Current fragment within the file map.
;

f32_open_file:	ldx	#F32_ERR_MUTEX		; Only allow one file to
		lda	f32_file_mutex		; be open at once.
		bne	.finished

		lda	[__bp]			; End of directory?
		beq	.not_file
		cmp	#$E5                    ; Empty entry?
		beq	.not_file

		ldy	#DIR_Attr		; Is this a file?
		lda	[__bp],y
		and	#ATTR_Type_Mask
		beq	.got_file

.not_file:	ldx	#F32_ERR_INVALID
		rts

.got_file:	ldy	#DIR_FileSize		; Save the file length.
		ldx	#$FC			
.copy_length:	lda	[__bp],y
		iny
		sta	f32_file_length - $FC,x
		inx
		bne	.copy_length

		jsr	f32_set_cluster		; From cur directory entry.

		tii	f32_cur_cluster, f32_fil_cluster, 4

.map_file:	jsr	f32_map_file		; Map the file fragments.
		bne	.finished

		dec	f32_file_mutex		; Signal that a file is open.

		stz	<__ax + 0		; Seek to the beginning
		stz	<__ax + 1		; of the file.
		stz	<__ax + 2
		stz	<__ax + 3
		jsr	f32_seek_set
		bne	.finished

.finished:	rts

f32_file_chosen	=	.map_file		; Shortcut for loading HuCard.



; ****************************************************************************
; ****************************************************************************
;
; f32_close_file - Close the current file.
;
; Returns: A,X,Y = preserved (and N,Z flags), unless closing generates an error.
;

f32_close_file:	stz	f32_file_mutex		; Release the mutex.
		cpx	#$00			; Set the N & Z return flags.
		rts



; ****************************************************************************
; ****************************************************************************
;
; f32_seek_set - Seek a # of sectors from the beginning of the file.
; f32_seek_cur - Seek a # of sectors forwards from the current file position.
;
; Args: __ax = lo-word of unsigned 32-bit # of 512-byte sectors to seek.
; Args: __bx = hi-word of unsigned 32-bit # of 512-byte sectors to seek.
;
; Uses: f32_file_map = Data buffer containing the file map.
; Uses: f32_file_pos = Current fragment within the file map.
;
; Returns: X = F32_OK (and Z flag) or an error code.
;

f32_seek_set:	stz	f32_next_frag + 1	; Start at the beginning of
		lda	#>f32_file_map		; the fragment map.
		sta	f32_next_frag + 2

		jsr	f32_next_frag		; Get the 1st fragment.

f32_seek_cur:	lda	f32_file_mutex		; Is there a file open?
		beq	.at_eof

		lda	f32_file_pos + 0	; Are we already at the EOF?
		ora	f32_file_pos + 1
		ora	f32_file_pos + 2
		ora	f32_file_pos + 3
		beq	.at_eof

		ldx	#$FC			; seek_nxt = seek_len - frag_len
		sec
.test_size:	lda	<((__ax - $FC) & 255),x
		sbc	f32_file_pos + 4 - $FC,x
		pha
		inx
		bne	.test_size
		bcc	.this_frag		; Is frag_len > seek_len?

		; frag_len <= seek_len

.next_frag:	pla				; seek_len = seek_nxt
		sta	<__ax + 3
		pla
		sta	<__ax + 2
		pla
		sta	<__ax + 1
		pla
		sta	<__ax + 0

		bsr	f32_next_frag		; Move forward to next fragment.
		bra	f32_seek_cur		; Try again.

		; frag_len >  seek_len

.this_frag:	pla				; Throw away seek_nxt.
		pla
		pla
		pla

		ldx	#$FC			; frag_1st += seek_len
		clc
.frag_1st:	lda	f32_file_pos + 0 - $FC,x
		adc	<((__ax - $FC) & 255),x
		sta	f32_file_pos + 0 - $FC,x
		inx
		bne	.frag_1st

		ldx	#$FC			; frag_len -= seek_len
		sec
.frag_len:	lda	f32_file_pos + 4 - $FC,x
		sbc	<((__ax - $FC) & 255),x
		stz	<((__ax - $FC) & 255),x
		sta	f32_file_pos + 4 - $FC,x
		inx
		bne	.frag_len

		ldx	#F32_OK			; Success!
		rts

.at_eof:	ldx	#F32_ERR_EOF		; Read beyond EOF!
		rts

		;

f32_next_frag:	tii	f32_file_map, f32_file_pos, 8

		lda	f32_next_frag + 1
		clc
		adc	#8
		sta	f32_next_frag + 1
		bcc	.done
		inc	f32_next_frag + 2

.done:		rts



; ****************************************************************************
; ****************************************************************************
;
; f32_file_read  - Load a # of sectors from the current file position.
; f32_file_write - Save a # of sectors to the current file position.
;
; Args: sdc_data_bank
; Args: sdc_data_addr
; Args: __ax         = unsigned 16-bit # of blocks to read/write.
;
; Uses: f32_file_map = Data buffer containing the file map.
; Uses: f32_file_pos = Current fragment within the file map.
;
; Returns: X = F32_OK (and Z flag) or an error code.
;

		;

f32_file_read:	tii	.load, f32_xfer_call, 3	; Self-Modify the xfer code.
		bra	f32_file_xfer
.load:		jsr	sdc_read_data		; Low level function for xfer.

		;

f32_file_write:	tii	.save, f32_xfer_call, 3	; Self-Modify the xfer code.
		bra	f32_file_xfer
.save:		jsr	sdc_write_data		; Low level function for xfer.

		;

f32_file_xfer:	lda	f32_file_mutex		; Is there a file open?
		beq	.at_eof

		lda	f32_file_pos + 0	; Are we already at the EOF?
		ora	f32_file_pos + 1
		ora	f32_file_pos + 2
		ora	f32_file_pos + 3
		beq	.at_eof

		stz	<__ax + 2		; Expand to a 32-bit value
		stz	<__ax + 3		; to keep the math clean.

		ldx	#$FC			; Copy fragment's block #.
		clc
.copy_block_num:lda	f32_file_pos + 0 - $FC,x
		sta	sdc_block_num - $FC,x
		adc	<((__ax - $FC) & 255),x	; Add # of blocks to transfer.
		sta	f32_file_pos + 0 - $FC,x; Next block in fragment.
		inx
		bne	.copy_block_num

		ldx	#$FC			; Copy fragment's block count.
		sec
.copy_block_cnt:lda	f32_file_pos + 4 - $FC,x
		sta	sdc_block_cnt - $FC,x
		sbc	<((__ax - $FC) & 255),x	; Sub # of blocks to transfer.
		sta	f32_file_pos + 4 - $FC,x; Next count in fragment.
		inx
		bne	.copy_block_cnt

		ldx	#$FC			; Subtract fragment size from
		sec				; xfer count.
.block_cnt_left:lda	<((__ax - $FC) & 255),x
		sbc	sdc_block_cnt - $FC,x
		sta	<((__ax - $FC) & 255),x
		inx
		bne	.block_cnt_left
		bcc	.last_xfer		; Fragment size > xfer size?

		jsr	f32_next_frag		; Prepare for next fragment.
		bra	.xfer_fragment		; Transfer entire fragment.

.last_xfer:	ldx	#$FC			; Just xfer the remaining tail
		clc				; of the xfer size.
.copy_last_cnt: lda	sdc_block_cnt - $FC,x
		adc	<((__ax - $FC) & 255),x
		sta	sdc_block_cnt - $FC,x
		stz	<((__ax - $FC) & 255),x
		inx
		bne	.copy_last_cnt

.xfer_fragment: jsr	.placeholder		; Xfer fragment (self-modifying).
		bne	.finished

		lda	<__ax + 0		; Transfer complete?
		ora	<__ax + 1
		bne	f32_file_xfer

.placeholder:	txa				; Set the N & Z return flags.

.finished:	rts				; Return the error code.

.at_eof:	ldx	#F32_ERR_EOF		; Read beyond EOF!
		bra	.finished

f32_xfer_call	=	.xfer_fragment

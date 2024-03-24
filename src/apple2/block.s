;******************************************
; block.s
;
; breakout for apple2
;
; copyright (c) 2023-24 yosi55@email.com
;
;******************************************

.debuginfo on
.listbytes unlimited
.feature c_comments

.include "apple2.inc"

;ゼロページセグメント定義
;.cfgファイルで$50から自動採番する設定
.segment "ZEROPAGE"
;システム制御変数(ハイレゾ描写ルーチン)
vramX:       .res 1 ;VRAM表示Xポジション(0～39)
vramY:       .res 1 ;VRAM表示Yポジション(0～191)
pixL:        .res 1 ;ビットマップデータLowアドレス(VRAMアドレステーブルから算出する)
pixH:        .res 1 ;ビットマップデータhiアドレス(VRAMアドレステーブルから算出する)
pix_offset:  .res 1 ;ビットマップデータの横の位置(0〜255)
pix_width:   .res 1 ;描写するピクセルの幅(1～ byte単位)
pix_height:  .res 1 ;描写するピクセルの高さ(1〜)
strL:        .res 1 ;text_outで描写する文字列のlowアドレス
strH:        .res 1 ;text_outで描写する文字列のhiアドレス
text_xpos:   .res 1 ;NULL String文字列の描写X座標(0〜39)
text_ypos:   .res 1 ;NULL String文字列の描写Y座標(0〜191)
page:	     .res 1 ;表示ページ $20(page1) or $40(page2)

;アプリケーション変数
rpos_x:      .res 2 ;ラケットのX座標(0〜79) 1/2の値で座標計算・描写（表示/消去用の２バイト)
rpos_y:      .res 1 ;ラケットのY座標 固定値
bpos_x1:     .res 2 ;ボールのX座標1(VRAMアドレス 0〜39)（表示/消去用の２バイト）	
bpos_x2:     .res 2 ;ボールのX座標2(VRAMアドレス内の位置 0〜3)（表示/消去用の２バイト）
bpos_y:      .res 2 ;ボールのY座標（表示/消去用の２バイト）
b_vx:        .res 1 ;ボールのX座標ベクトル(-2〜2)
b_vy:        .res 1 ;ボールのY座標ベクトル(-2〜2)
game_state:  .res 1 ;ゲームの状態(0:スタート 1:通常プレイ 2:ミス 3:ゲームオーバー)
ball_wait:   .res 1 ;ボール移動時のウェイト 数字が大きいほど遅くなる
rkt_wait:    .res 1 ;ラケット移動時のウェイト 数字が大きいほど遅くなる
bw_init:     .res 1 ;ボールウェイトの初期値
rw_init:     .res 1 ;ラケットウェイトの初期値

bin_score:   .res 3 ;スコア(バイナリ　リトルエディアン)
ball_left:   .res 1 ;残りボール数(初期値は3)
seed:        .res 2 ; initialize 16-bit seed to any value except 0(乱数の種)
r_color:     .res 1 ;ラケットの描写色 0:ノーマル 1:リバース
loop_cnt:    .res 1 ;汎用内部ループ変数
z_temp:      .res 10;汎用バッファ

; 定数定義
HGR1SCRN   = $2000 ;ハイレゾページ１の開始アドレス
HGR2SCRN   = $4000 ;ハイレゾページ２の開始アドレス
MLI        = $BF00 ; Pro DOS API
GBASL      = $26
GBASH      = $27
HCOLOR1    = $1c
SPEAKER    = $C030
MON_BELL   = $FBE4
KEYIN      = $FD1B
MON_WAIT   = $FCA8	

; アプリパラメタ値
BALL_WAIT  = $2    ;ボール移動時のウェイト値。値が大きいほど遅い
; BALL_WAIT  = $0    ;ボール移動時のウェイト値。値が大きいほど遅い
RKT_WAIT   = $1    ;ラケット移動時のウェイト値。値が大きいほど遅い
; RKT_WAIT   = $0    ;ラケット移動時のウェイト値。値が大きいほど遅い

	
S_START    = 0
S_PLAY     = 1
S_MISS     = 2
S_END      = 3
	
;コードセグメント
.segment "CODE"
;***************************************
;
; メイン処理(プログラムエントリポイント)
;
;***************************************
.proc main
	jsr onece_init
	jsr init            ; 変数等の初期化

	bit KBDSTRB         ; clear keyboard

	bit TXTCLR          ; Turn off text, turn on Graphics
	bit MIXCLR          ; Turn off the bottom 4 lines of text
	bit LOWSCR          ; Activate Page1.  Use HISCR for Page2 but see page: init
	bit HIRES           ; Turn on Hires mode
	
	jsr opening_screen_draw	; オープニング画面描写(キーボード入力待ち)
	jsr KEYIN               ; モニターのキーボード入力を利用する（乱数シード値を更新したいため)

game_start:
	lda #S_PLAY
	sta game_state

	;1pageに描写
	jsr hclear		; ページクリア
	jsr game_screen_draw    ; ゲームメイン画面の描写
	jsr score_bin2ascii     ; 得点をASCII文字列変換
	jsr draw_score		; スコア文字列を画面表示
	jsr draw_leftball	; 残りボール数を画面表示

	lda #$40		; アクティブページを2pageに切替
	sta page
page2_init:
	jsr hclear		; ページクリア
	jsr game_screen_draw    ; ゲームメイン画面の描写
	jsr draw_score		; スコア文字列を画面表示
	jsr draw_leftball	; 残りボール数を画面表示
	
	lda #$20		; page1をアクティブに切替
	sta page
	
page1_init:
	jsr draw_racket		; ラケットを初期表示
	jsr draw_ball           ; ボールの初期表示
	jsr swap_page
	jsr draw_racket		; ラケットを初期表示
	jsr draw_ball           ; ボールの初期表示
main_loop:
	jsr draw_racket		; ラケット消去
	jsr draw_ball           ; ボール消去
	jsr swap_position	; 座標データの新旧入れ替え
	jsr apdat_bkup		; 新データのバックアップ

	jsr move_ball           ; ボールの移動
	jsr move_racket		; キーボード入力チェック、ラケットの移動・描写
	jsr draw_block		; ブロックの表示or消去

	lda game_state		; ゲームのステータスをロード
	cmp #S_PLAY		; ステータスが2(ボールが一番下まで来た?)
	beq draw

	lda ball_left           ; 残りボール数を-1
	sec
	sbc #1
	sta ball_left
	bne hit_miss            ; ボールの残数が0でない場合は、処理継続
game_over:
	lda #S_END              ; ゲームオーバー
	sta game_state
	jsr gameover
hit_miss:
	jsr miss_animation      ; ミスアニメーション
	jsr init                ; 変数等の初期化
	lda #S_PLAY
	sta game_state
	jmp game_start
draw:
	jsr draw_racket		; ラケットを表示
	jsr draw_ball           ; ボールの表示

	jsr swap_visible_page

	jsr swap_page           ; ページ切り替え
	jsr swap_position	; 座標入れ替え

	jmp main_loop           ; キーボード入力チェックを繰り返す

.endproc

;****************************************
;
; ハイレゾ画面の切替
;
;****************************************
.proc swap_visible_page
	lda page
	cmp #$20
	bne page2
page1:
	bit LOWSCR
	jmp :+
page2:	
	bit HISCR
:	
	rts
.endproc

;****************************************
;
; アプリケーション座標のバックアップ
; ダブルバッファリングを実装するため
; ボールとラケットの座標をバックアップ
;
;****************************************
.proc apdat_bkup
	lda rpos_x
	sta rpos_x+1
	lda bpos_x1
	sta bpos_x1+1
	lda bpos_x2
	sta bpos_x2+1
	lda bpos_y
	sta bpos_y+1
	rts
.endproc

;****************************************
;
; hiresページのスワップ
;
;****************************************
.proc swap_page
	lda page            ;現在のページをロード($20 or $40)
	eor #$60	    ;XORで反転($20->$40 or $40->$20)
	sta page	    ;反転結果をストア
	rts
.endproc
	
;****************************************
;
; ボール、ラケット座標／パターンを
; 旧→現にスワップする
;
;****************************************
.proc swap_position

	lda rpos_x
	pha
	lda rpos_x+1
	sta rpos_x
	pla
	sta rpos_x+1

	lda bpos_x1
	pha
	lda bpos_x1+1
	sta bpos_x1
	pla
	sta bpos_x1+1
	
	lda bpos_x2
	pha
	lda bpos_x2+1
	sta bpos_x2
	pla
	sta bpos_x2+1
	
	lda bpos_y
	pha
	lda bpos_y+1
	sta bpos_y
	pla
	sta bpos_y+1

	rts
.endproc
	
;****************************************
;
; 1回きりの初期化処理
;
;****************************************
.proc onece_init
	; 1回きりの初期化処理
	lda #$40
	sta page
	jsr hclear
	lda #$20
	sta page
	jsr hclear

	lda #0
	sta bin_score
	sta bin_score+1
	sta bin_score+2	        ;スコア初期化

	lda #3
	sta ball_left           ;残りのボール数をセット

	lda RNDL                ;乱数の種をセット
	bne :+			;0ではない場合、初期値をそのままセット
	clc			;0の場合は+1
	adc #1
:
	sta seed
	lda RNDH
	bne :+			;0ではない場合、初期値をそのままセット
	clc			;0の場合は+1
	adc #1
:
	sta seed+1

	rts
.endproc
	
;****************************************
;
; ゲームオーバー時のアニメーション+サウンド
;
;****************************************
.proc gameover
	;'GAME OVER'文字列の表示
	lda #<game_over
	sta strL
	lda #>game_over
	sta strH
	lda #100
	sta vramY
	lda #15
	sta vramX
	jsr text_out

	jsr miss_animation      ; ミスアニメーション

	ldx #$10		;
:
	lda #$f0
	jsr MON_WAIT
	dex
	bne :-
	
	jsr exit_game
.endproc

;****************************************
;
; ミスした時のアニメーション+サウンド
;
;****************************************
.proc miss_animation
	jsr swap_visible_page
	jsr draw_racket		; ラケットの消去
	ldy #$20		; delay値
	ldx #$10		; 鳴らす時間
	jsr playNote
	lda #$80                ; ウェイト値
	jsr MON_WAIT

	lda #1                  ; ラケットの描写色を反転(0:ノーマル 1:反転)
	sta r_color		; zero pageのフラグに格納
	jsr draw_racket		; ラケットの表示
	ldy #$20
	ldx #$10
	jsr playNote
	lda #$80                ; ウェイト値
	jsr MON_WAIT

	jsr draw_racket		; ラケットの消去
	ldy #$20
	ldx #$10
	jsr playNote
	lda #$80                ; ウェイト値
	jsr MON_WAIT

	jsr draw_racket		; ラケットの表示
	ldy #$20
	ldx #$10
	jsr playNote
	lda #$80                ; ウェイト値
	jsr MON_WAIT

	lda #0		        ; ラケットの描写色を反転(0:ノーマル 1:反転)
	sta r_color		; zero pageのフラグに格納
	
	rts
.endproc

;****************************************
;
; プレイ画面の描写
;
;****************************************
.proc game_screen_draw
	;縦線の描写
	lda #%10000101		;描写ビットマップパターンの設定
	ldy #0
	jsr vline

	lda #%10000101		;描写ビットマップパターンの設定
	ldy #30
	jsr vline

	;横線の描写
	lda #%01111111		;描写ビットマップパターンの設定
	ldy #$0
	jsr hline

	;'BLOCK'文字列の表示
	lda #<game_title
	sta strL
	lda #>game_title
	sta strH
	lda #0
	sta vramY
	lda #31
	sta vramX
	jsr text_out

	;'SCORE'文字列の表示
	lda #<score
	sta strL
	lda #>score
	sta strH
	lda #16
	sta vramY
	lda #31
	sta vramX

	jsr text_out

	;'LEFT'文字列の表示
	lda #<left
	sta strL
	lda #>left
	sta strH
	lda #32
	sta vramY
	lda #31
	sta vramX

	jsr text_out

	;ガイド1の表示
	lda #<GUIDE1
	sta strL
	lda #>GUIDE1
	sta strH
	lda #56
	sta vramY
	lda #31
	sta vramX

	jsr text_out

	;ガイド2の表示
	lda #<GUIDE2
	sta strL
	lda #>GUIDE2
	sta strH
	lda #64
	sta vramY
	lda #31
	sta vramX

	jsr text_out

	;ガイド3の表示
	lda #<GUIDE3
	sta strL
	lda #>GUIDE3
	sta strH
	lda #72
	sta vramY
	lda #31
	sta vramX

	jsr text_out

	;ガイド4の表示
	lda #<GUIDE4
	sta strL
	lda #>GUIDE4
	sta strH
	lda #80
	sta vramY
	lda #31
	sta vramX

	jsr text_out
	
	rts
.endproc

;****************************************
; 
; Beep音を鳴らす
;
;****************************************
.proc playBeep
	ldy #$25
	ldx #$08
	jsr playNote

	rts
.endproc

;****************************************
; 
; スピーカを鳴らす（パラメータ付き）
; Yレジスタ delay値
; Xレジスタ 鳴らす時間
;
;****************************************
.proc playNote

    sty loop_cnt ;delay値を保存

loop:
    lda SPEAKER
    ldy loop_cnt
:
    nop 
    nop 
    nop 
    nop 
    dey 
    bne :-                                      ; hold for the duration in y
    dex 
    bne loop                                    ; retrigger
    
    rts 
.endproc 


;****************************************
;
; 初期画面の描写
;
;****************************************
.proc opening_screen_draw
	;'B L O C K'文字列の表示
	lda #<game_title
	sta strL
	lda #>game_title
	sta strH
	lda #15
	sta vramY
	lda #18
	sta vramX

	jsr text_out

	;'HIT ANY KEY'文字列の表示
	lda #<hit_anykey
	sta strL
	lda #>hit_anykey
	sta strH
	lda #80
	sta vramY
	lda #17
	sta vramX

	jsr text_out

	;'(C) 2024 YOSI55@EMAILL.COM'文字列の表示
	lda #<CP
	sta strL
	lda #>CP
	sta strH
	lda #160
	sta vramY
	lda #10
	sta vramX

	jsr text_out

	rts
.endproc

;****************************************
; 横線の描写
;
; A = color byte to repeat, e.g., $7F
; Y = row (0-191) ($FF on exit)
;
; Uses GBASL, GBASH
;****************************************
.proc hline
	pha
	lda rowL,y
	sta GBASL
	lda page             ; set HGR Page 1($20)
	;lda #$20             ; set HGR Page 1($20)
	clc
	adc rowH,y
	sta GBASH
	ldy #35	             ; Width of screen in bytes
	pla
hl1:	sta (GBASL),y
	dey
	bpl hl1

	rts
.endproc

;****************************************
; 縦線の描写
;
; A = byte to write in each position
; Y = column
;
; Uses GBASL, GBASH, HCOLOR1
;
;****************************************
.proc vline
	sta   HCOLOR1
	ldx   #179           ; Start at second-to-last row
vl1:    lda   rowL,x         ; Get the row address
	sta   GBASL
	;lda   #$20           ; set HGR Page 1($20)
	lda   page           ; set HGR Page 1($20)
	clc
	adc   rowH,x
	sta   GBASH
	lda   HCOLOR1
	sta   (GBASL),y      ; Write the color byte
	dex                  ; Previous row
	bne   vl1

	rts
.endproc

;****************************************
; 初期化処理
; 各変数の初期化を行う
;****************************************
.proc init
	lda #0
	sta loop_cnt
	
	sta bpos_x1
	sta bpos_x1+1
	sta bpos_x2
	sta bpos_x2+1
	sta game_state
	sta r_color

	lda #$20
	sta page       ;ハイレゾページ0($20)
	
	lda #40	       ;ボールのY座標
	sta bpos_y
	sta bpos_y+1
	lda #1         ;ボールのX方向のベクトル値(1)
	sta b_vx
	lda #5        ;ボールのY方向のベクトル値(5)
	;lda #3	      ;ボールのY方向のベクトル値(3)
	;この値にするとボールの当たり判定が誤動作する要チェック
	;ボールが丈夫に移動した際、ご動作しているためY座標が-(マイナス)値に
	;なった場合の値の補正/考慮ができていないことが原因だと思われる。
	sta b_vy
	lda #12
	sta rpos_x     ;ラケットのX座標
	sta rpos_x+1

	;ボールのX座標をランダム値を設定
	jsr ball_xpos_init
	
	lda #180
	sta rpos_y     ;ラケットのY座標

	lda #BALL_WAIT
	sta ball_wait  ;ボール移動時のウェイト値

	lda #RKT_WAIT
	sta rkt_wait  ;ボール移動時のウェイト値

	bit KBDSTRB             ; キーボード入力をクリアする
	
	rts
.endproc
	
;****************************************
;
; ボールの初期X座標を算出する
;
;****************************************
.proc ball_xpos_init
	jsr prng               ;乱数生成(0〜255 -> Aレジスタ)

	and #$0f               ;4bitでマスク(0〜16)
	
	sta bpos_x1
	sta bpos_x1+1

	lda #0
	sta bpos_x2
	sta bpos_x2+1

	rts
.endproc

;*******************************************************************************
; prng(乱数生成)
;
; A（0-255）にランダムな8ビットの数を返し、Y（0）を破壊します。
;
; "seed"と呼ばれるゼロページ上の2バイトの値が必要です。
; 最初のprng呼び出しの前に、seedを0以外の任意の値で初期化してください。
; （seed値が0の場合、prngは常に0を返します。）
;
; これは、多項式$0039を持つ16ビットGalois線形フィードバックシフトレジスタです。
; 生成される数列は65535回の呼び出し後に繰り返されます。
;
; 実行時間は平均で125サイクルです（jsrとrtsを除く）。
;*******************************************************************************
.proc prng
	ldy #8     ; iteration count (generates 8 bits)
	lda seed+0
:
	asl        ; shift the register
	rol seed+1
	bcc :+
	eor #$39   ; apply XOR feedback whenever a 1 bit is shifted out
:
	dey
	bne :--
	sta seed+0
	cmp #0     ; reload flags

	rts
.endproc

;****************************************
;
; ゲームスコアのバイナリ→ASCII変換
; todo:
; 変換対象が255を超えるとascii表示がおかしくなる
;
;****************************************
.proc score_bin2ascii
	; 元のスコアをスタックに退避
	lda bin_score
	pha
	lda bin_score+1
	pha
	lda bin_score+2
	pha

	ldx #0            ;引き算した回数(X)を0クリア
	stx loop_cnt	  ;ASCIIスコア文字列の桁数オフセットを0クリア
	ldy #0		  ;スコアの割る数テーブル(3 x 6 = 18バイト 0〜17)のインデックス初期値を設定
compare:	
	;割られる数と割る数の大小比較比較
	lda bin_score+2  ; 割る数-割られる数の大小比較
	cmp asc_tbl+2,y  ; 割る数の最上位バイトをロード
	beq :+		 ; 同値であれば、次の桁をチェック
	bcc exit_loop	 ; 割られる数 < 割る数 であれば、比較終了
	bcs substruct    ; 割られる数 > 割る数 であれば、即時引き算実行
:	
	lda bin_score+1
	cmp asc_tbl+1,y
	beq :+
	bcc exit_loop
	bcs substruct
:	
	lda bin_score
	cmp asc_tbl,y
	bcs substruct
	jmp exit_loop
substruct:
	;引き算実行
	sec			; 引き算するためキャリーフラグをセット
	lda bin_score		; 割られる数をロード
	sbc asc_tbl,y		; 割る数で引き算
	sta bin_score		; 引いた数をメモリにストア
	lda bin_score+1		; 以降、２バイト分続ける
	sbc asc_tbl+1,y
	sta bin_score+1
	lda bin_score+2
	sbc asc_tbl+2,y
	sta bin_score+2

	inc loop_cnt		;割った数+1

	jmp compare		;繰り返す
exit_loop:
	lda loop_cnt		;割った数をAにセット
	clc			;足し算するのでキャリーフラグをクリア
	adc #$30		;ASCII'0'($30)+カウンタ
	sta asc_score,x		;asc_score+xにASCII文字を格納
	inx			;ASCII桁数(X)+1
	lda #0			;割った数を0クリア
	sta loop_cnt		;格納

	tya			;Y->A
	clc
	adc #3			;A=A+3(割る値のバイト長)
	tay			;A->Y

	cpx #6			;すべての桁を計算した?(X == 6?)
	bne compare		;していない場合は、引き算を繰り返す

	pla                ;スタックに退避していたバイナリスコアを復元
	sta bin_score+2
	pla
	sta bin_score+1
	pla
	sta bin_score

	rts
.endproc

;****************************************
; ゲームスコア加算
;****************************************
.proc add_score
	lda bin_score
	clc
	adc #10	;得点+10
	sta bin_score
	lda bin_score+1
	adc #0
	sta bin_score+1
	lda bin_score+2
	adc #0
	sta bin_score+2

	rts
.endproc
	
;****************************************
; スコアの画面表示
;****************************************
.proc draw_score
	lda #<asc_score
	sta strL
	lda #>asc_score
	sta strH

	lda #24
	sta vramY
	lda #31
	sta vramX

	jsr text_out
	jsr swap_page           ; ページ切り替え

	lda #<asc_score
	sta strL
	lda #>asc_score
	sta strH

	lda #24
	sta vramY
	lda #31
	sta vramX
	jsr text_out
	jsr swap_page           ; ページ切り替え
	
	rts
.endproc

;****************************************
; 残りボール数の画面表示
;****************************************
.proc draw_leftball

	; 残りボール数の計算
	lda ball_left
	clc
	adc #$30
	sta asc_left
	
	lda #<asc_left ;lowアドレス取得
	sta strL       ;取得したアドレスを設定(low)
	lda #>asc_left ;highアドレス取得
	sta strH       ;取得したアドレスを設定(high)

	lda #32	       ;Y座標
	sta vramY      ;Y座標設定
	lda #36	       ;X座標
	sta vramX      ;X座標設定

	jsr text_out
	
	rts
.endproc

;***********************************************
; ラケットの移動
; キーボード入力有無をチェックし、入力されていたら
; ラケットの新しい座標を計算し描写する
;***********************************************
.proc move_racket
	;ボール移動時のウェイト値のチェック
	lda rkt_wait
	beq :+
	sec
	sbc #1
	sta rkt_wait
	rts
:
	lda #RKT_WAIT
	sta rkt_wait
				; キー入力スキャン
	lda KBD                 ; キーボード入力チェック 入力キー -> Aレジスタ
	bmi check_code          ; キーボード入力があった？
	rts                     ; キー入力がなければリターン

check_code:
;	bit KBDSTRB             ; キーボード入力をクリアする
	and #$5f                ; MSBをストリップ かつ 小文字→大文字

	cmp #'A'                ; 'A'左移動キー?
	beq left
	cmp #'D'                ; 'D'右移動キー?
	beq right
	cmp #'Q'                ; 'Q'ゲーム終了?
	beq quit
	cmp #' '                ; ' 'ラケット移動停止?
	bne :+
	
	bit KBDSTRB             ; キーボード入力をクリアする
:
	rts
left:
	lda rpos_x              ; ラケットX座標をロード
	cmp #0
	bne :+                  ; X座標が0でなければX座標を更新
	rts                     ; X座標が0の場合は何もせず復帰
:
	lda rpos_x
	sec                     ; キャリーフラグをセット
	sbc #1                  ; A = A - 1
	sta rpos_x              ; rpos_x = A

	rts

right:
	lda rpos_x              ; ラケットX座標をロード
	cmp #48                 ; X座標と48を比較
	bne :+                  ; X座標が48より小さい場合は、座標更新
	rts                     ; X座標が48であればリターン
:
	lda rpos_x
	clc                     ; キャリーフラグをクリア
	adc #1                  ; A = A + 1
	sta rpos_x              ; rpos_x = A

	rts
quit:                           ; プログラム終了(DOSへ復帰)
	jsr exit_game
.endproc

;****************************************
;
; ゲーム終了ルーチン
; DOS APIをコールしてDOSに戻る（終了）
;
;****************************************
.proc exit_game
	bit     TXTSET          ; turn text mode back on
	bit     LOWSCR          ; Page1 memory active
	bit     KBDSTRB         ; clear the key that was pressed
	jsr     MLI             ; Call the ProDOS API to quit this app
	.byte   $65             ; Quit
	.addr   * + 2           ; Parameter block follows this address
	.byte   4               ; 4 parameters
	.byte   0               ; all 4 are 0 (reserved)
	.word   0000
	.byte   0
	.word   0000
options: .byte "12TELSQ"
optionsEnd:
.endproc

;****************************************
; ブロックの表示
;
; アルゴリズム
; ブロックデータの状態データを取得する
; 状態データで、存在ビットをチェック。1の場合は
; 描写or消去処理を継続する。0の場合は、ブロックが
; 消滅しているので、処理をスキップする。
;
; 次に描写ビットをチェックする。
; HGRの各ページが0の場合は、ビットマップを描写する。
; アクティブページに描写した場合、当該ページの
; ビットに1を立てる。
; 
; 次に消去ビットをチェックする。
; HGRの各ページが1の場合は、ビットマップを描写(消去)する。
; アクティブページに描写した場合、当該ページの
; ビットに0を立てる。
; すべてのページビットが0になった場合、ブロックデータ
; の状態データビットを0にする。
;
;****************************************
.proc draw_block
	total_blks = z_temp      ;合計ブロック数
	
	lda b_data1_cnt	         ;データの個数を取得
	sta total_blks		 ;データ個数をストア
	ldy #0			 ;ループカウンタを0で初期化
	sty loop_cnt		 ;ループカウンタ変数に格納
loop:
	lda b_data1,y		 ;ブロックの状態を取得
	and #$80		 ;ビット状態をマスク
	cmp #$80		 ;状態ビット(8bit)をチェック
	beq draw_check		 ;状態ビットが1の場合は描写する
	jmp next_blk_up		 ;状態ビットが0の場合は描写（消去）する
draw_check:	
	lda b_data1,y		 ;ブロックの状態を取得
	and #$40		 ;描写ビットをマスク
	cmp #$40		 ;描写ビットが立っている？
	beq :+
	jmp next_blk_up
:	
	lda page		 ;アクティブページを取得
	cmp #$20
	bne p2_chg
p1_chg:
	lda b_data1,y
	eor #$20
	sta b_data1,y
	jmp st_chk
p2_chg:	
	lda b_data1,y
	eor #$10
	sta b_data1,y
st_chk:
	lda b_data1,y		 ;ブロックの状態を取得
	and #$30		 ;ビット5と4をマスク
	cmp #$30		 ;両ページともビットが1(描写済み)?
	beq drawbit_off
	cmp #$00		 ;両ページともビットが0(消去済み)?
	beq exitbit_off
	jmp draw_sp
drawbit_off:
	lda b_data1,y
	and #$bf
	sta b_data1,y
	jmp draw_sp
exitbit_off:
	lda b_data1,y
	and #$7f
	sta b_data1,y
draw_sp:	
	lda b_data1+1,y	         ;ブロックのX座標を取得
	sta vramX

	sty loop_cnt
	lda b_data1+3,y		;Y座標値取得
	sta vramY

	lda #<blk_pat1		;描写データセット
	sta pixL
	lda #>blk_pat1
	sta pixH

	lda b_data1+2,y		;描写データの幅セット
	sta pix_width
	lda b_data1+4,y		;描写データの高さセット
	sta pix_height
	
	jsr draw_sprite		;ビットマップ描写
next_blk_up:
	ldy loop_cnt
	iny
	iny
	iny
	iny
	iny
	sty loop_cnt

	cpy total_blks
	beq :+

	jmp loop
:	
	rts
.endproc
	
;****************************************
; ラケットの表示
; 指定されたzeroページの座標をもとに
; VRAMにXOR描写する
;****************************************
.proc draw_racket
	; 画面の描写位置設定
	lda rpos_y
	sta vramY ;Y座標の設定
	;X座標が奇数 or 偶数 チェック
	and #%1          ;MSBが1?
	beq odd          ;Yes 奇数

even:
	;X座標を1/2にスケールダウン
	lda rpos_x
	lsr
	sta vramX

	and #%1	          ;MSBが1?
	beq odd_pattern   ;Yes 奇数

	lda r_color       ;ラケットの描写色設定をロード
	bne odd_pattern   ;0以外の場合は、反転色

even_pattern:	
	;偶数用ビットマップデータのアドレスセット
	lda #<pat1
	sta pixL
	lda #>pat1
	sta pixH
	jmp preparation

odd_pattern:
	lda r_color       ;ラケットの描写色設定をロード
	bne even_pattern  ;0以外の場合は、反転色
	;奇数用ビットマップデータのアドレスセット
	lda #<pat2
	sta pixL
	lda #>pat2
	sta pixH
	jmp preparation
odd:
	;X座標を1/2にスケールダウン
	lda rpos_x
	lsr
	sta vramX

	and #%1	          ;MSBが1?
	beq odd_pattern2  ;Yes 奇数

	lda r_color       ;ラケットの描写色設定をロード
	bne odd_pattern2  ;0以外の場合は、反転色
even_pattern2:
	;偶数用ビットマップデータのアドレスセット
	lda #<pat3
	sta pixL
	lda #>pat3
	sta pixH
	jmp preparation
odd_pattern2:
	lda r_color       ;ラケットの描写色設定をロード
	bne even_pattern2 ;0以外の場合は、反転色
	;奇数用ビットマップデータのアドレスセット
	lda #<pat4
	sta pixL
	lda #>pat4
	sta pixH
preparation:
	;描写データの幅、高さを設定
	lda #$6
	sta pix_width
	lda #$8
	sta pix_height
	
	jsr draw_sprite	;ビットマップ描写

	rts
.endproc

;****************************************
; ボールの表示
; 指定されたzeroページのボール座標をもとに
; VRAMにXOR描写する
; - ボールのビットマップデータは２バイトで構成されている
; - ボールのビットマップデータは４パターンで構成されている
;
; アルゴリズム
; ロードしたX座標が奇数か偶数か判定
; 奇数の場合は、描写元の奇数用ビットマップデータをVRAMに書き込む
; 偶数の場合は、描写元の偶数用ビットマップデータをVRAMに書き込む
; 奇数、偶数で条件分岐しているのはapple2のHI-RES制約をクリアするため
; ボールのX座標2(0〜3)をロード
; ボールのY座標をロード
; ボールの最終X座標を計算する
;
;****************************************
.proc draw_ball
	;ボールのX座標1(0〜39)をロード
	lda bpos_x1
	sta vramX
	;ボールのY座標をロード
	lda bpos_y
	sta vramY
	;描写するボールのパターン番号をロード
	lda bpos_x2
	cmp #1             ; A == 1?
	beq :+
	cmp #2             ; A == 2?
	beq :++
	cmp #3             ; A == 3?
	beq :+++

	; A = 0の場合
	lda #<BALL0
	sta pixL
	lda #>BALL0
	sta pixH
	jmp :++++
:
	; A = 1の場合
	lda #<BALL0
	clc
	adc #16            ; ビットマップを16バイトずらす
	sta pixL
	lda #>BALL0
	adc #0             ; 上位バイトのキャリーを足し込む
	sta pixH
	jmp :+++
:
	; A = 2の場合
	lda #<BALL0
	clc
	adc #32            ; ビットマップを32バイトずらす
	sta pixL
	lda #>BALL0
	adc #0             ; 上位バイトのキャリーを足し込む
	sta pixH
	;描写ビットマップデータのアドレス設定
	jmp :++
:
	; A = 3の場合
	lda #<BALL0
	clc
	adc #48            ; ビットマップを32バイトずらす
	sta pixL
	lda #>BALL0
	adc #0             ; 上位バイトのキャリーを足し込む
	sta pixH
	;描写ビットマップデータのアドレス設定
:
	lda #2
	sta pix_width
	lda #8
	sta pix_height

	jsr draw_sprite

	rts
.endproc

;****************************************
; ボールの座標移動
; ボールの移動方向と座標をもとにボールの位置を
; 更新する
; 壁にあたった場合は、反転する
; ラケットとの衝突判定は別ルーチン
;****************************************
.proc move_ball
	;ボール移動時のウェイト値のチェック
	lda ball_wait
	beq :+              ; ball_wait == 0 ?
	sec
	sbc #1
	sta ball_wait
	rts
:
	lda #BALL_WAIT      ; #BALL_WAIT -> ball_wait
	sta ball_wait
	;ブロック衝突判定
	jsr block_collison_detection ;ブロック衝突判定
	
	;X座標の未来座標の位置を計算
	lda bpos_x2             ;ボールのビットマップパターンをロード
	ldx #0                  ;0 -> X(ボールのビットマップパターン)
	clc                     ;キャリーフラグクリア
	adc b_vx                ;ボールのビットマップパターンを演算
	bmi :+                  ;演算結果がマイナスならばbpos_x2を3に設定
	cmp #3                  ;ビットマップパターン番号と3を比較
	bpl :++                 ;比較結果がプラス(3を超えていない)?
	jmp :+++		;新しいビットマップパターンをbpos_x2に保存
:
	lda #3                  ;3 -> A ボールのビットマップパターン
	ldx #1                  ;1 -> X
	jmp :++			;新しいX座標をbpos_x2に保存
:
	lda #0                  ;0 -> A ボールのビットマップパターン
	ldx #2                  ;2 -> X
:
	sta bpos_x2             ;A -> bpox_x2(ボールのビットマップパターン)

	cpx #0                  ;ビットマップパターンがオーバーフローしてる？
	beq :++++               ;X == 0の場合は、bpox_x1の値を更新せずリターン

	lda bpos_x1             ;ボールのVRAM上のX座標をロード
	clc                     ;キャリーフラグクリア(足し算するので…)
	adc b_vx                ;A = A + b_vx
	sta bpos_x1             ;bpos_x1 = A
	beq :+                  ;bpos_x1 == 0であればb_vx反転
	cmp #29                 ;bpos_x1 == 29?
	beq :+                  ;画面の一番右に来てても_vx反転
	jmp :++			;Y座標チェック
:                               ;Xベクトルを反転
	lda b_vx
	eor #$ff                ;ビット反転(1の補数)
	clc
	adc #1                  ;2の補数を算出(符号の反転)
	sta b_vx
	jsr playBeep            ;beep音を鳴らす
:
	;******************************
	;Y座標の未来座標の位置を計算
	;******************************
	lda b_vy		;Y軸のベクトル値を取得
	bmi top_check		;-(マイナス)?であれば、top_check
	jmp bottom_check	;でなければ、bottom_check

top_check:
	lda bpos_y              ;ボールのY座標 -> A
	cmp #5			;ボールのY座標と5を比較
	bcc adjust		;A < 5 ?であれば、演算結果がマイナスにならない調整
	clc			;キャリーフラグをクリア
	adc b_vy		;A + b_vy -> A
	sta bpos_y		;A -> bpos_y
	rts

adjust:
	lda #0                  ;Y座標の位置がマイナスのため0に修正
	sta bpos_y              ;Y座標値に格納
	jmp :+			;Y座標ベクトルを反転

bottom_check:
	lda bpos_y              ;ボールのY座標 -> A
	clc			;キャリーフラグをクリア
	adc b_vy		;A + b_vy -> A
	sta bpos_y		;A -> bpos_y
	cmp #175		;A(Y座標) - 175(底辺)
	bcc :++			;A < 175 -> rts
	
adjust2:
	;ラケットとの衝突判定
	lda #175	        ;調整値
	sta bpos_y	        ;ボールのY座標を補正・調整
	jsr collison_detection  ;ラケットとの衝突判定

	jmp :++			;rts

:	;Y座標ベクトルを反転
	lda b_vy                ;Yベクトルを反転
	eor #$ff                ;ビット反転(1の補数)
	clc
	adc #1                  ;1の補数+1=2の補数(符号の反転)
	sta b_vy
	jsr playBeep            ;beep音を鳴らす
:
	rts
.endproc

;****************************************
;
;ボールとブロックの当たり判定
;
;アルゴリズム(ロジック)
;ボールの未来位置を計算
;ボールの未来位置と、ブロックの座標を比較
;このとき、X座標とY座標それぞれの軸で比較
;ヒットした場合、ボールのY進行方向を逆転する。
;合わせて、ブロックの消去ビットを立てる
;すべてのブロックの座標を比較・演算する
;座標計算の最適化アルゴリズムとして
;モートン順序 というアルゴリズムがあるらしい
;演算処理を効率化できるアルゴリズムとのこと
;
;****************************************
.proc block_collison_detection
	total_blks = z_temp     ;合計のブロック数(ループ回数)
	f_bposx    = z_temp + 1	;未来のボールX座標
	blk_posx   = z_temp + 2 ;ブロックのX座標
	f_bposy    = z_temp + 3	;未来のボールY座標
	blk_posy   = z_temp + 4	;ブロックのY座標

	ldy #0                  ;ループカウンタを0をYレジスタにセット
	sty loop_cnt		;ループカウンタ変数を0で初期化
	lda b_data1_cnt		;合計のブロック個数をAレジスタにセット
	sta total_blks		;Aレジスタの値を合計ブロック変数にセット
calc_future_pos:                ;ボールの未来位置を計算
	lda bpos_x1		;現在のボールX座標をAレジスタにロード
	clc			;キャリーフラグをクリア
	adc b_vx		;ボールX座標 + ボールXベクトル(-1 or 1) -> Aレジスタ
	sta f_bposx             ;ボールの未来X座標を格納

	lda bpos_y              ;現在のボールY座標をAレジスタにロード
	clc			;キャリーフラグをクリア
	adc b_vy		;ボールY座標 + ボールYベクトル(-1 or 1) -> Aレジスタ
	sta f_bposy             ;ボールの未来Y座標を格納
x_detection:
	lda b_data1+1,y         ;ブロックのX座標を取得
;	asl			;ブロックのX座標 x 2(ボールのX座標と単位をそろえるため)
	sta blk_posx		;演算結果を一時領域に退避
	lda b_data1+2,y		;ブロックの幅を取得
	lsr			;幅を1/2に計算(中央値を求めるため)
	clc			;キャリーフラグクリア
	adc blk_posx            ;ブロックの幅(1/2) + ブロックのX座標
	sta blk_posx		;演算結果を格納

	lda f_bposx		;ボールのX座標値をロード
	sec
	sbc blk_posx	        ;ボールのX座標 - ブロックの中央値
	bpl :+			;演算結果がプラスならば判定処理へ
	eor #$ff		;マイナスならば、2の補数を取得(絶対数を求める)
	clc			;足し算をするのでキャリーフラグをクリア
	adc #1			;演算結果の絶対数(+の値)を求める
:
	cmp #$2		        ;差分が2?
	bcc y_detection		;差分 <= 2 であれば、Y座標のチェック
	jmp next_check		;差分が>2であれば、次のチェック

y_detection:
	lda b_data1+3,y         ;ブロックのY座標を取得
	sta blk_posy		;演算結果を一時領域に退避
	lda b_data1+4,y		;ブロックの高さを取得
	lsr			;高さを半分に
	clc
	adc blk_posy		;ブロックの高さ(1/2) + ブロックのY座標
	sta blk_posy
	
	lda f_bposy		;ボールのY座標値をロード
	clc
	adc #$4			;ボールの高さ(1/2)を加算
	sec			;キャリーフラグをセット
	sbc blk_posy		;ボールY座標 - ラケットY座標
	bpl :+			;減算結果が +(プラス) であれば差をチェック
	eor #$ff                ;マイナスならば、2の補数を取得(絶対数を求める)
	clc			;足し算をするのでキャリーフラグをクリア
	adc #1			;演算結果の絶対数(+の値)を求める
:	
	cmp #8			;ボールのY座標値 - ブロックのY座標の相対値が8かどうか比較
	bcc erase_block		;ボールのY座標値 <= ブロックのY座標 であれば、ブロック消去
	jmp next_check		;次のブロックチェック

erase_block:
	lda b_data1,y           ;ブロックの状態データを取得
	ora #$40		;描写ビットを立てる
	sta b_data1,y           ;ブロックの状態データに格納

flip_yvec:			;ボールのYベクトル値反転
	lda b_vy		;ボールのYベクトル値をロード
	eor #$ff		;A XOR $ff(ビット反転)
	clc			;キャリーフラグクリア
	adc #1			;A = A + 1(２の補数を取得)
	sta b_vy		;演算結果をボールYベクトル変数に格納
	
next_check:
	ldy loop_cnt            ;Yレジスタの値をロード
	iny			;Yレジスタの値を+5(次のブロックデータへポインタを加算)
	iny
	iny
	iny
	iny
	sty loop_cnt
	cpy total_blks
	bne x_detection

	rts
.endproc

;****************************************
;ボールとラケットの当たり判定
;ロジック
;ラケットのX座標とボールのX座標を比較
;X座標の差分が0〜6(ラケットのXサイズ)である かつ
;ボールのY座標をチェックし、Y座標が画面の下部に到達している
;ラケットX座標 - ボールX座標
;
;****************************************
.proc collison_detection
	lda rpos_x
	tax			;rpos_x(オリジナル値)をXレジスタに退避
	lsr                     ;ラケットX座標を1/2
	sta rpos_x
	lda bpos_x1
	sec			;キャリーフラグセット
	sbc rpos_x		;ボールのVRAM上のX座標を減算  ボールX - ラケットX -> A
	
	cmp #6			;差分差6と比較
	bcs :+			; A >= 6 ? だとミス
	cmp #0                  ; A と 0を比較
	bcs :++			; A >= 0 ? だとラケットにヒット
:				; 0 > A or 6 < A miss
	; ラケットにヒットしなかった（ミス）
	txa			;Xレジスタに退避していたrpos_x(オリジナル値)を復元
	sta rpos_x
	lda #2
	sta game_state
	rts
:
	; ラケットにヒットした（加点）
	cmp #2			;check hit distance
	beq hit_center
	cmp #3			;check hit distance 
	beq hit_center
	jmp hit_nocenter
hit_center:			;hit center
	lda #5
	jmp reverse
hit_nocenter:			;hit no center
	lda #3
reverse:	
	sta b_vy

	txa			;Xレジスタに退避していたrpos_x(オリジナル値)を復元
	sta rpos_x
	lda b_vy                ;Yベクトルを反転
	eor #$ff                ;ビット反転(1の補数)
	clc
	adc #1                  ;1の補数+1=2の補数(符号の反転)
	sta b_vy

	jsr add_score           ;スコア加算

	jsr score_bin2ascii     ;スコアのbin->ascii変換
	jsr draw_score		;スコア表示
	jsr playBeep            ;beep音を鳴らす

	rts
.endproc

;****************************************
;draw_sprite ビットマップ表示
;
; 使い方
; ゼロページの次の領域にパラメータをセットしてから呼び出す
; vramX,vramY:
; 描写する位置を設定しておく(vramXは0〜39,vramYは0〜191)
; pixL,pixH:
; 描写したいビットマップデータのアドレスを設定しておく
; pix_width,pix_height:
; 描写したいビットマップデータの幅と高さを設定しておく
;
;****************************************
.proc draw_sprite
	lda vramY        ; vramY座標値をAレジスタにロード
	clc
	adc pix_height   ; vramY+pix_height->Aレジスタ
	sta pix_height   ; Aレジスタ->pix_height(Y座標のループ回数)

	ldx #0

	lda pixL         ; ビットマップデータのLowアドレスのロード
	sta cols + 1     ; 描写元データアドレスセット（自己書き換え）
	lda pixH         ; ビットマップデータのHighアドレスのロード
	sta cols + 2     ; 描写元データアドレスセット（自己書き換え）

	ldy vramY
rows:
	lda rowL, y      ; ハイレゾ画面のVRAMアドレス(low)を取得
	clc              ; 加算するためキャリーフラグをクリア
	adc vramX        ; 取得したアドレスに描写対象のX座標を加えて最終のアドレスを計算
	sta write + 1    ; 取得したアドレスを自己書き換え(low)
	sta write + 4    ; 取得したアドレスを自己書き換え(low)
	;lda #$20	 ; page1のアドレスを設定
	lda page	 ; page1のアドレスを設定
	adc rowH, y      ; ハイレゾ画面のVRAMアドレス(high)を取得
	sta write + 2    ; 取得したアドレスを自己書き換え(high)
	sta write + 5    ; 取得したアドレスを自己書き換え(high)

cols:
	lda $ffff, x     ; 書き込むピクセルデータ(1バイト分)を取得(自己書き換え)
write:
	eor $ffff, x     ; XOR(自己書き換え)
	sta $ffff, x     ; ビットマップデータを書き込む(自己書き換え)

	inx              ;X++
	cpx pix_width    ;Xレジスタの値とビットマップ幅を比較
	bne cols         ;指定されたビットマップの幅(7bit幅単位)描写した?

	ldx #0
	iny              ; Y座標 + 1
	cpy pix_height   ; Y座標がビットマップの高さ検査
	beq done         ; 一致?

	clc
	lda pix_width
	adc cols + 1
	sta cols + 1
	bcc rows
	inc cols + 2
	bne rows
done:
	rts
.endproc


; テキスト文字(NULL String)表示
; ハイレゾ画面にテキストを出力する
; vramX(ゼロページ) 0 - 39
; vramY(ゼロページ) 0 - 191
; 出力したい文字列は予めstrL,strHにアドレスを設定しておく
.proc text_out
	lda #0
	sta text_ypos
	sta pix_offset
char_loop:
	ldy #0        ;Yレジスタ0初期化
	lda (strL),y  ;描写対象の文字キャラクタを取得
	bne :+        ;NULL文字?
	rts           ;処理終了。復帰
:
	jsr set_font  ;描写フォントデータのセット。描写文字列はAレジスタに設定
	lda vramY
	sta text_ypos
loop:
	ldy text_ypos    ;ハイレゾ画面の縦位置を取得しYレジスタにセット
	lda rowL, y      ;ハイレゾ画面のVRAMアドレス(low)を取得
	adc vramX        ;取得したアドレスに描写対象のX座標を加えて最終のアドレスを計算
	sta write + 1    ;取得したアドレスを自己書き換え(low)
	;lda #$20	 ;page1のアドレスを設定
	lda page	 ;page1のアドレスを設定
	adc rowH, y      ;ハイレゾ画面のVRAMアドレス(high)を取得
	sta write + 2    ;取得したアドレスを自己書き換え(high)

	ldy pix_offset   ;ピクセルテーブルのオフセット値を取得
	lda (pixL),y     ;書き込むピクセルデータ(1バイト分)を取得
write:
	sta $ffff        ;ビットマップデータを書き込む

	;; ここからはオリジナルソース
	cpy #7          ;8ライン(1文字)書き込んだ?
	bcs next_char   ;次の文字へ
	inc text_ypos   ;描写するVRAMのY座標を+1
	inc pix_offset	;書き込むフォントデータを+1

	bne loop

next_char:
	inc vramX     ;描写位置X座標ををインクリメント
	inc strL      ;描写文字列のlowアドレスをインクリメント
	bne char_loop ;ページ長を超えた?
	inc strH      ;描写文字列のページをインクリメント
	bne char_loop
	rts
.endproc


;****************************************
; hclear ハイレゾ画面クリア
; page1 or 2 のページを0クリアする
;
;****************************************
.proc hclear
	lda page                        ;アクティブページをロード
	cmp #$40
	beq p2_clear			;pageが40だったらpage2へジャンプ

p1_clear:				;ページ1クリア
	lda #0                          ;0 -> A
	tax				;A(0) -> X
:
	.repeat $20, B
		sta HGR1SCRN+(B*256),x
	.endrep
	dex
	beq done
	jmp :-

p2_clear:                               ;ページ2クリア
	lda #0				;0 -> A
	tax				;A(0) -> X
:
	.repeat $20, B
		sta HGR2SCRN+(B*256),x
	.endrep
	dex
	beq done
	jmp :-
done:
	rts
.endproc
	
;****************************************
; ハイレゾ画面フォントのビットマップデータを
; セットする
; Aレジスタ - ascii character
; Yレジスタ - 必ず0を設定しておくこと
;****************************************
.proc set_font
	sty pix_offset
	sty pixL
	sty pixH

	sec                                         ; subtract 32 as font starts at char 32 (space)
	sbc #$20
	asl                                         ; mult 8 as that's how many bytes per char
	rol pixH
	asl
	rol pixH
	asl
	rol pixH
	adc #<font                                  ; add in the memory location
	sta pixL
	lda #>font
	adc pixH
	sta pixH                                   ; now font points at the character data

	rts
.endproc

; データセグメント
.segment "DATA"
asc_score: .asciiz "000000"                     ;スコア(ascii)
asc_left:  .asciiz "0"				;残りのボール数(ascii)

dmz1:	.asciiz "xxxxxxx"                       ;debug用。この領域が壊れてるかどうか

; 5バイトで１個のブロックデータを表現
; 1バイト目 ブロック状態(8bit)
; 7ビット:状態ビット 0:消去された 1:存在している
; 6ビット:描写ビット 0:描写指示なし 1:描写指示あり
; 描写指示があり、２ページともが0になったら、状態ビットを0にする
; また、描写指示があり２ページすべての状態ビットが1になったら
; 描写ビットを0にする
; 5ビット:1ページ目の表示状態: 1:表示 0:非表示
; 4ビット:2ページ目の表示状態: 1:表示 0:非表示
; 1の場合、描写ルーチンで当該ビットを0にセット
; あわせて、状態ビットを1にセットすること。
;
; 3〜0ビット:未使用
; 2バイト目 X座標 X座標(8bit 0〜255)
; 3バイト目 X方向の幅  (8bit 0〜255)
; 4バイト目 Y座標 Y座標(8bit 0〜255)
; 5バイト目 Y方向の高さ(8bit 0〜255)
;
; ブロック消去時のデータフローは次のとおり。
; 10 -> 11 -> ブロック消去 -> 00
b_data1_cnt:
.byte $0f                     ;テーブルデータの個数(個数領域は含まない)
b_data1:	
.byte $c0,$01,$04,$01,$08     ;１つ目のブロックデータ
.byte $c0,$05,$04,$01,$08     ;２つ目のブロックデータ
.byte $c0,$09,$04,$01,$08     ;３つ目のブロックデータ

b_data2:	
	.byte $11,$21,$31,$41,$51,$61,$71
	.byte $12,$22,$32,$42,$52,$62,$72
	.byte $13,$23,$33,$43,$53,$63,$73
	
; 読み取り専用データセグメント
.segment "RODATA"
; ハイレゾメモリアドレステーブル(0〜191)
rowL:
    .repeat $C0, Row
	.byte   Row & $08 << 4 | Row & $C0 >> 1 | Row & $C0 >> 3
    .endrep
rowH:
    .repeat $C0, Row
	.byte   >$0000 | Row & $07 << 2 | Row & $30 >> 4
.endrep

;テキスト描写データ
game_title: .asciiz "B L O C K"
hit_anykey: .asciiz "HIT ANY KEY"
CP: .asciiz "(C) 2024 YOSI55@EMAIL.COM"

score: .asciiz "SCORE"
hi_score: .asciiz "HSCORE"
left:	.asciiz "LEFT"
GUIDE1:  .asciiz "A:LEFT"
GUIDE2:  .asciiz "D:RIGHT"
GUIDE3:  .asciiz " :STOP"
GUIDE4:  .asciiz "Q:QUIT"
szHex:	.asciiz "  "
game_over: .asciiz "GAME OVER"

asc_tbl:    ;割る数テーブル(3バイト * 6桁 = 18バイト) リトルエディアン
	.byte $a0,$86,$01	; 100000 $0186a0
	.byte $10,$27,$00	; 10000  $002710
	.byte $e8,$03,$00	; 1000   $0003e8
	.byte $64,$00,$00	; 100    $000064
	.byte $0a,$00,$00	; 10     $00000a
	.byte $01,$00,$00	; 1      $000001
	
; フォントビットマップデータ
font:
    .byte   $00,$00,$00,$00,$00,$00,$00,$00 ;'
    .byte   $08,$08,$08,$08,$08,$00,$08,$00 ;'!
    .byte   $14,$14,$14,$00,$00,$00,$00,$00 ;'"
    .byte   $14,$14,$3E,$14,$3E,$14,$14,$00 ;'#
    .byte   $08,$3C,$0A,$1C,$28,$1E,$08,$00 ;'$
    .byte   $06,$26,$10,$08,$04,$32,$30,$00 ;'%
    .byte   $04,$0A,$0A,$04,$2A,$12,$2C,$00 ;'&
    .byte   $08,$08,$08,$00,$00,$00,$00,$00 ;''
    .byte   $08,$04,$02,$02,$02,$04,$08,$00 ;'(
    .byte   $08,$10,$20,$20,$20,$10,$08,$00 ;')
    .byte   $08,$2A,$1C,$08,$1C,$2A,$08,$00 ;'*
    .byte   $00,$08,$08,$3E,$08,$08,$00,$00 ;'+
    .byte   $00,$00,$00,$00,$08,$08,$04,$00 ;',
    .byte   $00,$00,$00,$3E,$00,$00,$00,$00 ;'-
    .byte   $00,$00,$00,$00,$00,$00,$08,$00 ;'.
    .byte   $00,$20,$10,$08,$04,$02,$00,$00 ;'/
    .byte   $1C,$22,$32,$2A,$26,$22,$1C,$00 ;'0
    .byte   $08,$0C,$08,$08,$08,$08,$1C,$00 ;'1
    .byte   $1C,$22,$20,$18,$04,$02,$3E,$00 ;'2
    .byte   $3E,$20,$10,$18,$20,$22,$1C,$00 ;'3
    .byte   $10,$18,$14,$12,$3E,$10,$10,$00 ;'4
    .byte   $3E,$02,$1E,$20,$20,$22,$1C,$00 ;'5
    .byte   $38,$04,$02,$1E,$22,$22,$1C,$00 ;'6
    .byte   $3E,$20,$10,$08,$04,$04,$04,$00 ;'7
    .byte   $1C,$22,$22,$1C,$22,$22,$1C,$00 ;'8
    .byte   $1C,$22,$22,$3C,$20,$10,$0E,$00 ;'9
    .byte   $00,$00,$08,$00,$08,$00,$00,$00 ;':
    .byte   $00,$00,$08,$00,$08,$08,$04,$00 ;';
    .byte   $10,$08,$04,$02,$04,$08,$10,$00 ;'<
    .byte   $00,$00,$3E,$00,$3E,$00,$00,$00 ;'=
    .byte   $04,$08,$10,$20,$10,$08,$04,$00 ;'>
    .byte   $1C,$22,$10,$08,$08,$00,$08,$00 ;'?
    .byte   $1C,$22,$2A,$3A,$1A,$02,$3C,$00 ;'@
    .byte   $08,$14,$22,$22,$3E,$22,$22,$00 ;'A
    .byte   $1E,$22,$22,$1E,$22,$22,$1E,$00 ;'B
    .byte   $1C,$22,$02,$02,$02,$22,$1C,$00 ;'C
    .byte   $1E,$22,$22,$22,$22,$22,$1E,$00 ;'D
    .byte   $3E,$02,$02,$1E,$02,$02,$3E,$00 ;'E
    .byte   $3E,$02,$02,$1E,$02,$02,$02,$00 ;'F
    .byte   $3C,$02,$02,$02,$32,$22,$3C,$00 ;'G
    .byte   $22,$22,$22,$3E,$22,$22,$22,$00 ;'H
    .byte   $1C,$08,$08,$08,$08,$08,$1C,$00 ;'I
    .byte   $20,$20,$20,$20,$20,$22,$1C,$00 ;'J
    .byte   $22,$12,$0A,$06,$0A,$12,$22,$00 ;'K
    .byte   $02,$02,$02,$02,$02,$02,$3E,$00 ;'L
    .byte   $22,$36,$2A,$2A,$22,$22,$22,$00 ;'M
    .byte   $22,$22,$26,$2A,$32,$22,$22,$00 ;'N
    .byte   $1C,$22,$22,$22,$22,$22,$1C,$00 ;'O
    .byte   $1E,$22,$22,$1E,$02,$02,$02,$00 ;'P
    .byte   $1C,$22,$22,$22,$2A,$12,$2C,$00 ;'Q
    .byte   $1E,$22,$22,$1E,$0A,$12,$22,$00 ;'R
    .byte   $1C,$22,$02,$1C,$20,$22,$1C,$00 ;'S
    .byte   $3E,$08,$08,$08,$08,$08,$08,$00 ;'T
    .byte   $22,$22,$22,$22,$22,$22,$1C,$00 ;'U
    .byte   $22,$22,$22,$22,$22,$14,$08,$00 ;'V
    .byte   $22,$22,$22,$2A,$2A,$36,$22,$00 ;'W
    .byte   $22,$22,$14,$08,$14,$22,$22,$00 ;'X
    .byte   $22,$22,$14,$08,$08,$08,$08,$00 ;'Y
    .byte   $3E,$20,$10,$08,$04,$02,$3E,$00 ;'Z
    .byte   $3E,$06,$06,$06,$06,$06,$3E,$00 ;'[
    .byte   $00,$02,$04,$08,$10,$20,$00,$00 ;'\
    .byte   $3E,$30,$30,$30,$30,$30,$3E,$00 ;']
    .byte   $00,$00,$08,$14,$22,$00,$00,$00 ;'^
    .byte   $00,$00,$00,$00,$00,$00,$00,$7F ;'_
    .byte   $04,$08,$10,$00,$00,$00,$00,$00 ;'`
endFont:

; ボールビットマップデータ
BALL0:
.byte $3C, $00 ;00111100 00000000
.byte $7F, $01 ;01111111 00000001
.byte $7F, $01 ;01111111 00000001
.byte $7F, $01 ;01111111 00000001
.byte $7F, $01 ;01111111 00000001
.byte $7F, $01 ;01111111 00000001
.byte $7F, $01 ;01111111 00000001
.byte $3C, $00 ;00111100 00000000
;BALL1:
;.byte $78, $00 ;01111000 00000000
;.byte $7E, $03 ;01111110 00000011
;.byte $7E, $03 ;01111110 00000011
;.byte $7E, $03 ;01111110 00000011
;.byte $7E, $03 ;01111110 00000011
;.byte $7E, $03 ;01111110 00000011
;.byte $7E, $03 ;01111110 00000011
;.byte $78, $00 ;01111000 00000000
BALL2:
.byte $70, $01 ;01110000 00000001
.byte $7C, $07 ;01111100 00000111
.byte $7C, $07 ;01111100 00000111
.byte $7C, $07 ;01111100 00000111
.byte $7C, $07 ;01111100 00000111
.byte $7C, $07 ;01111100 00000111
.byte $7C, $07 ;01111100 00000111
.byte $70, $01 ;01110000 00000001
;BALL3:
;.byte $60, $03 ;01100000 00000011
;.byte $78, $0F ;01111000 00001111
;.byte $78, $0F ;01111000 00001111
;.byte $78, $0F ;01111000 00001111
;.byte $78, $0F ;01111000 00001111
;.byte $78, $0F ;01111000 00001111
;.byte $78, $0F ;01111000 00001111
;.byte $60, $03 ;01100000 00000011
BALL4:
.byte $40, $07 ;01000000 00000111
.byte $70, $1F ;01110000 00011111
.byte $70, $1F ;01110000 00011111
.byte $70, $1F ;01110000 00011111
.byte $70, $1F ;01110000 00011111
.byte $70, $1F ;01110000 00011111
.byte $70, $1F ;01110000 00011111
.byte $40, $07 ;01000000 00000111
;BALL5:
;.byte $00, $0F ;00000000 00001111
;.byte $60, $3F ;01100000 00111111
;.byte $60, $3F ;01100000 00111111
;.byte $60, $3F ;01100000 00111111
;.byte $60, $3F ;01100000 00111111
;.byte $60, $3F ;01100000 00111111
;.byte $60, $3F ;01100000 00111111
;.byte $00, $0F ;00000000 00001111
BALL6:
.byte $00, $1E ;00000000 00011110
.byte $40, $7F ;01000000 01111111
.byte $40, $7F ;01000000 01111111
.byte $40, $7F ;01000000 01111111
.byte $40, $7F ;01000000 01111111
.byte $40, $7F ;01000000 01111111
.byte $40, $7F ;01000000 01111111
.byte $00, $1E ;00000000 00011110

;ラケットのビットマップ
pat1:  ;色付きパターン(奇数)
.byte $a8,$d5,$aa,$d5,$aa,$00
.byte $aa,$d5,$aa,$d5,$aa,$85
.byte $aa,$d5,$aa,$d5,$aa,$85
.byte $aa,$d5,$aa,$d5,$aa,$85
.byte $aa,$d5,$aa,$d5,$aa,$85
.byte $aa,$d5,$aa,$d5,$aa,$85
.byte $aa,$d5,$aa,$d5,$aa,$85
.byte $a8,$d5,$aa,$d5,$aa,$00

pat2:  ;色付きパターン(奇数) ハーフビットシフトバージョン
.byte $d0,$aa,$d5,$aa,$d5,$00
.byte $d5,$aa,$d5,$aa,$d5,$8a
.byte $d5,$aa,$d5,$aa,$d5,$8a
.byte $d5,$aa,$d5,$aa,$d5,$8a
.byte $d5,$aa,$d5,$aa,$d5,$8a
.byte $d5,$aa,$d5,$aa,$d5,$8a
.byte $d5,$aa,$d5,$aa,$d5,$8a
.byte $d0,$aa,$d5,$aa,$d5,$00

pat3:  ;色付きパターン(偶数)
.byte $00,$d5,$aa,$d5,$aa,$85
.byte $aa,$d5,$aa,$d5,$aa,$d5
.byte $aa,$d5,$aa,$d5,$aa,$d5
.byte $aa,$d5,$aa,$d5,$aa,$d5
.byte $aa,$d5,$aa,$d5,$aa,$d5
.byte $aa,$d5,$aa,$d5,$aa,$d5
.byte $aa,$d5,$aa,$d5,$aa,$d5
.byte $00,$d5,$aa,$d5,$aa,$85

pat4:  ;色付きパターン(偶数) ハーフビットシフトバージョン
.byte $00,$aa,$d5,$aa,$d5,$8a
.byte $d0,$aa,$d5,$aa,$d5,$aa
.byte $d0,$aa,$d5,$aa,$d5,$aa
.byte $d0,$aa,$d5,$aa,$d5,$aa
.byte $d0,$aa,$d5,$aa,$d5,$aa
.byte $d0,$aa,$d5,$aa,$d5,$aa
.byte $d0,$aa,$d5,$aa,$d5,$aa
.byte $00,$aa,$d5,$aa,$d5,$8a

blk_pat1:			;ブロックパターン1
	.byte $00,$00,$00,$00
	.byte $fc,$ff,$ff,$3f
	.byte $fc,$ff,$ff,$3f
	.byte $fc,$ff,$ff,$3f
	.byte $fc,$ff,$ff,$3f
	.byte $fc,$ff,$ff,$3f
	.byte $fc,$ff,$ff,$3f
	.byte $fc,$ff,$ff,$3f

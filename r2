#!/bin/sh
# デバッグ版モジュール実行スクリプト

cp /home/kouji/src/a2/block/block.dsk /home/kouji/microM8/MyDisks
microm8 -drive1 block.dsk -debug

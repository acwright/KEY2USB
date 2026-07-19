0 rem =====================================================================
1 rem  key2usbtest - keyboard + joystick verification for key2usb
2 rem
3 rem  runs inside vice on the host. the c64/c128 sends keystrokes over usb
4 rem  via the key2usb cartridge; this program shows what vice actually
5 rem  received, for both the keyboard and both joystick ports.
6 rem
7 rem  all live fields are poked straight to screen ram and keys are never
8 rem  echoed with print. that matters: a joystick held in port 1 grounds a
9 rem  keyboard matrix row and phantom-presses return / clr-home / cursor
10 rem  keys, which would scroll and overwrite a print-based display and make
11 rem  the readings look like garbage.
12 rem =====================================================================
20 print chr$(147);"key2usb test"
30 print
40 print "joy2:"
50 print "joy1:"
60 print
70 print "key:"
80 print "typed:"
90 print
100 print "joy flags: u d l r f   raw is hex"
110 print "port 2 = keypad digits"
120 print "port 1 = keypad symbols"
130 print
140 print "run/stop + restore to exit"
150 dim c(4):for i=0 to 4:read c(i):next
160 data 21,4,12,18,6
170 p=1110:q=1150:hp=1272:hn=0
180 rem --- main poll loop ---
190 j=peek(56320):k=peek(56321)
200 m=1
210 for b=0 to 4
220 a=46:if (j and m)=0 then a=c(b)
230 poke p+b*2,a
240 a=46:if (k and m)=0 then a=c(b)
250 poke q+b*2,a
260 m=m*2:next
270 x=j:y=1121:gosub 500
280 x=k:y=1161:gosub 500
290 get a$:if a$="" then 190
300 v=asc(a$)
310 s=63
320 if v>=32 and v<=63 then s=v
330 if v>=64 and v<=95 then s=v-64
340 if v>=96 and v<=127 then s=v-32
350 if v>=160 and v<=191 then s=v-64
360 if v>=192 and v<=223 then s=v-128
370 poke 1230,s
380 x=v:y=1233:gosub 600
390 poke hp+hn,s:hn=hn+1
400 if hn<20 then 190
410 hn=0:for i=0 to 19:poke hp+i,32:next
420 goto 190
500 rem --- poke x as two hex digits at y ---
510 h=int(x/16):l=x-h*16
520 if h>9 then poke y,h-9
530 if h<10 then poke y,h+48
540 if l>9 then poke y+1,l-9
550 if l<10 then poke y+1,l+48
560 return
600 rem --- poke x as three decimal digits at y ---
610 d1=int(x/100):d2=int((x-d1*100)/10):d3=x-d1*100-d2*10
620 poke y,d1+48:poke y+1,d2+48:poke y+2,d3+48
630 return

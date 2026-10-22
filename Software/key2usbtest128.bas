0 rem =====================================================================
1 rem  key2usbtest128 - c128 native-mode test for key2usb (basic 7.0)
2 rem
3 rem  runs inside x128 (c128 mode) on the host, with the cartridge's mode
4 rem  jumper on c128. shows what x128 received: the key the c128 kernal
5 rem  sees held (from its own matrix code at 212, so the keypad, help,
6 rem  esc, alt, no scroll and cursor pad are named exactly), the shift /
7 rem  c= / ctrl / alt / caps lock flags (211), the 40/80 key (54533),
8 rem  both joysticks, and the last characters typed.
9 rem
10 rem  all output uses char, which writes at a fixed position without
11 rem  scrolling, on the 40- or 80-column screen alike.
12 rem =====================================================================
20 dim n$(88),d$(8)
30 for i=0 to 88:read n$(i):next
40 for i=0 to 8:read d$(i):next
50 scnclr
60 char 1,0,0,"key2usb test 128"
70 char 1,0,2,"key:"
80 char 1,0,3,"mods:"
90 char 1,0,4,"40/80:"
100 char 1,0,6,"joy2:"
110 char 1,0,7,"joy1:"
120 char 1,0,9,"typed:"
130 char 1,0,11,"key = the matrix key x128 sees held."
140 char 1,0,12,"joy2 needs joystick port 2 = keypad"
150 char 1,0,13,"and allow keyset joysticks; to type"
160 char 1,0,14,"on the keypad set port 2 to none."
170 char 1,0,15,"no scroll pauses: press it again."
175 char 1,0,17,"run/stop to exit"
180 h$=""
190 rem --- main poll loop ---
200 m=peek(212):s=peek(211):d=peek(54533) and 128
210 char 1,7,2,left$(n$(m)+"            ",12)+str$(m)+"  "
220 f$=""
230 if s and 1 then f$=f$+"shift "
240 if s and 2 then f$=f$+"c= "
250 if s and 4 then f$=f$+"ctrl "
260 if s and 8 then f$=f$+"alt "
270 if s and 16 then f$=f$+"caps "
280 char 1,7,3,left$(f$+"                        ",24)
290 if d then char 1,7,4,"up   (40 col)"
300 if d=0 then char 1,7,4,"down (80 col)"
310 j=joy(2):y=6:gosub 500
320 j=joy(1):y=7:gosub 500
330 get a$:if a$="" then 200
340 v=asc(a$):c$="."
350 if (v>31 and v<128) or v>159 then c$=a$
360 h$=right$(h$+c$,20)
370 char 1,7,9,left$(h$+"                    ",20)+str$(v)+"  "
380 goto 200
500 rem --- joystick value j at row y ---
510 t$=d$(j and 15):if j and 128 then t$=t$+" + fire"
520 char 1,7,y,left$(t$+"                  ",18)
530 return
900 rem --- c128 kernal matrix codes 0-88 (88 = no key) ---
910 data "inst/del","return","crsr l/r","f7","f1","f3","f5","crsr u/d"
920 data "3","w","a","4","z","s","e","left shift"
930 data "5","r","d","6","c","f","t","x"
940 data "7","y","g","8","b","h","u","v"
950 data "9","i","j","0","m","k","o","n"
960 data "+","p","l","-",".",":","@",","
970 data "pound","*",";","clr/home","right shift","=","up arrow","/"
980 data "1","left arrow","ctrl","2","space","c=","q","run/stop"
990 data "help","kp 8","kp 5","tab","kp 2","kp 4","kp 7","kp 1"
1000 data "esc","kp +","kp -","line feed","kp enter","kp 6","kp 9","kp 3"
1010 data "alt","kp 0","kp .","pad up","pad down","pad left","pad right"
1020 data "no scroll","-"
1030 rem --- joy() directions 0-8 ---
1040 data "-","up","up right","right","down right","down","down left"
1050 data "left","up left"

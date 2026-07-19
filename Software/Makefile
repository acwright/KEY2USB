# =============================================================================
#  KEY2USB host-side test software
# =============================================================================
#
#   make          -> key2usbtest.prg
#   make run      -> build, then launch it in x64sc
#   make clean    -> remove built .prg
#
# petcat ships with VICE. Note that the BASIC source must be written in
# LOWERCASE: petcat treats lowercase as normal text (rendering as uppercase on
# the C64) and UPPERCASE as shifted/graphics characters. All-caps source
# tokenizes into graphics glyphs and produces ?SYNTAX ERROR.

TARGET = key2usbtest

.PHONY: all run clean

all: $(TARGET).prg

$(TARGET).prg: $(TARGET).bas
	petcat -w2 -o $@ -- $<
	@printf 'Built %s (%s bytes)\n' "$@" "$$(wc -c < $@ | tr -d ' ')"

run: $(TARGET).prg
	x64sc -autostart $(TARGET).prg

clean:
	rm -f $(TARGET).prg

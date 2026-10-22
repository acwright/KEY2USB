# =============================================================================
#  KEY2USB host-side test software
# =============================================================================
#
#   make            -> key2usbtest.prg, key2usbtest128.prg and key2usbmon
#   make run        -> build key2usbtest.prg, then launch it in x64sc
#   make run128     -> build key2usbtest128.prg, then launch it in x128
#   make mon        -> build key2usbmon, then watch the cartridge's USB reports
#   make check      -> build key2usbmon, then run its press-every-key checklist
#   make clean      -> remove build output
#
# key2usbmon is a native macOS tool (Swift + IOKit) that reads the cartridge's
# HID reports directly - no emulator involved. swiftc comes with the Xcode
# Command Line Tools (xcode-select --install).
#
# petcat ships with VICE. Note that the BASIC source must be written in
# LOWERCASE: petcat treats lowercase as normal text (rendering as uppercase on
# the C64) and UPPERCASE as shifted/graphics characters. All-caps source
# tokenizes into graphics glyphs and produces ?SYNTAX ERROR.

TARGET = key2usbtest
TARGET128 = key2usbtest128
MON    = key2usbmon

.PHONY: all run run128 mon check clean

all: $(TARGET).prg $(TARGET128).prg $(MON)

$(TARGET).prg: $(TARGET).bas
	petcat -w2 -o $@ -- $<
	@printf 'Built %s (%s bytes)\n' "$@" "$$(wc -c < $@ | tr -d ' ')"

# BASIC 7.0 for the C128 (-w70 also sets the C128's $1C01 load address).
$(TARGET128).prg: $(TARGET128).bas
	petcat -w70 -o $@ -- $<
	@printf 'Built %s (%s bytes)\n' "$@" "$$(wc -c < $@ | tr -d ' ')"

run: $(TARGET).prg
	x64sc -autostart $(TARGET).prg

run128: $(TARGET128).prg
	x128 -40col -autostart $(TARGET128).prg

$(MON): $(MON).swift
	swiftc -swift-version 5 -O -o $@ $<

mon: $(MON)
	./$(MON)

check: $(MON)
	./$(MON) --check

clean:
	rm -f $(TARGET).prg $(TARGET128).prg $(MON)

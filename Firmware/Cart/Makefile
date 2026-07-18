# =============================================================================
#  KEY2USB cartridge ROM - build the 8K 28C64 image from two 4K banks
# =============================================================================
#
#   make            -> Cart.bin (8K: C64 bank then C128 bank), temp files removed
#   make eeprom     -> build, then program the EEPROM with minipro
#   make view       -> build, then hexdump the image
#   make clean      -> remove all build output
#
# `make` always rebuilds and leaves only Cart.bin (the two intermediate 4K bank
# files are deleted once concatenated).

TARGET = Cart
CONFIG = Cart.cfg
SRC    = Cart.asm Cart.inc $(CONFIG)

# minipro device name for the EEPROM. Use the standard AT28C64B profile (NOT
# "AT28C64B(Non-Standard)", whose write timing needs a pulse-delay workaround).
# Override on the command line if needed, e.g.  make eeprom EEPROM="AM28C64B@DIP28"
EEPROM = AT28C64B

CL65 = cl65 -t none -C $(CONFIG)

.PHONY: all build eeprom view clean

all: build

# Assemble the C64 (lower 4K) and C128 (upper 4K) banks, concatenate into the
# 8K image, then delete the intermediate bank files.
build: $(SRC)
	$(CL65) -o cart_c64.bin Cart.asm
	$(CL65) --asm-define TARGET_C128 -o cart_c128.bin Cart.asm
	cat cart_c64.bin cart_c128.bin > $(TARGET).bin
	@rm -f cart_c64.bin cart_c128.bin
	@printf 'Built %s (%s bytes)\n' "$(TARGET).bin" "$$(wc -c < $(TARGET).bin | tr -d ' ')"

eeprom: build
	minipro -p "$(EEPROM)" -w $(TARGET).bin

view: build
	hexdump -C $(TARGET).bin

clean:
	rm -f $(TARGET).bin cart_c64.bin cart_c128.bin *.lst

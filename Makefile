fl2000-y := \
	fl2000_drv.o \
	fl2000_registers.o \
	fl2000_interrupt.o \
	fl2000_streaming.o \
	fl2000_i2c.o \
	fl2000_drm.o \
	bridge/it66121_drv.o

obj-m := fl2000.o

KVER ?= $(shell uname -r)
KSRC ?= /lib/modules/$(KVER)/build

ccflags-y := -Wall

all:	modules

modules:
	make CHECK="/usr/bin/sparse" -C $(KSRC) M=$(PWD) modules

clean:
	make -C $(KSRC) M=$(PWD) clean
	rm -f $(PWD)/Module.symvers $(PWD)/*.ur-safe

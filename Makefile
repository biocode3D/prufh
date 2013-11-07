
LIBDIR_APP_LOADER?=/home/linuxcnc/am335x_pru_package/pru_sw/app_loader/lib
INCDIR_APP_LOADER?=/home/linuxcnc/am335x_pru_package/pru_sw/app_loader/include
BINDIR?=.

CFLAGS+= -Wall -I$(INCDIR_APP_LOADER) -D__DEBUG -O2 -mtune=cortex-a8 -march=armv7-a
LDFLAGS+=-L$(LIBDIR_APP_LOADER) -lprussdrv -lpthread
OBJDIR=obj
TARGET=$(BINDIR)/prufh_term

_DEPS = 
DEPS = $(patsubst %,$(INCDIR_APP_LOADER)/%,$(_DEPS))

_OBJ = prufh_term.o
OBJ = $(patsubst %,$(OBJDIR)/%,$(_OBJ))


$(OBJDIR)/%.o: %.c $(DEPS)
	@mkdir -p obj
	gcc $(CFLAGS) -c -o $@ $< 

$(TARGET): $(OBJ)
	gcc $(CFLAGS) -o $@ $^ $(LDFLAGS)

.PHONY: clean

clean:
	rm -rf $(OBJDIR)/ *~  $(TARGET)

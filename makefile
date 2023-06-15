NAME = ly
CC = gcc
FLAGS = -std=c99 -pedantic -g
FLAGS+= -Wall -Wextra -Werror=vla -Wno-unused-parameter
#FLAGS+= -DDEBUG
FLAGS+= -DLY_VERSION=\"$(shell git describe --long --tags | sed 's/\([^-]*-g\)/r\1/;s/-/./g')\"
LINK = -lpam -lxcb
VALGRIND = --show-leak-kinds=all --track-origins=yes --leak-check=full --suppressions=../res/valgrind.supp
CMD = ./$(NAME)

OS:= $(shell uname -s)
ifeq ($(OS), Linux)
	FLAGS+= -D_DEFAULT_SOURCE
endif

BIND = bin
OBJD = obj
SRCD = src
SUBD = sub
RESD = res
TESTD = tests

DATADIR ?= ${DESTDIR}/etc/ly
FLAGS+= -DDATADIR=\"$(DATADIR)\"

INCL = -I$(SRCD)
INCL+= -I$(SUBD)/ctypes
INCL+= -I$(SUBD)/argoat/src
INCL+= -I$(SUBD)/configator/src
INCL+= -I$(SUBD)/dragonfail/src
INCL+= -I$(SUBD)/termbox_next/src

SRCS = $(SRCD)/main.c
SRCS += $(SRCD)/config.c
SRCS += $(SRCD)/draw.c
SRCS += $(SRCD)/inputs.c
SRCS += $(SRCD)/login.c
SRCS += $(SRCD)/utils.c
SRCS += $(SUBD)/argoat/src/argoat.c
SRCS += $(SUBD)/configator/src/configator.c
SRCS += $(SUBD)/dragonfail/src/dragonfail.c

SRCS_OBJS:= $(patsubst %.c,$(OBJD)/%.o,$(SRCS))
SRCS_OBJS+= $(SUBD)/termbox_next/bin/termbox.a

.PHONY: final
final: $(BIND)/$(NAME)

$(OBJD)/%.o: %.c
	@echo "building object $@"
	@mkdir -p $(@D)
	@$(CC) $(INCL) $(FLAGS) -c -o $@ $<

$(SUBD)/termbox_next/bin/termbox.a:
	@echo "building static object $@"
	@(cd $(SUBD)/termbox_next && $(MAKE))

$(BIND)/$(NAME): $(SRCS_OBJS)
	@echo "compiling executable $@"
	@mkdir -p $(@D)
	@$(CC) -o $@ $^ $(LINK)

run:
	@cd $(BIND) && $(CMD)

leak: leakgrind
leakgrind: $(BIND)/$(NAME)
	@rm -f valgrind.log
	@cd $(BIND) && valgrind $(VALGRIND) 2> ../valgrind.log $(CMD)
	@less valgrind.log

install: $(BIND)/$(NAME)
	@echo "installing ly"
	@install -dZ ${DESTDIR}/etc/ly
	@install -DZ $(BIND)/$(NAME) -t ${DESTDIR}/usr/bin
	@install -DZ $(RESD)/config.ini -t ${DESTDIR}/etc/ly
	@install -DZ $(RESD)/xsetup.sh -t $(DATADIR)
	@install -DZ $(RESD)/wsetup.sh -t $(DATADIR)
	@install -dZ $(DATADIR)/lang
	@install -DZ $(RESD)/lang/* -t $(DATADIR)/lang
	@install -DZ $(RESD)/pam.d/ly -m 644 -t ${DESTDIR}/etc/pam.d

installnoconf: $(BIND)/$(NAME)
	@echo "installing ly without the configuration file"
	@install -dZ ${DESTDIR}/etc/ly
	@install -DZ $(BIND)/$(NAME) -t ${DESTDIR}/usr/bin
	@install -DZ $(RESD)/xsetup.sh -t $(DATADIR)
	@install -DZ $(RESD)/wsetup.sh -t $(DATADIR)
	@install -dZ $(DATADIR)/lang
	@install -DZ $(RESD)/lang/* -t $(DATADIR)/lang
	@install -DZ $(RESD)/pam.d/ly -m 644 -t ${DESTDIR}/etc/pam.d

installsystemd:
	@echo "installing systemd service"
	@install -DZ $(RESD)/ly.service -m 644 -t ${DESTDIR}/usr/lib/systemd/system

installopenrc:
	@echo "installing openrc service"
	@install -DZ $(RESD)/ly-openrc -m 755 -T ${DESTDIR}/etc/init.d/${NAME}

installrunit:
	@echo "installing runit service"
	@install -DZ $(RESD)/ly-runit-service/* -t ${DESTDIR}/etc/sv/ly

uninstall:
	@echo "uninstalling"
	@rm -rf ${DESTDIR}/etc/ly
	@rm -rf $(DATADIR)
	@rm -f ${DESTDIR}/usr/bin/ly
	@rm -f ${DESTDIR}/usr/lib/systemd/system/ly.service
	@rm -f ${DESTDIR}/etc/pam.d/ly
	@rm -f ${DESTDIR}/etc/init.d/${NAME}
	@rm -rf ${DESTDIR}/etc/sv/ly

clean:
	@echo "cleaning"
	@rm -rf $(BIND) $(OBJD) valgrind.log
	@(cd $(SUBD)/termbox_next && $(MAKE) clean)

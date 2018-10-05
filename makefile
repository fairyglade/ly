NAME=ly
CC=gcc
#CC=gcc -O3
#CC=tcc
FLAGS=-std=c99 -pedantic -Wall -Werror=vla -Werror -g

OS:=$(shell uname -s)
ifeq ($(OS),Linux)
	FLAGS+=-D_DEFAULT_SOURCE
endif

BIND=bin
SRCD=src
SUBD=sub
OBJD=obj
RESD=res
LANG=$(RESD)/lang
INCL=-I$(SRCD) -I$(SUBD)/termbox-next/src -I$(SUBD)/inih
LINK=-lm -lpam -lpam_misc

SRCS=$(SRCD)/main.c
SRCS+=$(SRCD)/draw.c
SRCS+=$(SRCD)/util.c
SRCS+=$(SRCD)/config.c
SRCS+=$(SRCD)/widgets.c
SRCS+=$(SRCD)/desktop.c
SRCS+=$(SRCD)/inputs.c
SRCS+=$(SRCD)/login.c
SRCS+=$(SUBD)/inih/ini.c

OBJS:=$(patsubst $(SRCD)/%.c,$(OBJD)/$(SRCD)/%.o,$(SRCS))
OBJS+=$(SUBD)/termbox-next/bin/termbox.a

.PHONY:all
all:$(BIND)/$(NAME)

$(OBJD)/%.o:%.c
	@echo "building source object $@"
	@mkdir -p $(@D)
	@$(CC) $(INCL) $(FLAGS) -c -o $@ $<

$(SUBD)/termbox-next/bin/termbox.a:
	@echo "building static object $@"
	@(cd $(SUBD)/termbox-next && $(MAKE))

$(BIND)/$(NAME):$(OBJS)
	@echo "compiling $@"
	@mkdir -p $(BIND)
	@$(CC) $(INCL) $(FLAGS) $(LINK) -o $(BIND)/$(NAME) $(OBJS)
	@cp -r $(LANG) $(BIND)/lang
	@cp $(RESD)/config.ini $(BIND)

run:$(BIND)/$(NAME)
	@cd ./$(BIND) && ./$(NAME)

valgrind:$(BIND)/$(NAME)
	@cd ./$(BIND) && valgrind --show-leak-kinds=all --track-origins=yes --leak-check=full --suppressions=../res/valgrind.supp 2> ../valgrind.log ./ly

install:$(BIND)/$(NAME)
	install -dZ ${DESTDIR}/etc/ly
	install -DZ $(BIND)/$(NAME) -t ${DESTDIR}/usr/bin
	install -DZ xsetup.sh -t ${DESTDIR}/etc/ly
	install -DZ $(RESD)/config.ini -t ${DESTDIR}/etc/ly
	install -dZ ${DESTDIR}/etc/ly/lang
	install -DZ $(RESD)/lang/* -t ${DESTDIR}/etc/ly/lang
	install -DZ ly.service -t ${DESTDIR}/usr/lib/systemd/system

uninstall:
	rm -rf ${DESTDIR}/etc/ly
	rm -f ${DESTDIR}/usr/bin/ly
	rm -f ${DESTDIR}/usr/lib/systemd/system/ly.service

clean:
	@echo "cleaning workspace"
	@rm -rf $(BIND)
	@rm -rf $(OBJD)
	@(cd $(SUBD)/termbox-next && $(MAKE) clean)

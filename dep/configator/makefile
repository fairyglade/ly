NAME = sample
CC = gcc
FLAGS = -std=c99 -pedantic -g
FLAGS+= -Wall -Wno-unused-parameter -Wextra -Werror=vla -Werror
VALGRIND = --show-leak-kinds=all --track-origins=yes --leak-check=full

BIND = bin
OBJD = obj
SRCD = src
RESD = res

INCL = -I$(SRCD)

SRCS = $(SRCD)/example.c
SRCS+= $(SRCD)/configator.c

OBJS:= $(patsubst $(SRCD)/%.c,$(OBJD)/$(SRCD)/%.o,$(SRCS))

.PHONY: all
all: $(BIND)/$(NAME) run

$(OBJD)/%.o: %.c
	@echo "building object $@"
	@mkdir -p $(@D)
	@$(CC) $(INCL) $(FLAGS) -c -o $@ $<

$(BIND)/$(NAME): $(OBJS)
	@echo "compiling executable $@"
	@mkdir -p $(@D)
	@$(CC) -o $@ $^ $(LINK)
	@cp $(RESD)/test.ini $(BIND)/config.ini

run:
	@cd $(BIND) && ./$(NAME)

leakgrind: $(BIND)/$(NAME)
	@cd $(BIND) && valgrind $(VALGRIND) 2> ../valgrind.log ./$(NAME)

clean:
	@echo "cleaning"
	@rm -rf $(BIND) $(OBJD) valgrind.log

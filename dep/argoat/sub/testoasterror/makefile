NAME = testoasterror
CC = gcc
FLAGS = -std=c99 -pedantic -g
FLAGS+= -Wall -Wextra -Werror=vla -Werror
VALGRIND = --show-leak-kinds=all --track-origins=yes --leak-check=full

BIND = bin
OBJD = obj
SRCD = src
TESTS = tests

INCL = -I$(SRCD)

SRCS = $(SRCD)/testoasterror.c
SRCS+= $(TESTS)/main.c

OBJS:= $(patsubst %.c,$(OBJD)/%.o,$(SRCS))

.PHONY: $(BIND)/$(NAME)

$(OBJD)/%.o: %.c
	@echo "building object $@"
	@mkdir -p $(@D)
	@$(CC) $(INCL) $(FLAGS) -c -o $@ $<

$(BIND)/$(NAME): $(OBJS)
	@echo "compiling executable $@"
	@mkdir -p $(@D)
	@$(CC) -o $@ $^ $(LINK)

run:
	@cd $(BIND) && ./$(NAME)

leakgrind: $(BIND)/$(NAME)
	@cd $(BIND) && valgrind $(VALGRIND) 2> ../valgrind.log ./$(NAME)

clean:
	@echo "cleaning"
	@rm -rf $(BIND) $(OBJD) valgrind.log

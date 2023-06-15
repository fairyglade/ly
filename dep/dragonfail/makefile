NAME = dragonfail
CC = gcc
FLAGS = -std=c99 -pedantic -g
FLAGS+= -Wall -Wno-unused-parameter -Wextra -Werror=vla -Werror
VALGRIND = --show-leak-kinds=all --track-origins=yes --leak-check=full

BIND = bin
OBJD = obj
SRCD = src
EXPD = example

INCL = -I$(SRCD)
INCL+= -I$(EXPD)

SRCS = $(EXPD)/example.c
SRCS+= $(SRCD)/dragonfail.c

SRCS_OBJS := $(patsubst %.c,$(OBJD)/%.o,$(SRCS))

# aliases
.PHONY: final
final: $(BIND)/$(NAME)

# generic compiling command
$(OBJD)/%.o: %.c
	@echo "building object $@"
	@mkdir -p $(@D)
	@$(CC) $(INCL) $(FLAGS) -c -o $@ $<

# final executable
$(BIND)/$(NAME): $(SRCS_OBJS) $(FINAL_OBJS)
	@echo "compiling executable $@"
	@mkdir -p $(@D)
	@$(CC) -o $@ $^ $(LINK)

run:
	@cd $(BIND) && ./$(NAME)

# tools
## valgrind memory leak detection
leak: $(BIND)/$(NAME)
	@echo "# running valgrind"
	rm -f valgrind.log
	cd $(BIND) && valgrind $(VALGRIND) 2> ../valgrind.log ./$(NAME)
	less valgrind.log
## repository cleaning
clean:
	@echo "# cleaning"
	rm -rf $(BIND) $(OBJD) valgrind.log

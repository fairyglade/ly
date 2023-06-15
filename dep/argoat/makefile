NAME = test
CC = gcc
FLAGS = -std=c99 -pedantic -g
FLAGS+= -Wall -Wextra -Werror=vla -Werror -Wno-unused-parameter

BIND = bin
OBJD = obj
SUBD = sub
SRCD = src
TEST = test

BINS = $(BIND)/argoat_sample_1
BINS+= $(BIND)/argoat_sample_2
BINS+= $(BIND)/argoat_sample_3

INCL = -I$(SRCD) -I$(SUBD)/testoasterror/src
DEP = $(SUBD)/testoasterror/src/testoasterror.h

$(OBJD)/%.o: %.c
	@echo "building object $@"
	@mkdir -p $(@D)
	@$(CC) $(INCL) $(FLAGS) -c -o $@ $<

all: $(DEP) $(BINS) $(BIND)/$(NAME)

$(DEP):
	@git submodule update --init --recursive

$(BIND)/argoat_sample_%: $(OBJD)/$(SRCD)/argoat.o $(OBJD)/$(TEST)/argoat_sample_%.o
	@echo "compiling executable $@"
	@mkdir -p $(@D)
	@$(CC) -o $@ $^ $(LINK)

$(BIND)/$(NAME): $(OBJD)/$(TEST)/main.o $(OBJD)/$(SUBD)/testoasterror/src/testoasterror.o
	@echo "compiling executable $@"
	@mkdir -p $(@D)
	@$(CC) -o $@ $^ $(LINK)

run:
	@cd $(BIND) && ./$(NAME)

clean:
	@echo "cleaning"
	@rm -rf $(BIND) $(OBJD)

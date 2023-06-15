CC=gcc
FLAGS=-std=c99 -pedantic -Wall -Werror -g -static 
INCL=-I../
BIND=../../bin

%.o:%.c
	@echo "building source object $@"
	@$(CC) $(INCL) $(FLAGS) -c -o $@ $<

all:keyboard output paint truecolor

keyboard:keyboard.o
	@echo "compiling $@"
	@$(CC) $(INCL) $(FLAGS) -o $@ $@.o $(BIND)/termbox.a

output:output.o
	@echo "compiling $@"
	@$(CC) $(INCL) $(FLAGS) -o $@ $@.o $(BIND)/termbox.a

paint:paint.o
	@echo "compiling $@"
	@$(CC) $(INCL) $(FLAGS) -o $@ $@.o $(BIND)/termbox.a

truecolor:truecolor.o
	@echo "compiling $@"
	@$(CC) $(INCL) $(FLAGS) -o $@ $@.o $(BIND)/termbox.a

clean:
	@echo "cleaning workspace"
	@rm -rf *.o keyboard output paint truecolor

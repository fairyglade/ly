rwildcard=$(foreach d,$(wildcard $1*),$(call rwildcard,$d/,$2) $(filter $(subst *,%,$2),$d))

######## CONFIG ########

NAME := ly

CXX := cc
INSTALL = ln -sf /usr/lib/security/pam_loginuid.so ${DESTDIR}/usr/lib/pam_loginuid.so

SRCD := src
INCD := src
BIND := build
OBJD := obj
DEPD := dep
LIBD := lib
LIBS := -lform -lncurses -lpam -lpam_misc -lX11
LIBSUSR = -L/usr/lib/security -l:pam_loginuid.so

VPATH = $(SRCD) $(INCD) $(OBJD) $(DEPD)

########  STOP  ########

SRCS := $(call rwildcard,$(SRCD)/,*.c)
OBJS := $(patsubst $(SRCD)/%.c,$(OBJD)/%.o,$(SRCS))
DEPS := $(patsubst $(SRCD)/%.c,$(DEPD)/%.d,$(SRCS))

CXXFLAGS := -Wall -g -I$(INCD)
LDDFLAGS := -L$(LIBD) $(LIBS)

.PHONY: all install uninstall clean distclean
.PRECIOUS: $(DEPD)/%.d

all: $(BIND)/$(NAME)

$(DEPD)/%.d : $(SRCD)/%.c
	@echo "listing dependencies for source file $<"
	@mkdir -p $(@D)
	@$(CXX) $(CXXFLAGS) -M -c $< -o $@

$(OBJD)/%.o : $(SRCD)/%.c $(DEPD)/%.d
	@echo "building object $@"
	@mkdir -p $(@D)
	@$(CXX) $(CXXFLAGS) -c $< -o $@

$(BIND)/$(NAME): $(OBJS)
	@echo "compiling $@"
	@mkdir -p $(BIND)
	@$(CXX) $(CXXFLAGS) $(LDDFLAGS) $(OBJS) -o $(BIND)/$(NAME)

install : $(BIND)/$(NAME)
	install -dZ ${DESTDIR}/etc/ly
	install -DZ $(BIND)/$(NAME) -t ${DESTDIR}/usr/bin
	install -DZ xsetup.sh -t ${DESTDIR}/etc/ly
	install -DZ ly.service -t ${DESTDIR}/usr/lib/systemd/system
	$(INSTALL)

uninstall:
	rm -rf ${DESTDIR}/etc/ly
	rm -f ${DESTDIR}/usr/bin/ly
	rm -f ${DESTDIR}/usr/lib/systemd/system/ly.service

clean:
	@echo "cleaning workspace"
	@rm -rf $(BIND)
	@rm -rf $(OBJD)
	@rm -rf $(DEPD)

distclean: clean

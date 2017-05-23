ly :
	mkdir -p ./build
	cc -std=c99 -pedantic -Wall -I src -L/usr/lib/security -lform -lncurses -lpam -lpam_misc -lX11 -l:pam_loginuid.so -o build/ly src/main.c src/utils.c src/login.c src/ncui.c src/desktop.c
	
install : ly
	install -d ${DESTDIR}/etc/ly
	install -D build/ly -t ${DESTDIR}/usr/bin
	install -D ly.service -t ${DESTDIR}/usr/lib/systemd/system
	ln -sf /usr/lib/security/pam_loginuid.so ${DESTDIR}/usr/lib/pam_loginuid.so
	
all : install

clean :
	rm -rf build/ly

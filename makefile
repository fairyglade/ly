ly :
	mkdir -p ./build
	cc -std=c99 -pedantic -Wall -I src -L/usr/lib/security -lform -lncurses -lpam -lpam_misc -lX11 -l:pam_loginuid.so -o build/ly src/main.c src/utils.c src/login.c src/ncui.c src/desktop.c
	
install : ly
	cp build/ly /bin/ly
	mkdir -p /etc/ly
	cp ly.service /lib/systemd/system/ly.service
	ln -sf /usr/lib/security/pam_loginuid.so /lib/pam_loginuid.so
	
all : install

clean :
	rm -rf build/ly

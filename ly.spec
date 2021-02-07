Name:       ly
Version:    0.5
Release:    2
Summary:    A TUI display manager
License:    WTFPL
BuildRequires: libxcb-devel
BuildRequires: pam-devel
Requires: libxcb
Requires: pam

%description
Ly is a lightweight TUI (ncurses-like) display manager for Linux and BSD.

%prep
make github

%build
make

%install
cd src
mkdir -p %{buildroot}/etc/
mkdir -p %{buildroot}/usr/bin/
mkdir -p %{buildroot}/usr/lib/systemd/system/
mkdir -p %{buildroot}/etc/pam.d/
DESTDIR="%{buildroot}" make install

%files
/usr/bin/ly
/usr/lib/systemd/system/ly.service
/etc/ly/lang/es.ini
/etc/ly/lang/pt.ini
/etc/ly/lang/ru.ini
/etc/ly/lang/en.ini
/etc/ly/lang/fr.ini
/etc/ly/lang/ro.ini
/etc/ly/xsetup.sh
/etc/ly/wsetup.sh
/etc/ly/config.ini
/etc/pam.d/ly

%changelog

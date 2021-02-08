Name:           ly
Version:        0.5.2
Release:        1
Summary:        A TUI display manager
License:        WTFPL
URL:            https://github.com/nullgemm/ly
Source:         https://github.com/dhalucario/ly/archive/v0.5.2.tar.gz
BuildRequires:  libxcb-devel
BuildRequires:  pam-devel
BuildRequires:  make
Requires:       libxcb
Requires:       pam

%description
Ly is a lightweight TUI (ncurses-like) display manager for Linux and BSD.

%prep
cd src
make github

%build
cd src
make

%install
cd src
mkdir -p %{buildroot}/etc/
mkdir -p %{buildroot}/usr/bin/
mkdir -p %{buildroot}/usr/lib/systemd/system/
mkdir -p %{buildroot}/etc/pam.d/
DESTDIR="%{buildroot}" make install
chmod -x %{buildroot}/etc/ly/config.ini
chmod -x %{buildroot}/etc/ly/lang/*

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

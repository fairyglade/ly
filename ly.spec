Name:           ly
Version:        0.5.3
Release:        1%{?dist}
Summary:        a TUI display manager

License:        WTFPL
URL:            https://github.com/fairyglade/ly
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  make automake
BuildRequires:  gcc gcc-c++
BuildRequires:  kernel-devel pam-devel
BuildRequires:  libxcb-devel

%description
Ly is a lightweight TUI (ncurses-like) display manager for Linux and BSD.

%prep
%autosetup


%build
%configure
%make_build


%install
%make_install systemd


%check


%files
%license license.md
%doc


%changelog
* Thu Sep 29 2022 Jerzy Drozdz <jerzy.drozdz@jdsieci.pl> - 0.5.3-1
- Initial build

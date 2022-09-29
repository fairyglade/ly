Name:           ly
Version:        0.5.3
Release:        1%{?dist}
Summary:        a TUI display manager

License:        WTFPL
URL:            https://github.com/fairyglade/ly.git
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  make automake
BuildRequires:  gcc gcc-c++
BuildRequires:  kernel-devel pam-devel
BuildRequires:  libxcb-devel

%systemd_requires

%description
Ly is a lightweight TUI (ncurses-like) display manager for Linux and BSD.

%prep
%autosetup


%build
%make_build


%install
%make_install installsystemd


%check


%files
%license license.md
%doc readme.md
%{_sysconfdir}/ly
%{_sysconfdir}/pam.d/*
%{_unitdir}/*
%{_bindir}/*


%post
%systemd_post %{name}.service

%preun
%systemd_preun %{name}.service

%changelog
* Thu Sep 29 2022 Jerzy Drozdz <jerzy.drozdz@jdsieci.pl> - 0.5.3-1
- Initial build

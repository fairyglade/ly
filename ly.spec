Name:           ly
Version:        0.5.3
Release:        5%{?dist}
Summary:        a TUI display manager

License:        WTFPL
URL:            https://github.com/fairyglade/ly.git
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  make automake
BuildRequires:  gcc gcc-c++
BuildRequires:  kernel-devel pam-devel
BuildRequires:  libxcb-devel
BuildRequires:  systemd-rpm-macros
BuildRequires:  gawk

Requires(post): policycoreutils-python-utils
Requires(postun): policycoreutils-python-utils
%systemd_requires

%description
Ly is a lightweight TUI (ncurses-like) display manager for Linux and BSD.

%prep
%autosetup


%build
%make_build
mv -f res/config.ini config.ini_orig
awk '{print}
/#save_file/{print "save_file = %{_sharedstatedir}/%{name}/save"}
/#wayland_specifier/{print "wayland_specifier = true"}
' config.ini_orig > res/config.ini


%install
%make_install installsystemd
install -m 755 -d %{buildroot}%{_sharedstatedir}/%{name}

%check


%files
%license license.md
%doc readme.md
%config(noreplace) %{_sysconfdir}/ly
%config %{_sysconfdir}/pam.d/*
%{_unitdir}/*
%{_bindir}/*
%{_sharedstatedir}/%{name}


%post
%systemd_post %{name}.service
semanage fcontext --add --ftype f --type xdm_exec_t '%{_bindir}/ly' 2>/dev/null || :
semanage fcontext --add --ftype a --type xdm_var_lib_t '%{_sharedstatedir}/%{name}(/.*)?' 2>/dev/null || :
restorecon -R %{_bindir}/ly %{_sharedstatedir}/%{name} || :

%preun
%systemd_preun %{name}.service

%postun
if [ $1 -eq 0 ];then
semanage fcontext --delete --ftype f --type xdm_exe_t '%{_bindir}/ly' 2>/dev/null || :
semanage fcontext --delete --ftype a --type xdm_var_lib_t '%{_sharedstatedir}/%{name}(/.*)?' 2>/dev/null || :
fi

%changelog
* Wed Oct 05 2022 Jerzy Drożdż <jerzy.drozdz@jdsieci.pl> - 0.5.3-5
- Added patches from PR #446

* Sun Oct 02 2022 Jerzy Drożdż <jerzy.drozdz@jdsieci.pl> - 0.5.3-4
- Fixed postun script

* Fri Sep 30 2022 Jerzy Drożdż <jerzy.drozdz@jdsieci.pl> - 0.5.3-3
- Added wayland_specifier = true

* Fri Sep 30 2022 Jerzy Drożdż <jerzy.drozdz@jdsieci.pl> - 0.5.3-2
- Added setting SELinux contexts
- Added configuration option for state files
- Configuration directory and pam service set to \%config

* Thu Sep 29 2022 Jerzy Drożdż <jerzy.drozdz@jdsieci.pl> - 0.5.3-1
- Initial build

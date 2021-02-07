# vim: sw=4:ts=4:et


%define relabel_files() \
restorecon -R /usr/bin/ly; \

%define selinux_policyver 3.14.6-34

Name:   ly_selinux
Version:	1.0
Release:	1%{?dist}
Summary:	SELinux policy module for ly

Group:	System Environment/Base		
License:	WTFPL
# This is an example. You will need to change it.
URL:		https://github.com/nullgemm/ly
Source0:	ly.pp
Source1:	ly.if
Source2:	ly_selinux.8


Requires: policycoreutils, libselinux-utils
Requires(post): selinux-policy-base >= %{selinux_policyver}, policycoreutils
Requires(postun): policycoreutils
BuildArch: noarch

%description
This package installs and sets up the  SELinux policy security module for ly.

%install
install -d %{buildroot}%{_datadir}/selinux/packages
install -m 644 %{SOURCE0} %{buildroot}%{_datadir}/selinux/packages
install -d %{buildroot}%{_datadir}/selinux/devel/include/contrib
install -m 644 %{SOURCE1} %{buildroot}%{_datadir}/selinux/devel/include/contrib/
install -d %{buildroot}%{_mandir}/man8/
install -m 644 %{SOURCE2} %{buildroot}%{_mandir}/man8/ly_selinux.8
install -d %{buildroot}/etc/selinux/targeted/contexts/users/


%post
semodule -n -i %{_datadir}/selinux/packages/ly.pp
if /usr/sbin/selinuxenabled ; then
    /usr/sbin/load_policy
    %relabel_files

fi;
exit 0

%postun
if [ $1 -eq 0 ]; then
    semodule -n -r ly
    if /usr/sbin/selinuxenabled ; then
       /usr/sbin/load_policy
       %relabel_files

    fi;
fi;
exit 0

%files
%attr(0600,root,root) %{_datadir}/selinux/packages/ly.pp
%{_datadir}/selinux/devel/include/contrib/ly.if
%{_mandir}/man8/ly_selinux.8.*


%changelog
* Wed Feb  3 2021 YOUR NAME <YOUR@EMAILADDRESS> 1.0-1
- Initial version


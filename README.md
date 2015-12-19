# ctneer

Manage options and script as single **dabfile* for easy container template creation.

Build container (and deploy VM) using single **dabfile**.

Uses dab command from https://pve.proxmox.com/wiki/Debian_Appliance_Builder

## dabfile format example (dab.conf extension)

```
# Optional: template name, instead of default OS-generated.
Template: mytemplate2016
Suite: jessie
Architecture: amd64
Name: minimal
Version: 8.2-1
Section: system
Maintainer: me <root@localhot>
Infopage: http://pve.proxmox.com/wiki/Debian_Appliance_Builder
Description: Debian Jessie 8.2 (minimal)
 A minimal Debian Jessie system including all required and important packages.

# Exec commands to create VM
%EXEC
dab init
dab bootstrap --minimal
dab install mc git subversion locales
dab exec apt-get -y purge postfix
ROOTDIR=`dab basedir`
echo "en_US.UTF-8" >${ROOTDIR}/etc/locale
echo "en_US.UTF-8 UTF-8" >${ROOTDIR}/etc/locale.gen
dab exec locale-gen
echo SSH PermitRootLogin
sed -e 's/^PermitRootLogin without-password/PermitRootLogin yes/' -i ${ROOTDIR}/etc/ssh/sshd_config
dab finalize
```

## Bare minimum %EXEC 

```
dab init
dab bootstrap --minimal
dab finalize
```

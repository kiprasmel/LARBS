# Remote lock screen

## Prerequisites

* You need xhost (xorg-xhost)

```sh
sudo pacman -S xorg-xhost
```

* MAKE SURE to read https://wiki.archlinux.org/index.php/Xhost

Warning - this is security related -- be careful.

## Making it a thing

### Local machine:

```sh
# run without root / sudo:
# xhost +SI:localuser:<THE_REMOTE_USERS_USERNAME_YOU_WANT_TO_ALLOW_ACCESS_TO_YOUR_SCREEN_WARNING_SECURITY_RELATED>
```

also, add the <REMOTE_USERS_USERNAME> to `ssh`s `AllowedUsers` list:

`/etc/ssh/sshd_config`:

```
AllowUsers <REMOTE_USERS_USERNAME>
```

### Remote machine:

```sh
ssh <REMOTE_USERS_USERNAME>@<IP_OF_MACHINE_YOU_WANT_TO_ACCESS> -X
# or use `-Y` flag

# then login

# after logging in:

# set display the same as your user from which you ran the 'xhost +SI:localuser:<REMOTE_USERS_USERNAME>' command
export DISPLAY=:0

# do stuff
i3lock
```

## See also

* https://wiki.archlinux.org/index.php/OpenSSH#X11_forwarding

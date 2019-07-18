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

Create a separate user with limited priviledges used only for this task.
Same as with wine -- make sure (!) to read https://wiki.archlinux.org/index.php/Wine#Running_Wine_under_a_separate_user_account

Then, after being aware of security implications:

```sh
# sudo useradd -m -s /bin/bash screenlockuser
# sudo passwd screenlockuser
```

> `-m` - create home (since we'll need the ~/.ssh/authorized_keys` to be available)
> `-s` - shell

Then run without root / sudo:

```sh
# xhost +SI:localuser:screenlockuser
```

& verify it's in the list:

```sh
xhost
```

also, add the screenlockuser to `ssh`s `AllowedUsers` list:

`/etc/ssh/sshd_config`:

```
AllowUsers screenlockuser
```

and make sure to enable these 2 options until the setup is complete:

```
PasswordAuthentication yes
ChallengeResponseAuthentication yes
```

(change them back to `no` after the setup is complete if you wish so)

and then restart the `sshd` service:

```sh
# sudo systemctl restart sshd --now
```

### Remote machine:

Copy your public key to remote machine's user's `~/.ssh/authorized_keys`:

```sh
# ssh-copy-id screenlockuser@<REMOTE_MACHINE_IP>
```

> Note - if nothing seems to be working:
> No output whatsoever -> verify that you're using the correct IP address.
> You are not even prompted with a password, but some messages appear -> restart the local machine (re-login at least at first, if still doesn't work - reboot)

Connect with `X11Forward` (`-X`) or `X11ForwardTrusted` (`-Y`)
```sh
ssh screenlockuser@<IP_OF_MACHINE_YOU_WANT_TO_ACCESS> -X
# or use `-Y` flag

# then login

# after logging in:

# set display the same as your user from which you ran the 'xhost +SI:localuser:screenlockuser' command
export DISPLAY=:0

# do stuff
i3lock
```

## See also

* https://wiki.archlinux.org/index.php/OpenSSH#X11_forwarding


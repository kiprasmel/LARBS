# etc

This repository SHALL be kept private

## Setup from scratch

* Install `etckeeper`

* Init

```sh
sudo etckeeper init
sudo etckeeper commit "Initial commit"
```

* Edit `/etc/etckeeper/etckeeper.conf`:

```diff
-PUSH_REMOTE=""
+PUSH_REMOTE="origin"
```

* Generate an ssh key

* Properly configure it (assuming it was placed in `/root/.ssh/`)

`/root/.ssh/config`:

```
Host github.com
	HostName	github.com
	User		git
	IdentityFile	~/.ssh/<<<YOUR_SSH_KEY_NAME_RSA>>>
```

* Create a **PRIVATE** github repo

* Add the `~/.ssh/<<<YOUR_SSH_KEY_NAME_RSA>>>.pub` (**.pub**) as a deploy key to github

* Add the repo as a remote

```sh
sudo etckeeper vcs remote add origin "git@github.com:<<<USERNAME>>>/<<<PRIVATE_REPO>>>"
```

* Try pushing to the **PRIVATE** repo

```sh
sudo etckeeper vcs push -u origin master
```



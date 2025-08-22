Build an image which automatically boots into kiosk mode to run an web application on Wayland.

This is a very simple system which includes one of the built-in config files, overrides some settings and uses a custom layer to:

* Install a set of packages over and above those provided by the base which are needed to run the kiosk
* Install and enable a systemd service to automatically run the kiosk at boot up

```text
examples/webkiosk/
|-- config
|   `-- kiosk.cfg
|-- kiosk.service.tpl
|-- meta
|   `-- kiosk.yaml
`-- README.md
```

Note: This relies on the base provided by the built-in configuration included by kiosk.cfg. Including this file is not necessary if kiosk.cfg specifies all attributes/layers.
To deploy a production kiosk system it is envisaged that a specific config file would be used, therefore giving full control over the base system to the developer.

Usage of `-S` allows rpi-image-gen to locate the config file automatically because the source directory (`./examples/webkiosk/`) is prioritised in the search path.

```bash
rpi-image-gen build -S ./examples/webkiosk/ -c kiosk.cfg
```

Since images are created with user login disabled by default, if you need to be able to log into this system via the console you'll need to specify a password (either in the config file or via the command line) or utilise SSH.

```
[device]
user1pass=Fo0bar!!
```

```bash
rpi-image-gen build -S ./examples/webkiosk/ -c kiosk.cfg -- IGconf_device_user1pass=Fo0bar!!
```
Or SSH:
```bash
# Enforce SSH public key auth only in this image
rpi-image-gen build -S ./examples/webkiosk/ -c kiosk.cfg -- 'IGconf_ssh_pubkey_user1=$(< ~/.ssh/id_rsa.pub)' IGconf_ssh_pubkey_only=y
```

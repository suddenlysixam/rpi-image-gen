Build a system with a custom config and multiple layers, declaring dependencies between layers and defining variables.

The config file used by this example specifies a custom layer to build a system from, which uses built-in and custom layers as dependencies. The custom layers declare additional variables to the config system which are used in the layers.

```text
|-- config
|   `-- acme-integration.cfg
|-- meta
|   |-- acme-developer.yaml
|   |-- acme-sdk-v1.yaml
|   `-- essential.yaml
|-- README.md
`-- setup-functions
```

```bash
rpi-image-gen build -S ./examples/custom_layers/ -c ./examples/custom_layers/config/acme-integration.cfg
```

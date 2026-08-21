# temp-control

`temp-control` is a small Zig fan controller for Dell PowerEdge-style systems. It samples temperatures from `sensors` first, falls back to `ipmitool`, and sets fan speed with `ipmitool raw`.

## Requirements

- Zig 0.14 or newer
- `ipmitool`
- `lm-sensors` if you want local sensor readings from `sensors`
- Permission to issue IPMI raw commands, which usually means running as `root` or via `sudo`

## Build

```sh
zig build
```

For a smaller release binary:

```sh
zig build -Doptimize=ReleaseSmall
```

The executable is placed at `zig-out/bin/temp-control`.

## Install

Copy the binary somewhere on your `PATH`, for example:

```sh
sudo install -m 755 zig-out/bin/temp-control /usr/local/bin/temp-control
```

## Configuration

Copy `config.example.conf` to `/etc/temp-control.conf` or point the program at a custom file with `--config`.

The file format is simple `key=value` pairs. Define the fan curve with one or more `point=temp,fan` entries:

```conf
point=0,15
point=40,50
point=60,100
interval_seconds=5
```

Recognized keys are:

- `point`
- `interval_seconds`

Curve points are sorted by temperature at load time and the controller linearly interpolates between neighboring points. Temperatures below the first point clamp to the first fan speed; temperatures above the last point clamp to the last fan speed.

## Run

Run a single control cycle:

```sh
temp-control --config /etc/temp-control.conf
```

Run as a daemon:

```sh
temp-control --daemon --config /etc/temp-control.conf
```

If no config file is present at `/etc/temp-control.conf`, the built-in defaults are used.

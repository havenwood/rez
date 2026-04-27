# Rez

Single-file version control. Just `diff` and `patch` under the hood.

## Install

```sh
gem install rez
```

## Usage

```sh
rez save file.rb initial version
rez save -m "fix the thing"
rez log
rez diff 1
rez show 1
rez restore 1
```

Name the file once. Pass it again only when more than one is tracked.

## Storage

```
.rez/<filename>/
  base        # first version (immutable)
  snapshot    # latest version
  log         # one line per rev: timestamp message
  1.patch     # forward diff r1 -> r2
  2.patch     # forward diff r2 -> r3
```

Endpoints are stored whole; intermediates are walked forward from `base`.

Requires `diff` and `patch`. Colored output via `git diff` when available.

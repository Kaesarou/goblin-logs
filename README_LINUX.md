# Goblin! log archiver — Linux

These files replace the Windows scripts in `goblin-logs`.

## Expected default layout

```text
~/Projects/
├── goblin/data/logs/
└── goblin-logs/
```

## Install

Copy the three scripts to the root of `goblin-logs`, then:

```bash
chmod +x archive_logs.sh copy_active_logs.py split_large_logs.py
```

Check that Git authentication works without prompting:

```bash
git push
```

## Test one cycle

```bash
./archive_logs.sh --once
```

Custom source path:

```bash
LOG_SOURCE=/path/to/goblin/data/logs ./archive_logs.sh --once
```

## Continuous mode

```bash
./archive_logs.sh
```

Background mode:

```bash
nohup ./archive_logs.sh > archive_logs.out 2>&1 &
echo $! > archive_logs.pid
```

Follow:

```bash
tail -f archive_logs.out
```

Stop:

```bash
kill "$(cat archive_logs.pid)"
```

Defaults:

- archive every 30 minutes;
- split above 45 MiB;
- abort before committing any file above GitHub's 100 MiB hard limit;
- retry `git push` at the next cycle after a network failure.

Compressed files are split by bytes. Reassemble before reading:

```bash
cat market.jsonl.part*.gz > market.jsonl.gz
```

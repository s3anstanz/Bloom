#!/usr/bin/env python3
"""Prints the exception and crashed-thread stack from macOS crash reports written during this CI run."""
import glob
import json
import os

for path in sorted(glob.glob(os.path.expanduser("~/Library/Logs/DiagnosticReports/*.ips"))):
    with open(path) as report:
        header = json.loads(report.readline())
        try:
            body = json.loads(report.read())
        except json.JSONDecodeError:
            continue
    print(f"== {os.path.basename(path)} ({header.get('app_name')})")
    print("exception:", json.dumps(body.get("exception")))
    images = body.get("usedImages", [])
    for thread in body.get("threads", []):
        if not thread.get("triggered"):
            continue
        print("crashed thread:", thread.get("queue") or thread.get("name") or "")
        for frame in thread.get("frames", [])[:40]:
            index = frame.get("imageIndex")
            image = images[index].get("name", "?") if index is not None and index < len(images) else "?"
            print(f"  {image:<28} {frame.get('symbol', hex(frame.get('imageOffset', 0)))}")

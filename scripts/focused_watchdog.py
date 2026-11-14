#!/usr/bin/env python3
"""Bound one focused command's process group, not total CircleCI billing time."""
import math, os, signal, subprocess, sys
from pathlib import Path

def main():
 seconds=float(sys.argv[1])
 if not math.isfinite(seconds) or not 0 < seconds <= 590:
  raise SystemExit('Focused command allowance must be >0 and <=590 seconds')
 out=Path(sys.argv[2]); out.mkdir(parents=True,exist_ok=True)
 p=subprocess.Popen(sys.argv[3:],start_new_session=True)
 status=1
 def stop_group(sig):
  try:os.killpg(p.pid,sig)
  except ProcessLookupError:pass
 def interrupted(signum,frame):raise InterruptedError(signum)
 signal.signal(signal.SIGTERM,interrupted);signal.signal(signal.SIGINT,interrupted)
 try:
  status=p.wait(timeout=seconds)
 except (subprocess.TimeoutExpired,InterruptedError) as exc:
  status=124 if isinstance(exc,subprocess.TimeoutExpired) else 130
  signal.signal(signal.SIGTERM,signal.SIG_IGN);signal.signal(signal.SIGINT,signal.SIG_IGN)
  stop_group(signal.SIGTERM)
  try:p.wait(timeout=5)
  except subprocess.TimeoutExpired:pass
 finally:
  # Always clean up remaining descendants, even if their parent has exited.
  stop_group(signal.SIGKILL)
  p.wait()
  if status<0:status=128-status
  (out/'focused-exit-status.txt').write_text(str(status)+'\n')
 return status
if __name__=='__main__':sys.exit(main())

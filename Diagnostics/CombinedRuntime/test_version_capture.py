import subprocess,sys
producer="import sys,time;print('Xcode 26.3',flush=True);time.sleep(0.1);print('Build version TEST',flush=True)"
import shlex
prefix="set -o pipefail; xcrun() { "+shlex.quote(sys.executable)+" -c "+shlex.quote(producer)+"; }; "
old="XCODE_VERSION=$(xcrun xcodebuild -version 2>/dev/null | head -n1 | awk '{ print $2 }')"
new="# Consume all output: head can close the pipe while xcodebuild still writes.\nXCODE_VERSION_OUTPUT=$(xcrun xcodebuild -version)\nprintf '%s\\n' \"$XCODE_VERSION_OUTPUT\"\nXCODE_VERSION=$(printf '%s\\n' \"$XCODE_VERSION_OUTPUT\" | awk 'NR == 1 { print $2 }')"
a=subprocess.run(["bash","-c",prefix+old],capture_output=True,text=True)
b=subprocess.run(["bash","-c",prefix+new+'\nprintf "%s" "$XCODE_VERSION"'],capture_output=True,text=True)
assert a.returncode!=0, "Old producer must observe closed pipe"
assert b.returncode==0 and b.stdout.endswith("26.3"),(b.returncode,b.stdout,b.stderr)
print("Short-read pipe reproduced:",a.returncode)
print("Full-output version capture passed")

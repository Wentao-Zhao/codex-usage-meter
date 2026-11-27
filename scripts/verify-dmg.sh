#!/bin/zsh
set -euo pipefail
[[ $# -eq 1 ]] || { print -u2 'Usage: verify-dmg.sh FILE'; exit 2; }
# hdiutil create may leave its write-once attachment open on newer macOS.
# Detach only unmounted, system-owned creation devices for this exact image.
python3 - "$1" <<'PY'
import os,plistlib,re,subprocess,sys
image=os.path.realpath(sys.argv[1])
data=plistlib.loads(subprocess.check_output(['hdiutil','info','-plist']))
for record in data.get('images',[]):
 if os.path.realpath(record.get('image-path',''))!=image or not record.get('system-image') or not record.get('writeable'):
  continue
 entities=record.get('system-entities',[])
 if any(e.get('mount-point') for e in entities):
  raise SystemExit('Refusing to detach a mounted image during verification')
 devices=[e.get('dev-entry','') for e in entities]
 device=next((d for d in devices if re.fullmatch(r'/dev/disk[0-9]+',d)),None)
 if not device: raise SystemExit('Creation attachment has no whole disk device')
 subprocess.run(['hdiutil','detach',device],check=True)
PY
/usr/bin/hdiutil verify "$1"

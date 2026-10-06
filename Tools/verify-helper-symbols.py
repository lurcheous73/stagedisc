#!/usr/bin/env python3
"""Check every bundled helper's Mach-O UUID against its actual debug symbols."""
import pathlib,re,subprocess,sys
if len(sys.argv)!=3:raise SystemExit('Usage: verify-helper-symbols.py BIN_DIRECTORY SYMBOLS_DIRECTORY')
binaries,symbols=map(pathlib.Path,sys.argv[1:])
def uuids(path):
    output=subprocess.run(['xcrun','dwarfdump','--uuid',str(path)],capture_output=True,text=True,check=True).stdout
    return set(re.findall(r'UUID: ([A-F0-9-]+) \(([^)]+)\)',output))
for name in ['ffmpeg','ffprobe','tsMuxeR','stagedisc-udf']:
    binary=binaries/name;dsym=symbols/(name+'.dSYM')
    if not binary.is_file() or not dsym.is_dir():raise SystemExit('Missing binary or dSYM: '+name)
    expected=uuids(binary);actual=uuids(dsym)
    if not expected or expected!=actual:raise SystemExit('Mismatched symbols: '+name)
    print('Matching binary/dSYM UUID:',name)

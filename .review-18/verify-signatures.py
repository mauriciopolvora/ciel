from pathlib import Path
import os, re, subprocess
root=Path(__file__).resolve().parent
source=(root.parent/'scripts/build.sh').read_text()
start=source.index('codesign --verify --strict --deep "$staged_app"')
end=source.index('rm -rf "$app_path"',start)
checker=source[start:end]
shell=root/'bash-3.2/bash'
if not shell.exists(): raise SystemExit('Bash 3.2 build not ready')
print(subprocess.check_output([str(shell),'--version'],text=True).splitlines()[0])
def pairs(job):
    lines=[]
    for raw in (root/f'job-{job}.log').read_text().splitlines():
        line=re.sub(r'^\S+Z ', '', raw)
        if line.startswith(('CodeDirectory ', 'TeamIdentifier=')): lines.append(line)
    assert len(lines)==4,(job,lines)
    return ['\n'.join(lines[i:i+2])+'\n' for i in (0,2)]
script=root/'signature-check.sh'
script.write_text('''#!/bin/bash
set -euo pipefail
staged_app="$1"
framework="$2"
codesign() {
    if [[ "$1" == --verify ]]; then return "${VERIFY_STATUS:-0}"; fi
    if [[ "$1" == -dv ]]; then
        if [[ ${DETAIL_STATUS:-0} != 0 ]]; then return "$DETAIL_STATUS"; fi
        cat "$2" >&2
    else
        cat "$ENTITLEMENT_FIXTURE"
    fi
}
'''+checker+'printf "ACCEPTED team=<%s> flags=<%s>\\n" "$app_team" "$flags"\n')
good=pairs(124658149578)
old=pairs(124657633890)
xml=(root.parent/'Resources/Ciel.entitlements').read_text()
def run(name,app,fw,expected,ents=xml,extra=None):
    (root/'app-signature.txt').write_text(app)
    (root/'framework-signature.txt').write_text(fw)
    (root/'entitlements.plist').write_text(ents)
    env={**os.environ,'ENTITLEMENT_FIXTURE':str(root/'entitlements.plist')}
    env.pop('app_team',None)
    if extra: env.update(extra)
    r=subprocess.run([str(shell),str(script),str(root/'app-signature.txt'),str(root/'framework-signature.txt')],capture_output=True,text=True,env=env,timeout=5)
    output=(r.stdout+r.stderr).strip().replace(str(root)+'/', '')
    assert r.returncode==expected,(name,r.returncode,expected,output)
    print(f'{name}: exit={r.returncode}; {output}')
for job in (124658149578,124658149928):
    run(f'Real fixed signature job {job}',*pairs(job),0)
for job in (124657633890,124657633741):
    run(f'Real old signature job {job}',*pairs(job),1)
run('Real fixed app with old framework',good[0],old[1],1)
dev=[s.replace('0x2(adhoc)','0x10000(runtime)').replace('not set','TESTTEAM01') for s in good]
run('Synthetic matching Developer ID teams',*dev,0)
run('Synthetic different Developer ID teams',dev[0],dev[1].replace('TESTTEAM01','TESTTEAM02'),1)
run('Synthetic Developer ID framework without runtime',dev[0],dev[1].replace('0x10000(runtime)','0x0(none)'),1)
run('Synthetic Developer ID app without runtime',dev[0].replace('0x10000(runtime)','0x0(none)'),dev[1],1)
run('Synthetic disabled library validation',*dev,1,ents=xml.replace('</dict>','<key>com.apple.security.cs.disable-library-validation</key><true/></dict>'))
run('Unparseable flags fail closed','TeamIdentifier=not set\n',good[1],1)
run('codesign details failure propagates',*good,65,extra={'DETAIL_STATUS':'65'})
run('codesign verification failure propagates',*good,65,extra={'VERIFY_STATUS':'65'})
print('All 13 parser/guard checks passed with the unmodified build.sh guard.')

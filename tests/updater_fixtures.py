"""Build disposable packages for native updater integration checks."""
from pathlib import Path
import hashlib
import json
import re
import runpy
import stat
import zipfile

ROOT = Path(__file__).resolve().parents[1]
runpy.run_path(str(ROOT/'scripts/build.py'), run_name='__main__')
current = re.fullmatch(r'\s*return "([0-9A-Za-z.+-]+)"\s*', (ROOT/'kindlevel.koplugin/kindlevel_version.lua').read_text()).group(1)
major, minor, _ = current.split('-')[0].split('.')
incoming = f'{major}.{int(minor)+1}.0'
folder = ROOT/'.cache/updater-tests'
folder.mkdir(parents=True, exist_ok=True)
archive = ROOT/f'dist/kindlevel-{current}.zip'
with zipfile.ZipFile(archive) as z:
    files = {name: z.read(name) for name in z.namelist()}
manifest = json.loads(files['kindlevel.koplugin/update-manifest.json'])
manifest['version'] = incoming
files['kindlevel.koplugin/kindlevel_version.lua'] = f'return "{incoming}"\n'.encode()
for item in manifest['files']:
    data = files['kindlevel.koplugin/'+item['path']]
    item.update(size=len(data), sha256=hashlib.sha256(data).hexdigest())
files['kindlevel.koplugin/update-manifest.json'] = json.dumps(manifest).encode()


def package(name, changes=None, link=False):
    contents = files.copy()
    contents.update(changes or {})
    with zipfile.ZipFile(folder/name, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        for path, data in contents.items():
            z.writestr(path, data)
        if link:
            entry = zipfile.ZipInfo('kindlevel.koplugin/assets/escape.svg')
            entry.create_system = 3
            entry.external_attr = (stat.S_IFLNK | 0o777) << 16
            z.writestr(entry, '/tmp/outside-kindlevel')


package('valid.zip')
package('traversal.zip', {'kindlevel.koplugin/../../outside-kindlevel': b'no'})
package('absolute.zip', {'/tmp/outside-kindlevel': b'no'})
package('symlink.zip', link=True)
package('missing-file.zip', {'kindlevel.koplugin/update-manifest.json': json.dumps({**manifest, 'files': manifest['files']+[{'path':'missing.lua', 'size':1, 'sha256':hashlib.sha256(b'x').hexdigest()}]}).encode()})
package('tampered-file.zip', {'kindlevel.koplugin/main.lua': b'return {}\n'})
package('wrong-version.zip', {'kindlevel.koplugin/kindlevel_version.lua': b'return "99.0.0"\n'})
bad = json.loads(json.dumps(manifest))
bad['files'][0]['path'] = '../outside-kindlevel'
package('bad-manifest.zip', {'kindlevel.koplugin/update-manifest.json': json.dumps(bad).encode()})
(folder/'info.json').write_text(json.dumps({'current':current, 'incoming':incoming, 'archive':f'/workspace/dist/kindlevel-{current}.zip'}))
print('Prepared updater package fixtures.')

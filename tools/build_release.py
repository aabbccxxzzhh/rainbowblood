"""Offline, hash-locked reconstruction of RainbowBlood 1.0.2. Never installs."""
from pathlib import Path
import argparse, hashlib, json, os, re, struct, subprocess, sys, tempfile, zipfile
sys.path.insert(0, str(Path(__file__).parent / 'shaders'))
from bundle8 import Oodle, Layout, CHUNK, parse, build
from native_shader_stages import stages
from dxc_assemble import Assembler

ROOT = Path(__file__).resolve().parents[1]
def sha(b): return hashlib.sha256(b).hexdigest()
def require(ok, message):
    if not ok: raise RuntimeError(message)
def edits(data, changes, binary=True):
    out = []; pos = 0
    for start, stop, value in changes:
        require(pos <= start <= stop <= len(data), 'Invalid or overlapping source edits')
        out.append(data[pos:start] if binary else ''.join(data[pos:start])); out.append(bytes.fromhex(value) if binary else value); pos = stop
    out.append(data[pos:] if binary else ''.join(data[pos:]))
    return b''.join(out) if binary else ''.join(out)
def tokens(text): return re.findall(r'[^\S\n]+|\n|[%!@]?[\w.]+|[^\w\s]', text)
def clean(text):
    return '\n'.join(l.split(';')[0].rstrip() for l in text.splitlines() if l.split(';')[0].strip()) + '\n'
def records(data, oodle):
    layout = parse(data)
    raw = b''.join(oodle.decompress(b) if len(b) != CHUNK else b for b in layout.blocks)[:layout.length]
    pos = 0; rows = {}
    for _ in range(struct.unpack_from('<I', layout.prefix, 8)[0]):
        start = pos; ext, name, count, zero = struct.unpack_from('<QQII', raw, pos); pos += 24
        require(zero == 0 and count < 65536, 'Invalid resource record')
        size = 0
        for _ in range(count):
            kind, flag, body, flag2, tail = struct.unpack_from('<IBIBI', raw, pos); pos += 14; size += body + tail
        pos += size; rows[(ext, name)] = raw[start:pos]
    require(pos == len(raw), 'Unconsumed resource bytes')
    return layout, rows
def split(data, oodle):
    rows = []
    at, size = struct.unpack_from('<II', data, 12)
    if size and data[at:at+4] == struct.pack('<I', 43): rows = list(stages(data, oodle))
    parts = []; pos = 0
    for meta, code in rows:
        parts.append(data[pos:meta['offset']]); pos = meta['offset'] + meta['packed_size']
    parts.append(data[pos:]); return parts, rows
def normalize_pe(data, metadata):
    """Restore release timestamps/CodeView GUID only; never patch executable code."""
    b = bytearray(data); pe = struct.unpack_from('<I', b, 60)[0]
    require(b[pe:pe+4] == b'PE\0\0', 'Invalid native PE')
    ts = metadata['timestamp']; struct.pack_into('<I', b, pe+8, ts)
    opt = pe+24; sz = struct.unpack_from('<H', b, pe+20)[0]
    sections = [struct.unpack_from('<IIII', b, t+8) for t in range(opt+sz, opt+sz+struct.unpack_from('<H', b, pe+6)[0]*40, 40)]
    def offset(rva):
        for vs, va, rs, ra in sections:
            if va <= rva < va+max(vs, rs): return ra+rva-va
        raise RuntimeError('Invalid PE debug RVA')
    rva, n = struct.unpack_from('<II', b, opt+112+6*8)
    for at in range(offset(rva), offset(rva)+n, 28):
        struct.pack_into('<I', b, at+4, ts); ptr = struct.unpack_from('<I', b, at+24)[0]
        if b[ptr:ptr+4] == b'RSDS': b[ptr+4:ptr+20] = bytes.fromhex(metadata['codeview_guid'])
    return bytes(b)
def verify(folder, lock):
    actual = {f.relative_to(folder).as_posix() for f in folder.rglob('*') if f.is_file()}
    require(actual == set(lock['files']), 'Release file list differs')
    for name, row in lock['files'].items():
        b = (folder/name).read_bytes()
        require(len(b) == row['size'] and sha(b) == row['sha256'], 'Release mismatch: '+name)

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--game', type=Path)
    ap.add_argument('--polychromatic', type=Path, help='Polychromatic 3.0.0 folder or original ZIP; read only')
    ap.add_argument('--dxc', type=Path, help='Windows SDK 10.0.26100.0 x64/dxc.exe')
    ap.add_argument('--output', type=Path, help='New build directory; must not exist')
    ap.add_argument('--verify', type=Path, help='Verify an existing extracted RainbowBlood folder, without building')
    args = ap.parse_args(); lock = json.loads((ROOT/'release/1.0.2.json').read_text())
    if args.verify:
        verify(args.verify.resolve(), lock); print('PASS: all 410 release files match'); return
    require(all((args.game, args.polychromatic, args.dxc, args.output)), 'Build requires --game, --polychromatic, --dxc and --output')
    game = args.game.resolve(); output = args.output.resolve()
    require(game not in output.parents and output != game and not output.exists(), 'Output must be new and outside the game directory')
    require(os.name == 'nt', 'Windows is required for DXC/Oodle and the native build')
    require(sha(args.dxc.read_bytes()) == '7c6918a0e2d4e437629fa8549f5ce800970494780f363bbbe1e3d3034f435aee', 'DXC version differs from release toolchain')
    mr = json.loads((ROOT/'release/material-recipes.json').read_text()); br = json.loads((ROOT/'release/bundle-recipes.json').read_text())
    polyzip = zipfile.ZipFile(args.polychromatic) if args.polychromatic.is_file() else None
    inputs = {}; materials = {}; program_cache = {}; bundle_cache = {}
    oodle = Oodle(game/'binaries/oo2core_9_win64.dll'); asm = Assembler(args.dxc.parent/'dxcompiler.dll')
    def read(name):
        if name not in inputs:
            if name.startswith('polychromatic/'):
                p = name.removeprefix('polychromatic/')
                b = polyzip.read('Polychromatic/'+p) if polyzip else (args.polychromatic/p).read_bytes()
            else: b = (game/'bundle'/name).read_bytes()
            expected = mr['inputs'].get(name) or br['inputs'].get(name)
            require(sha(b) == expected, 'Input version mismatch: '+name); inputs[name] = b
        return inputs[name]
    def material(name):
        if name not in materials: materials[name] = split(read(name), oodle)
        return materials[name]
    def source(ref): return material(ref['file'])[1][ref['stage_index']]
    output.mkdir(parents=True); dest = output/'RainbowBlood'; dest.mkdir()
    def save(name, b):
        require(sha(b) == lock['files'][name]['sha256'], 'Generated file mismatch: '+name)
        f = dest/name; f.parent.mkdir(parents=True, exist_ok=True); f.write_bytes(b)
    with tempfile.TemporaryDirectory(prefix='rainbowblood-build-') as tmp:
        scratch = Path(tmp)
        def program(key):
            if key not in program_cache:
                recipe = mr['programs'][key]
                if 'copy' in recipe: code = source(recipe['copy'])[1]
                else:
                    old = source(recipe['source'])[1]; f = scratch/'input.dxbc'; ll = scratch/'input.ll'; f.write_bytes(old)
                    subprocess.run([str(args.dxc.resolve()), '-dumpbin', str(f), '-Fc', str(ll)], check=True, capture_output=True)
                    text = clean(ll.read_text(encoding='utf-8')); require(sha(text.encode()) == recipe['source_text_sha256'], 'Shader disassembly differs')
                    text = edits(tokens(text), recipe['edits'], False); code = asm.assemble(text)
                    code += bytes(max(0, recipe['raw_size']-len(code)))
                require(sha(code) == key, 'Shader compilation differs: '+key); program_cache[key] = code
            return program_cache[key]
        for row in mr['materials']:
            parts, _ = material(row['base']); parts = list(parts)
            by_segment = {}
            for seg, a, b, value in row['changes']: by_segment.setdefault(seg, []).append([a,b,value])
            for seg, changes in by_segment.items(): parts[seg] = edits(parts[seg], changes)
            blocks = []
            for slot in row['slots']:
                if 'copy' in slot:
                    m, _ = source(slot['copy']); data = read(slot['copy']['file']); block = data[m['offset']:m['offset']+m['packed_size']]
                else:
                    block = oodle.compress(program(slot['program']), slot['level'])
                    require(len(block) <= slot['size'], 'Compressed program exceeds slot'); block += bytes(slot['size']-len(block))
                blocks.append(block)
            result = b''.join(parts[i]+blocks[i] for i in range(len(blocks))) + parts[-1]
            save(row['path'], result)
        print('PASS: 388 materials rebuilt', flush=True)
        for row in br['bundles']:
            def bundle(name):
                if name not in bundle_cache: bundle_cache[name] = records(read(name), oodle)
                return bundle_cache[name]
            header = edits(bundle(row['base'])[0].prefix[:268], row['header_edits']); rs = []
            for r in row['records']:
                key = tuple(int(v,16) for v in r['record']); b = edits(bundle(r['file'])[1][key], r['edits'])
                require(sha(b) == r['sha256'], 'Resource record differs'); rs.append(b)
            prefix = header + b''.join(b[:16]+bytes.fromhex(flag) for b,flag in zip(rs,row['index_flags']))
            raw = b''.join(rs); require(len(raw) == row['length'], 'Bundle logical length differs'); raw += bytes((-len(raw)) % CHUNK)
            blocks = []
            for i,c in enumerate(row['chunks']):
                b = raw[i*CHUNK:(i+1)*CHUNK]; b = b if c.get('stored') else oodle.compress(b,c['level'])
                require(len(b) <= c['size'], 'Bundle chunk exceeds slot'); blocks.append(b+bytes(c['size']-len(b)))
            layout = Layout(prefix, [c['size'] for c in row['chunks']], bytes.fromhex(row['table_padding']), row['length'], [bytes.fromhex(v) for v in row['chunk_padding']], blocks)
            save(row['path'], build(layout,blocks))
        print('PASS: 4 resource containers rebuilt', flush=True)
        env = dict(os.environ, CARGO_TARGET_DIR=str(scratch/'cargo-target'))
        subprocess.run(['cargo','build','--locked','--release'], cwd=ROOT/'native/reforge', env=env, check=True)
        save('bin/reforge.dll', normalize_pe((scratch/'cargo-target/release/reforge.dll').read_bytes(), lock['native_metadata']))
    for name in lock['files']:
        if name.startswith('payload/') or name == 'bin/reforge.dll': continue
        f = ROOT/'LICENSES'/Path(name).name if name.startswith('bin/') else ROOT/'src/RainbowBlood'/name
        b = f.read_bytes()
        lf = b.replace(b'\r\n',b'\n')
        for candidate in (b, lf, lf.replace(b'\n',b'\r\n')):
            if sha(candidate) == lock['files'][name]['sha256']: b = candidate; break
        save(name,b)
    verify(dest,lock)
    archive = output/'RainbowBlood-1.0.2.zip'
    with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for name,row in lock['files'].items():
            info = zipfile.ZipInfo('RainbowBlood/'+name, tuple(row['zip']['date_time'])); info.external_attr = row['zip']['external_attr']; info.create_system = row['zip']['create_system']; info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info,(dest/name).read_bytes(),compresslevel=9)
    print('PASS: 410/410 files match release 1.0.2')
    print('ZIP SHA256:',sha(archive.read_bytes()))
    print('Original ZIP identical:',sha(archive.read_bytes()) == lock['archive_sha256'])
if __name__ == '__main__':
    try: main()
    except (RuntimeError, OSError, subprocess.CalledProcessError) as exc:
        print('BUILD FAILED:',exc,file=sys.stderr); sys.exit(1)

"""Pure helpers extracted from the development builder; no build or install side effects."""
import hashlib, re, struct

def sha(d):return hashlib.sha256(d).hexdigest()

def h(s):
    b=s.encode();m=0xc6a4a7935bd1e995;mask=(1<<64)-1;v=len(b)*m&mask
    for at in range(0,len(b)//8*8,8):
        k=int.from_bytes(b[at:at+8],'little')*m&mask;k^=k>>47;k=k*m&mask;v=(v^k)*m&mask
    if b[len(b)//8*8:]:v=(v^int.from_bytes(b[len(b)//8*8:],'little'))*m&mask
    v^=v>>47;v=v*m&mask;v^=v>>47;return v

def assert_diff(a,b,allowed,label):
    assert len(a)==len(b),(label,'size changed')
    bad=[i for i,(x,y) in enumerate(zip(a,b)) if x!=y and i not in allowed]
    assert not bad,(label,'non-colour changes',bad[:20])

def parts(d):
    n=struct.unpack_from('<I',d,28)[0]
    return {d[p:p+4]:d[p+8:p+8+struct.unpack_from('<I',d,p+4)[0]] for p in struct.unpack_from('<'+'I'*n,d,32)}

def fp(v):
    value=struct.unpack('<f',struct.pack('<f',v))[0]
    return '0x'+struct.pack('>d',value).hex().upper()

def canonical_body(text):
    """Compare actual assembled DXIL operations, ignoring printing of floats.

    DXC may print input hexadecimal floating operands as decimal zero. Convert
    both representations to IEEE float32 bits; keep SSA, opcodes and operands.
    """
    match=re.search(r'define void @ps_main\(\) \{\n(.*?)\n\}',text,re.S)
    assert match,'pixel function missing'
    def number(m):
        value=struct.unpack('>d',bytes.fromhex(m[0][2:]))[0] if m[0].startswith('0x') else float(m[0])
        return 'F32_'+struct.pack('>f',value).hex()
    body='\n'.join(x.split(';')[0].strip() for x in match[1].splitlines() if x.split(';')[0].strip())
    return re.sub(r'0x[0-9A-Fa-f]{16}|-?\d+\.\d+[eE][+-]\d+',number,body)

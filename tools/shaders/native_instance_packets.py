"""Bounded v43 device parser exposing the native instance-copy contract.

The 16-byte copy records are consumed by D3D12Instancer::insert_instance.
No inferred HLSL packing: source descriptor/offset, packet offset and byte count
are retained verbatim. Stages and opaque binding tables remain raw slices.
"""
import struct
from native_shader_stages import Reader


def variants(data):
    r=Reader(data);rows=[]
    for outer in range(r.count()):
        for context in range(r.count()):
            for variant in range(r.count()):
                start=r.pos;r.states()
                for _ in range(r.count()):r.u32();r.states()
                stages=[r.stage(i) for i in range(6)]
                count_at=r.pos;count=r.count();copy_at=r.pos
                copies=[struct.unpack('<4I',r.take(16)) for _ in range(count)]
                meta_at=r.pos;meta=struct.unpack('<4I',r.take(16));r.array(20)
                rows.append(dict(outer=outer,context=context,variant=variant,start=start,end=r.pos,
                    stages=stages,count_at=count_at,copy_at=copy_at,copies=copies,meta_at=meta_at,meta=meta))
        r.u32()
    assert r.pos==len(data)
    return rows


def splice(data,edits):
    """Apply original-coordinate edits, rejecting overlap and ambiguous inserts."""
    out=[];pos=0
    for start,end,value in sorted(edits,key=lambda x:(x[0],x[1])):
        assert pos<=start<=end<=len(data),(pos,start,end)
        out.extend((data[pos:start],value));pos=end
    out.append(data[pos:]);return b''.join(out)

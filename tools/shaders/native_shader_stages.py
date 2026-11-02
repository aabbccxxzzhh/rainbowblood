"""Enumerate actual v43 stage records, not incidental DXBC byte patterns.

All parsing is bounded and consumes the entire native device table. Exposes
the opaque 64-bit program identifier so rewritten code cannot retain a stock
program identity. No stage binding/state/layout records are reserialized.
"""
import struct


class Reader:
    def __init__(self,data):self.data=data;self.pos=0
    def take(self,n):
        assert 0<=n<=len(self.data)-self.pos
        value=self.data[self.pos:self.pos+n];self.pos+=n;return value
    def u32(self):return struct.unpack('<I',self.take(4))[0]
    def count(self):
        value=self.u32();assert value<20000;return value
    def array(self,stride):self.take(self.count()*stride)
    def states(self):self.array(13)
    def stage(self,stage):
        rows=[]
        for _ in range(self.count()):
            packed_size=self.u32();offset=self.pos;self.take(packed_size)
            meta_offset=self.pos;api,raw_size,identity=struct.unpack('<IIQ',self.take(16))
            for stride in (24,24,28,28,28,28,28,16,12,16):self.array(stride)
            rows.append(dict(stage=stage,offset=offset,packed_size=packed_size,meta_offset=meta_offset,api=api,raw_size=raw_size,program_identity=identity))
        return rows
    def all(self):
        rows=[]
        for _ in range(self.count()):
            for _ in range(self.count()):
                for _ in range(self.count()):
                    self.states()
                    for _ in range(self.count()):self.u32();self.states()
                    for stage in range(6):rows.extend(self.stage(stage))
                    self.array(16);self.take(16);self.array(20)
            self.u32()
        assert self.pos==len(self.data),'device table not fully consumed'
        return rows


def stages(material,oodle):
    offset,size=struct.unpack_from('<II',material,12)
    shader=material[offset:offset+size]
    assert struct.unpack_from('<I',shader)[0]==43
    base,span=struct.unpack_from('<II',shader,40)
    for row in Reader(shader[base:base+span]).all():
        row=dict(row,offset=offset+base+row['offset'],meta_offset=offset+base+row['meta_offset'])
        packed=material[row['offset']:row['offset']+row['packed_size']]
        raw=packed if packed[:4]==b'DXBC' else oodle.decompress(packed,row['raw_size'])
        assert raw[:4]==b'DXBC' and len(raw)==row['raw_size']
        assert struct.unpack_from('<I',raw,24)[0]<=len(raw)
        yield row,raw

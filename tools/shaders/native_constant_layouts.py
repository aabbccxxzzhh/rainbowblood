"""Bounded read-only parser for native v43 constant-layout tables.

No native fields, padding, resource identifiers or compiled programs are edited.
Knowing a layout does not prove a new parameter's engine upload path.
"""
import struct

class Reader:
    def __init__(self,data):self.data=data;self.pos=0
    def take(self,n):
        assert 0<=n<=len(self.data)-self.pos
        p=self.pos;self.pos+=n;return p,self.data[p:self.pos]
    def u32(self):return struct.unpack('<I',self.take(4)[1])[0]
    def count(self):
        n=self.u32();assert n<20000;return n
    def array(self,stride):
        count_offset=self.pos;n=self.count();at,data=self.take(n*stride)
        return dict(count=n,count_offset=count_offset,offset=at,stride=stride,data=data)
    def all(self):
        rows=[]
        for _ in range(self.count()):
            start=self.pos;key=self.u32();size=self.u32();descriptors=self.array(16);buffers=[]
            for _ in range(self.count()):
                variables=self.array(20);meta_offset=self.pos;span=self.u32();offset=self.u32()
                entries=[struct.unpack_from('<5I',variables['data'],i*20) for i in range(variables['count'])]
                assert all(p+length<=span for kind,elements,key,p,length in entries)
                buffers.append(dict(variables=variables,entries=entries,size=span,offset=offset,meta_offset=meta_offset))
            resources=self.array(28);samplers=self.array(17);flags=[self.u32(),self.u32()]
            rows.append(dict(start=start,end=self.pos,key=key,size=size,descriptors=descriptors,buffers=buffers,resources=resources,samplers=samplers,flags=flags))
        assert self.pos==len(self.data),'constant table not fully consumed'
        return rows

def layouts(material):
    shader_offset,shader_size=struct.unpack_from('<II',material,12)
    shader=material[shader_offset:shader_offset+shader_size]
    assert struct.unpack_from('<I',shader)[0]==43
    start,size=struct.unpack_from('<II',shader,32)
    return Reader(shader[start:start+size]).all()

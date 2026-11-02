"""Fixed authored references for common unshaded blood base RGB.

References come from immutable source graphs/materials, not current pixels or
per-frame colour. Native brightness modulation and alpha therefore remain.
"""
import struct
from ground_base_colour import luminance

GENERIC_MATERIALS = ('2d0d326b8ed9973b','7605816fdb9fbf0a','439ceaa62e86c544','b40bdc1a7cab7691','9536ea359347051d')
GPU_BLOOD = '9abec0399c2ede2e'
NATIVE_PASSTHROUGH_REFS = {
    ('content/fx/particles/impacts/flesh/blood_broker_toxin_fountain_head_01',1170),
    ('content/fx/particles/impacts/flesh/blood_broker_toxin_fountain_head_01',4665),
}


def reference_pigment(ground_rgb, reference_red):
    assert reference_red in (11,20,25,33)
    return [v*255/reference_red for v in ground_rgb]


def endpoint_coefficients(ground_rgb, native_endpoints):
    peak=max(map(luminance,native_endpoints));assert peak>0
    return [v/peak for v in ground_rgb]


def variant_key(identity, reference_red=None):
    return identity if reference_red is None else f'{identity}-reference-{reference_red}'


def specialization_plan(sources, specs):
    bindings={};needed={}
    for source in sources:
        refs=sorted(source['material_refs'],key=lambda r:r['offset'])
        for offset in source['rgb_offsets']:
            preceding=[r for r in refs if r['offset']<offset];assert preceding
            ref=preceding[-1];identity=ref['identity']
            if identity not in GENERIC_MATERIALS:continue
            rgb=source['rgb_source_values'][str(offset)]
            assert rgb[1:]==[0,0] and rgb[0] in (11,20,25,33)
            red=int(rgb[0]);key=(source['source'],ref['offset'])
            assert key not in bindings,'Multiple colour graphs require a separate reference audit'
            bindings[key]=variant_key(identity,red);needed.setdefault(identity,set()).add(red)
    for source in sources:
        for ref in source['material_refs']:
            if ref['identity'] in GENERIC_MATERIALS:
                key=(source['source'],ref['offset'])
                if key in NATIVE_PASSTHROUGH_REFS:
                    assert key not in bindings,'Passthrough graph gained a red baseline; re-audit classification'
                    bindings[key]=None
                else:assert key in bindings,'Generic reference lacks native RGB baseline'
    expanded={k:dict(v,native_identity=k,reference_red=None) for k,v in specs.items() if k not in (*GENERIC_MATERIALS,'8a962954b5e8c9d3','8a67a07f71ccba42')}
    parent_refs={}
    for identity,reds in needed.items():
        for red in sorted(reds):
            expanded[variant_key(identity,red)]=dict(specs[identity],native_identity=identity,reference_red=red)
            parent=specs[identity].get('parent')
            if parent in ('8a962954b5e8c9d3','8a67a07f71ccba42'):parent_refs.setdefault(parent,set()).add(red)
    for identity,reds in parent_refs.items():
        for red in sorted(reds):expanded[variant_key(identity,red)]=dict(specs[identity],native_identity=identity,reference_red=red)
    return bindings,expanded


def material_contract(data):
    version,start,size,shader_offset,shader_size,blob_offset,blob_size=struct.unpack_from('<7I',data)
    assert version==62 and start==28
    pos=start
    def take(fmt):
        nonlocal pos
        v=struct.unpack_from('<'+fmt,data,pos);pos+=struct.calcsize('<'+fmt)
        return v[0] if len(v)==1 else v
    take('I');parent,secondary=take('QQ')
    for _ in range(take('I')):take('I')
    for _ in range(take('I')):take('IQ')
    for _ in range(take('I')):take('II')
    rows=[take('5I') for _ in range(take('I'))]
    span=take('I');values_at=pos;pos+=span
    for _ in range(take('I')):take('IB')
    for _ in range(take('I')):take('II')
    assert pos==start+size
    variables=[]
    for kind,elements,key,offset,stride in rows:
        assert kind<4 and elements==0
        variables.append(dict(key=f'{key:08x}',klass=kind,elements=elements,offset=values_at+offset,
                              value=list(struct.unpack_from('<'+'f'*(kind+1),data,values_at+offset))))
    return dict(size=len(data),parent=f'{parent:016x}',shader_offset=shader_offset,variables=variables)

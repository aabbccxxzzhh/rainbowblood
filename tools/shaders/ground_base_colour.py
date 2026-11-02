"""Ground hue transfer, preserving downstream native shading and alpha.

This changes colour before lighting, never final pixels. No empirical gain,
background cancellation, new particles, normal/mask edit or game launch.
The common Pox-derived luminance gain is an implementation policy: it does
not equalise different native base magnitudes or prove full material coverage.
ground-base.3 failed the user's 2026-10-10 visual test; see the correction doc.
"""
import math,re,struct

LUMA=(.2126,.7152,.0722)
NATIVE_POX_ENDPOINTS=tuple(tuple(struct.unpack('<f',struct.pack('<f',v))[0] for v in row) for row in ((.043,0,0),(.06,.035,.005)))


def luminance(rgb):
    assert len(rgb)==3 and all(math.isfinite(x) and x>=0 for x in rgb)
    return sum(a*b for a,b in zip(LUMA,rgb))


def pigment_for_luminance(ground_rgb,target_luminance):
    y=luminance(ground_rgb)
    assert y>0 and math.isfinite(target_luminance) and target_luminance>=0
    return [x*target_luminance/y for x in ground_rgb]


def retarget_endpoints(native_endpoints,accepted_endpoints,ground_rgb):
    """One scalar compensation preserves native gradient contrast/zero points.

    The accepted peak luminance is retained. Native endpoints are transformed
    by the same linear operator, so every native lerp weight stays unchanged.
    """
    native_peak=max(map(luminance,native_endpoints))
    accepted_peak=max(map(luminance,accepted_endpoints))
    assert native_peak>0
    gain=accepted_peak/native_peak
    return [pigment_for_luminance(ground_rgb,luminance(rgb)*gain) for rgb in native_endpoints]


def common_pigment(ground_rgb,accepted_rgb):
    """Coefficients of the same T(C) used for native Pox endpoint transfer.

    The packed generic red remains a native scalar. Dividing accepted RGB by
    its maximum discarded the deliberate compensation; no fitted gain is used.
    Equal coefficients do not imply equal base RGB across renderer families.
    """
    gain=luminance(accepted_rgb)/max(map(luminance,NATIVE_POX_ENDPOINTS))
    return pigment_for_luminance(ground_rgb,gain)


def generic_pigment(ground_rgb,accepted_rgb):
    # Y((native_red,0,0)) = native_red * LUMA[0].
    return [x*LUMA[0] for x in common_pigment(ground_rgb,accepted_rgb)]


def patch_pox_diffuse(text,coefficients):
    """Retarget only diffuse RGB; keep native red-derived neutral emission.

    Two of five native PS variants interpolate c_material_exports endpoints
    at 64/116. The first red use is a scalar added equally to RGB. Do not tint
    that scalar, normals, textures, fog, alpha, depth or branch conditions.
    """
    assert 'define void @ps_main()' in text
    pattern=''.join(r'  (%\d+) = '+op+r' fast float (%\d+), (%\d+)\n' for op in ('fsub',)*3+('fmul',)*3+('fadd',)*3)
    hits=list(re.finditer(pattern,text));assert len(hits)<=1
    if not hits:return text,dict(changed=False,reason='no diffuse endpoint interpolation')
    hit=hits[0];g=hit.groups();triples=[g[i:i+3] for i in range(0,27,3)]
    definitions={m[1]:m[2].split(';')[0].strip() for m in re.finditer(r'^\s*(%[\w.]+) = (.+)$',text,re.M)}
    for channel in range(3):
        delta,a,b=triples[channel];product,t,d=triples[3+channel];leaf,p,base=triples[6+channel]
        assert d==delta and p==product and base==b and t==triples[3][1]
        offsets=[]
        for endpoint in (a,b):
            m=re.fullmatch(r'extractvalue %dx.types.CBufRet.f32 (%\d+), ([0-3])',definitions[endpoint]);assert m
            load=re.fullmatch(r'call %dx.types.CBufRet.f32 @dx.op.cbufferLoadLegacy.f32\(i32 59, %dx.types.Handle (%\d+), i32 (\d+)\)',definitions[m[1]]);assert load
            offsets.append(int(load[2])*16+int(m[2])*4)
        assert offsets==[64+4*channel,116+4*channel],('unexpected endpoint exports',offsets)
    leaves=[row[0] for row in triples[6:]]
    before=text.splitlines();lines=list(before);changed=[];highlight=None
    for channel,node in enumerate(leaves):
        uses=[i for i,line in enumerate(before) if node in re.findall(r'%\d+',line.split(';')[0]) and not line.startswith('  '+node+' =')]
        assert len(uses)==(2 if channel==0 else 1),('unexpected diffuse uses',channel,uses)
        if channel==0:
            highlight=before[uses.pop(0)]
            assert re.fullmatch(r'  %\d+ = fmul fast float '+re.escape(node)+r', %\d+',highlight)
        at=uses[0];assert ' fmul fast float ' in before[at] or ' fadd fast float ' in before[at]
        lines[at]=re.sub(re.escape(node)+r'\b',f'%rb_diffuse_{channel}',before[at]);assert lines[at]!=before[at];changed.append(at)
    roots={re.match(r'\s*(%\d+) =',before[i])[1] for i in changed};cache={}
    def depends(node,seen=frozenset()):
        if node in roots:return True
        if node in cache:return cache[node]
        if node in seen:return False
        value=any(depends(x,seen|{node}) for x in re.findall(r'%[\w.]+',definitions.get(node,'')));cache[node]=value;return value
    for m in re.finditer(r'storeOutput.f32\(i32 5, i32 (\d+), i32 0, i8 ([0-3]), float (%[\w.]+)\)',text):
        if depends(m[3]):assert int(m[1])==0 and int(m[2])<3,'diffuse affects protected output'
    for line in before:
        if re.match(r'\s*(br |switch |call void )',line) and 'storeOutput' not in line:
            assert not any(depends(x) for x in re.findall(r'%[\w.]+',line))
    additions=[f'  %rb_y_{c} = fmul fast float {leaves[c]}, {fp(LUMA[c])}' for c in range(3)]
    additions+=['  %rb_y_rg = fadd fast float %rb_y_0, %rb_y_1','  %rb_native_y = fadd fast float %rb_y_rg, %rb_y_2']
    additions+=[f'  %rb_diffuse_{c} = fmul fast float %rb_native_y, {fp(coefficients[c])}' for c in range(3)]
    edited='\n'.join(lines)+'\n';at=edited.index(hit[0])+len(hit[0]);edited=edited[:at]+'\n'.join(additions)+'\n'+edited[at:]
    assert highlight in edited and all(before[i]==lines[i] for i in range(len(lines)) if i not in changed)
    assert [x for x in before if 'storeOutput' in x]==[x for x in edited.splitlines() if 'storeOutput' in x]
    return edited,dict(changed=True,native_diffuse_leaves=leaves,native_neutral_emission_definition='IDENTICAL',changed_native_lines=[i+1 for i in changed],native_lerp_light_fog_alpha_normal_texture='IDENTICAL',added_RGB_arithmetic=8,protected_outputs='NO RGB DEPENDENCY')


def fp(value):
    value=struct.unpack('<f',struct.pack('<f',value))[0]
    return '0x'+struct.pack('>d',value).hex().upper()


def signature_semantics(text):
    metadata={m[1]:m[2] for m in re.finditer(r'^!(\d+) = !\{(.*?)\}$',text,re.M)}
    result=[]
    for entry in metadata.values():
        match=re.match(r'i32 (\d+), !"([^"]+)", i8 \d+, i8 \d+, !(\d+),',entry)
        if match:
            index=int(re.fullmatch(r'i32 (\d+)',metadata[match[3]])[1])
            result.append((int(match[1]),match[2],index))
    return result


def patch_generic_vertex(text,pigment):
    """Move generic tint to float VS RGB; native CPU ColourGraph remains red.

    Authored generic graphs are proven red-only. Read their exact native red
    byte (physical COLOR component2 after CPU BGR storage), then multiply by
    pigment. Existing main/dark RGB outputs and all downstream operations stay.
    A transitive dependency guard rejects colour inputs affecting geometry,
    normals, fog, alpha, UVs or any other output than CUSTOM1/3 RGB.
    """
    assert re.search(r'define void @vs_main\(\)',text)
    semantics=signature_semantics(text)
    ids={sid for sid,name,index in semantics if name=='COLOR' and index==0}
    if not ids:return text,dict(changed=False,reason='no COLOR0 signature')
    assert len(ids)==1
    sid=ids.pop()
    pattern=rf'^(\s*)(%\d+) = call float @dx\.op\.loadInput\.f32\(i32 4, i32 {sid}, i32 0, i8 ([0-2]), i32 undef\)(.*)$'
    loads=list(re.finditer(pattern,text,re.M))
    if not loads:return text,dict(changed=False,reason='no RGB reads')
    assert sorted(int(m[3]) for m in loads)==[0,1,2], 'partial/duplicate RGB reads require separate audit'
    roots={m[2] for m in loads}
    definitions={m[1]:m[2].split(';')[0] for m in re.finditer(r'^\s*(%[\w.]+) = (.+)$',text,re.M)}
    cache={}
    def depends(node,seen=frozenset()):
        if node in roots:return True
        if node in cache:return cache[node]
        if node in seen:return False
        value=any(depends(x,seen|{node}) for x in re.findall(r'%[\w.]+',definitions.get(node,'')))
        cache[node]=value;return value
    permitted={sig for sig,name,index in semantics if name=='CUSTOM' and index in (1,3)}
    affected=[]
    for match in re.finditer(r'storeOutput\.f32\(i32 5, i32 (\d+), i32 0, i8 ([0-3]), float (%[\w.]+)\)',text):
        output,component,node=int(match[1]),int(match[2]),match[3]
        if depends(node):
            assert output in permitted and component<3,('RGB affects protected output',output,component)
            affected.append((output,component))
    if not affected:return text,dict(changed=False,reason='RGB has no outputs')
    # Non-output side effects/branches must not depend on colour either.
    for line in text.splitlines():
        if re.match(r'\s*(br |switch |call void )',line) and 'storeOutput' not in line:
            assert not any(depends(node) for node in re.findall(r'%[\w.]+',line)), 'RGB affects side effect/control'
    # Named SSA additions do not renumber native unnamed definitions.
    insert=f'  %rb_native_red = call float @dx.op.loadInput.f32(i32 4, i32 {sid}, i32 0, i8 2, i32 undef)\n'
    def replace(match):
        return f'{match[1]}{match[2]} = fmul fast float %rb_native_red, {fp(pigment[2-int(match[3])])}{match[4]}'
    edited=re.sub(pattern,replace,text,flags=re.M)
    first=re.search(r'^\s*%\d+ = fmul fast float %rb_native_red,',edited,re.M)
    edited=edited[:first.start()]+insert+edited[first.start():]
    old_stores=[x for x in text.splitlines() if 'storeOutput' in x]
    assert old_stores==[x for x in edited.splitlines() if 'storeOutput' in x]
    return edited,dict(changed=True,colour_input_sig=sid,affected_rgb_outputs=affected,protected_outputs='NO RGB DEPENDENCY',alpha_read='IDENTICAL',native_body_changes='3 RGB reads replaced;1 same-channel read inserted')


def patch_baked_endpoints(text,endpoints):
    """Retarget the two proven baked Pox RGB endpoints without flattening t."""
    markers=('0x3F91687280000000','0x3FA60418A0000000','0x3FA1EB8520000000','0x3F747AE140000000')
    if markers[0] not in text:return text,dict(changed=False)
    a,b=endpoints;delta=[right-left for left,right in zip(a,b)]
    lines=text.splitlines();before=list(lines);changes=[]
    for marker,value in zip(markers,(delta[0],a[0],delta[1],delta[2])):
        hits=[i for i,line in enumerate(before) if marker in line]
        assert len(hits)==1,(marker,hits)
        at=hits[0];lines[at]=lines[at].replace(marker,fp(value));changes.append(at)
        if marker not in markers[2:]:continue
        channel=1 if marker==markers[2] else 2
        name='green' if channel==1 else 'blue'
        match=re.fullmatch(r'\s*(%\d+) = fmul fast float (%\d+), '+re.escape(marker),before[at].split(';')[0].rstrip())
        assert match
        delta_node,fog=match.groups()
        uses=[(i,re.fullmatch(r'\s*(%\d+) = fmul fast float '+re.escape(delta_node)+r', (%\d+)',line.split(';')[0].rstrip())) for i,line in enumerate(before) if i>at]
        uses=[(i,m) for i,m in uses if m];assert len(uses)==1
        at,m=uses[0];output,t=m.groups()
        lines[at]=(f'  %rb_{name}_delta = fmul fast float {delta_node}, {t}\n'
                   f'  %rb_{name}_base = fmul fast float {fog}, {fp(a[channel])}\n'
                   f'  {output} = fadd fast float %rb_{name}_delta, %rb_{name}_base')
        changes.append(at)
    assert len(changes)==6
    assert all(lines[i]==before[i] for i in range(len(lines)) if i not in changes)
    assert [x for x in lines if 'storeOutput' in x]==[x for x in before if 'storeOutput' in x]
    # Changed original colour definitions cannot reach native alpha/depth or
    # any branch/side effect. New definitions are used only by those RGB nodes.
    changed_nodes={re.match(r'\s*(%\d+) =',before[i])[1] for i in changes}
    definitions={m[1]:m[2].split(';')[0] for m in re.finditer(r'^\s*(%[\w.]+) = (.+)$',text,re.M)}
    def depends(node,seen=frozenset()):
        if node in changed_nodes:return True
        if node in seen:return False
        return any(depends(x,seen|{node}) for x in re.findall(r'%[\w.]+',definitions.get(node,'')))
    for match in re.finditer(r'storeOutput\.f32\(i32 5, i32 (\d+), i32 0, i8 ([0-3]), float (%[\w.]+)\)',text):
        if depends(match[3]):assert int(match[1])==0 and int(match[2])<3,'baked RGB affects protected output'
    for line in text.splitlines():
        if re.match(r'\s*(br |switch |call void )',line) and 'storeOutput' not in line:
            assert not any(depends(node) for node in re.findall(r'%[\w.]+',line))
    return '\n'.join(lines)+'\n',dict(changed=True,original_colour_lines=[i+1 for i in changes],native_lerp_weight='IDENTICAL',alpha_fog_light_texture='IDENTICAL',added_operations='4 colour-only arithmetic operations')

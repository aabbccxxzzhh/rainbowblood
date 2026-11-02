"""Bound the complete visible premultiplied RGB, not a pre-fog surface term.

Replace the failed early shoulder; preserve the existing emission-control fix.
The accepted screen reference is a calibration choice, not a measured runtime
Bloom threshold. Arbitrary exposure can still move diffuse into Bloom.
"""
import re
from shader_common import fp, canonical_body
from airborne_diffuse_floor import definitions

NAME=r'%[\w.]+'
PREFIX='rb_final_'
CEILING=0.1513129248657568
KNEE=CEILING/2
EPSILON=1e-8


def patch(source):
    has_early='%rb_bloom_scale' in source
    coverage=None
    if not has_early:
        # Two additional private orange chainsword parents were omitted by the
        # first two tests. Admit only their verified premultiplied HDR outputs;
        # never their 1/pi atlas permutations or the liquid GBuffer material.
        if '%rb_oh_max' not in source:return source,None
        d=definitions(source)
        m=re.fullmatch(r'call float @dx.op.binary.f32\(i32 35, float ('+NAME+r'), float ('+NAME+r')\)',d['%rb_oh_hi']);assert m
        q=re.fullmatch(r'call float @dx.op.binary.f32\(i32 35, float %rb_oh_hi, float ('+NAME+r')\)',d['%rb_oh_max']);assert q
        leaves=[m[1],m[2],q[1]]
        if all(re.fullmatch(r'fmul fast float '+NAME+r', 0x3FD45F3060000000',d[n]) for n in leaves):return source,None
        alpha=re.search(r'storeOutput.f32\(i32 5, i32 0, i32 0, i8 3, float ('+NAME+r')\)',source)[1]
        direct=all((m:=re.fullmatch(r'fmul fast float ('+NAME+r'), ('+NAME+r')',d[n])) and alpha in m.groups() for n in leaves)
        if not direct:
            # Native fourth layer can subtract an additive-mode term from the
            # blend alpha. Coverage still comes from its original saturated
            # base alpha; do not erase RGB just because blend alpha can be zero.
            m=re.fullmatch(r'fsub fast float ('+NAME+r'), ('+NAME+r')',d[alpha]);assert m
            coverage,term=m.groups()
            q=re.fullmatch(r'fmul fast float '+re.escape(coverage)+r', ('+NAME+r')',d[term]);assert q
            mode=q[1];q=re.fullmatch(r'extractvalue %dx.types.CBufRet.f32 ('+NAME+r'), 0',d[mode]);assert q
            q=re.fullmatch(r'call %dx.types.CBufRet.f32 @dx.op.cbufferLoadLegacy.f32\(i32 59, %dx.types.Handle ('+NAME+r'), i32 5\)',d[q[1]]);assert q
            assert d[q[1]]=='call %dx.types.Handle @dx.op.createHandle(i32 57, i8 2, i32 1, i32 1, i1 false)'
            assert d[coverage].startswith('call float @dx.op.unary.f32(i32 7, float ')
            memo={}
            def depends(n):
                if n==coverage:return True
                if n in memo:return memo[n]
                memo[n]=False;memo[n]=any(depends(x) for x in re.findall(NAME,d.get(n,'')));return memo[n]
            assert all(depends(n) for n in leaves)
        assert not re.search(r'storeOutput.f32\(i32 5, i32 [1-9]',source)
    assert '%'+PREFIX not in source
    original_defs=definitions(source)
    early=list(re.finditer(r'^  %rb_bloom_[^\n]+\n',source,re.M))
    assert len(early)==(13 if has_early else 0)
    old_lines=[m[0] for m in early]
    source_replacements=[]
    base=source
    for i in range(3 if has_early else 0):
        m=re.fullmatch(r'fmul fast float ('+NAME+r'), %rb_bloom_scale',original_defs[f'%rb_bloom_surface{i}']);assert m
        surface=m[1]
        hits=list(re.finditer(r'^  ('+NAME+r') = fadd fast float %rb_bloom_surface'+str(i)+r', ('+NAME+r')[^\n]*',base,re.M))
        assert len(hits)==1
        row=hits[0];old=row[0];new=f'  {row[1]} = fadd fast float {surface}, {row[2]}'
        base=base[:row.start()]+new+base[row.end():]
        source_replacements.append((old,new))
    base=re.sub(r'^  %rb_bloom_[^\n]+\n','',base,flags=re.M)
    assert '%rb_bloom_' not in base
    stores=list(re.finditer(r'^  call void @dx.op.storeOutput.f32\(i32 5, i32 0, i32 0, i8 ([0-3]), float ('+NAME+r')\)[^\n]*',base,re.M))
    assert [x[1] for x in stores]==['0','1','2','3']
    rgb=[x[2] for x in stores[:3]];alpha=stores[3][2]
    coverage=coverage or alpha
    defs=definitions(base)
    assert all(x in defs for x in rgb+[alpha])
    # All three final RGB leaves are evaluated AFTER native fog, alpha and any
    # existing orange conversion. Final zero/visible phi merges stay native.
    lines=[
        f'  %rb_final_alpha = call float @dx.op.unary.f32(i32 7, float {coverage})',
        f'  %rb_final_knee = fmul fast float %rb_final_alpha, {fp(KNEE)}',
        f'  %rb_final_headroom = fmul fast float %rb_final_alpha, {fp(CEILING-KNEE)}',
        f'  %rb_final_m0 = call float @dx.op.binary.f32(i32 35, float {rgb[0]}, float {rgb[1]})',
        f'  %rb_final_peak = call float @dx.op.binary.f32(i32 35, float %rb_final_m0, float {rgb[2]})',
        '  %rb_final_sub = fsub fast float %rb_final_peak, %rb_final_knee',
        '  %rb_final_excess = call float @dx.op.binary.f32(i32 35, float %rb_final_sub, float 0.000000e+00)',
        '  %rb_final_den0 = fadd fast float %rb_final_excess, %rb_final_headroom',
        f'  %rb_final_den = call float @dx.op.binary.f32(i32 35, float %rb_final_den0, float {fp(EPSILON)})',
        '  %rb_final_ratio = fdiv fast float %rb_final_excess, %rb_final_den',
        '  %rb_final_tail = fmul fast float %rb_final_headroom, %rb_final_ratio',
        '  %rb_final_limited = fadd fast float %rb_final_knee, %rb_final_tail',
        f'  %rb_final_divisor = call float @dx.op.binary.f32(i32 35, float %rb_final_peak, float {fp(EPSILON)})',
        '  %rb_final_scale0 = fdiv fast float %rb_final_limited, %rb_final_divisor',
        '  %rb_final_scale = call float @dx.op.binary.f32(i32 36, float %rb_final_scale0, float 1.000000e+00)',
    ]+[f'  %rb_final_rgb{i} = fmul fast float {n}, %rb_final_scale' for i,n in enumerate(rgb)]
    edited=base
    replacements=[]
    for i,m in reversed(list(enumerate(stores[:3]))):
        new=m[0].replace('float '+m[2]+')',f'float %rb_final_rgb{i})')
        edited=edited[:m.start()]+new+edited[m.end():];replacements.append((m[0],new))
    at=edited.index('  call void @dx.op.storeOutput.f32')
    edited=edited[:at]+'\n'.join(lines)+'\n'+edited[at:]
    assert 'declare float @dx.op.unary.f32' in edited and 'declare float @dx.op.binary.f32' in edited
    guard=dict(final_input_rgb=rgb,alpha=alpha,coverage_input=coverage,added_lines=lines,store_replacements=replacements,
               removed_early_lines=old_lines,restored_surface_additions=source_replacements,
               knee=KNEE,ceiling=CEILING,alpha_store=stores[3][0],
               reference='Accepted screen-matte display reference .5, conditional exposure=1 model only',
               runtime_Bloom_threshold_or_exposure_measured=False)
    verify_saved(edited,guard,source)
    return edited,guard


def restore_input(source,guard):
    restored=re.sub(r'^  %rb_final_[^\n]+\n','',source,flags=re.M)
    for old,new in guard['store_replacements']:
        assert restored.count(new)==1;restored=restored.replace(new,old,1)
    # Restore the earlier shoulder at its exact original location.
    if guard['restored_surface_additions']:
        first=guard['restored_surface_additions'][0][1]
        assert restored.count(first)==1
        at=restored.index(first)
        restored=restored[:at]+''.join(guard['removed_early_lines'])+restored[at:]
    for old,new in guard['restored_surface_additions']:
        assert restored.count(new)==1;restored=restored.replace(new,old,1)
    return restored


def verify_saved(source,guard,original=None):
    defs=definitions(source)
    for line in guard['added_lines']:
        n,e=line.strip().split(' = ',1);assert defs[n]==e
    assert '%rb_bloom_' not in source
    assert guard['alpha_store'] in source
    if original is not None:
        assert canonical_body(restore_input(source,guard))==canonical_body(original)
        # Removing the early cap must not re-enable any previous E=0 scalar.
        for n,e in definitions(original).items():
            if e=='fadd fast float 0.000000e+00, 0.000000e+00':assert defs[n]==e
    return dict(final_RGB_after_native_fog_alpha_and_orange_is_bounded=True,
                original_alpha_store_and_shape_control_exact=True,earlier_shoulder_replaced_not_stacked=True,
                emission_control_removal_retained=True,no_added_samples_bindings_branches=True,
                final_overbright_fog_RGB_also_compressed=True,actual_Bloom_visual='NOT_TESTED')

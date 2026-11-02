"""Orange RGB adapters. No emission, AO, normal, alpha, mask or motion edits."""
import re
from ground_base_colour import fp

REFERENCE=[253/253,131/253,31/253]
BASE=[3.2,.8,.032]


def declarations(edited,original):
    added=[]
    for name,args in [('binary','i32, float, float'),('unary','i32, float')]:
        if '@dx.op.'+name+'.f32' in edited and not re.search(r'^declare float @dx.op\.'+name+r'\.f32\(',original,re.M):
            row=f'declare float @dx.op.{name}.f32({args})\n';added.append(row);edited+='\n'+row
    return edited,added


def gate(rgb,prefix='rb_of'):
    r,g,b=rgb
    rows=[f'  %{prefix}_dr = fsub fast float {r}, {b}',f'  %{prefix}_dg = fsub fast float {g}, {b}',
          f'  %{prefix}_lo = fmul fast float %{prefix}_dr, {fp(.08)}',f'  %{prefix}_hi = fmul fast float %{prefix}_dr, {fp(.45)}',
          f'  %{prefix}_c0 = fcmp fast ogt float {r}, {fp(.08)}',f'  %{prefix}_c1 = fcmp fast ogt float %{prefix}_dg, %{prefix}_lo',
          f'  %{prefix}_c2 = fcmp fast olt float %{prefix}_dg, %{prefix}_hi',f'  %{prefix}_c3 = fcmp fast ogt float %{prefix}_dr, {fp(1e-8)}',
          f'  %{prefix}_a0 = and i1 %{prefix}_c0, %{prefix}_c1',f'  %{prefix}_a1 = and i1 %{prefix}_c2, %{prefix}_c3',
          f'  %{prefix}_own = and i1 %{prefix}_a0, %{prefix}_a1',
          f'  %{prefix}_safe = call float @dx.op.binary.f32(i32 35, float {r}, float {fp(1e-8)})',
          f'  %{prefix}_ratio1 = fdiv fast float {g}, %{prefix}_safe',f'  %{prefix}_ratio2 = fdiv fast float {b}, %{prefix}_safe']
    return rows,f'%{prefix}_own'


def stores(text):
    return list(re.finditer(r'^  call void @dx.op.storeOutput.f32\(i32 5, i32 0, i32 0, i8 ([0-2]), float (%\w+)\).*$',text,re.M))


def surface(text,rgb,weight=None,bases=None,green_scale=1.):
    hits=stores(text);assert len(hits)==3 and [int(h[1]) for h in hits]==[0,1,2]
    nodes=[h[2] for h in hits];rows,own=gate(rgb)
    if green_scale!=1.:
        at=next(i for i,s in enumerate(rows) if s.startswith('  %rb_of_ratio1 ='))
        rows[at]=rows[at].replace('%rb_of_ratio1 =','%rb_of_input_ratio1 =')
        rows.insert(at+1,f'  %rb_of_ratio1 = fmul fast float %rb_of_input_ratio1, {fp(green_scale)}')
    rows += [f'  %rb_of_r = call float @dx.op.binary.f32(i32 36, float {nodes[0]}, float 1.000000e+00)']
    if weight:
        assert bases and len(bases)==3
        rows += [f'  %rb_of_wet = fcmp fast ogt float {weight}, 0.000000e+00',f'  %rb_of_apply = and i1 {own}, %rb_of_wet',
                 f'  %rb_of_dry = fsub fast float 1.000000e+00, {weight}']
        own='%rb_of_apply'
        for i,base in enumerate(bases):rows += [f'  %rb_of_base{i} = fmul fast float {base}, %rb_of_dry']
        rows += ['  %rb_of_signal0 = fsub fast float %rb_of_r, %rb_of_base0',
                 '  %rb_of_signal = call float @dx.op.binary.f32(i32 35, float %rb_of_signal0, float 0.000000e+00)']
    for i in (1,2):
        value='%rb_of_signal' if weight else '%rb_of_r'
        rows += [f'  %rb_of_t{i} = fmul fast float {value}, %rb_of_ratio{i}']
        if weight:rows += [f'  %rb_of_v{i} = fadd fast float %rb_of_base{i}, %rb_of_t{i}']
    values=['%rb_of_r']+[f'%rb_of_v{i}' if weight else f'%rb_of_t{i}' for i in (1,2)]
    for i in range(3):rows += [f'  %rb_of_final{i} = select i1 {own}, float {values[i]}, float {nodes[i]}']
    at=text.index('  call void @dx.op.storeOutput.f32');edited=text[:at]+'\n'.join(rows)+'\n'+text[at:]
    for i,hit in enumerate(hits):edited=edited.replace(hit[0],hit[0].replace('float '+nodes[i]+')',f'float %rb_of_final{i})'),1)
    reversed='\n'.join(x for x in edited.splitlines() if not x.startswith('  %rb_of_'))+'\n'
    for i,node in enumerate(nodes):reversed=reversed.replace('float %rb_of_final'+str(i)+')','float '+node+')')
    assert reversed==text
    edited,_=declarations(edited,text)
    return edited,dict(kind='surface',leaves=rgb+nodes+([weight]+bases if weight else []),rgb=rgb,original_RGB_nodes=nodes,weight=weight,bases=bases,green_scale=green_scale,added_prefix='rb_of_',outputs=[f'%rb_of_final{i}' for i in range(3)],changed_outputs='GBuffer0 RGB only',all_other_code_restored=True)


def wound(text):
    if '  %rbw_b0 = fmul fast float %rbw_strength, %rbw_g0' not in text:return text,None
    rows,own=gate(['%rbw_g0','%rbw_g1','%rbw_g2'])
    for i in range(3):rows += [f'  %rb_of_raw{i} = fmul fast float %rbw_strength, %rbw_g{i}']
    rows += ['  %rb_of_r = call float @dx.op.binary.f32(i32 36, float %rb_of_raw0, float 1.000000e+00)',
             '  %rb_of_v1 = fmul fast float %rb_of_r, %rb_of_ratio1','  %rb_of_v2 = fmul fast float %rb_of_r, %rb_of_ratio2']
    for i in range(3):rows += [f'  %rb_of_final{i} = select i1 {own}, float '+('%rb_of_r' if i==0 else f'%rb_of_v{i}')+f', float %rb_of_raw{i}']
    at=text.index('  %rbw_b0 =');edited=text[:at]+'\n'.join(rows)+'\n'+text[at:]
    for i in range(3):
        old=f'  %rbw_b{i} = fmul fast float %rbw_strength, %rbw_g{i}';assert edited.count(old)==1
        edited=edited.replace(old,f'  %rbw_b{i} = fadd fast float %rb_of_final{i}, 0.000000e+00')
    reversed='\n'.join(x for x in edited.splitlines() if not x.startswith('  %rb_of_'))+'\n'
    for i in range(3):reversed=reversed.replace(f'  %rbw_b{i} = fadd fast float %rb_of_final{i}, 0.000000e+00',f'  %rbw_b{i} = fmul fast float %rbw_strength, %rbw_g{i}')
    assert reversed==text
    edited,_=declarations(edited,text)
    return edited,dict(kind='wound',leaves=['%rbw_g0','%rbw_g1','%rbw_g2','%rbw_strength'],rgb=['%rbw_g0','%rbw_g1','%rbw_g2'],added_prefix='rb_of_',outputs=[f'%rb_of_final{i}' for i in range(3)],native_mask_disabled_normals_AO_motion='UNCHANGED',all_other_code_restored=True)


def hdr(text,coefficients,gamma):
    hits=stores(text)
    # Deferred multi-target programs are handled separately; depth-only/debug
    # programs with no authored colour contribution must remain native.
    if len(hits)!=3 or re.search(r'^; SV_Target\s+[1-9]',text,re.M) or len({h[2] for h in hits})!=3:return text,None
    if 'loadInput.f32' not in text and '%rb_diffuse_' not in text and '%rb_green_' not in text and 'c_material_exports' not in text:return text,None
    nodes=[h[2] for h in hits];rows=[]
    def add(name,expr):rows.append(f'  %rb_oh_{name} = {expr}');return '%rb_oh_'+name
    lo=add('lo',f'call float @dx.op.binary.f32(i32 36, float {nodes[0]}, float {nodes[1]})')
    neutral=add('neutral',f'call float @dx.op.binary.f32(i32 36, float {lo}, float {nodes[2]})')
    hi=add('hi',f'call float @dx.op.binary.f32(i32 35, float {nodes[0]}, float {nodes[1]})')
    hi=add('max',f'call float @dx.op.binary.f32(i32 35, float {hi}, float {nodes[2]})')
    peak=add('peak',f'fsub fast float {hi}, {neutral}')
    a,b,c,d,e=map(fp,coefficients)
    na=add('na',f'fmul fast float {peak}, {a}');nb=add('nb',f'fadd fast float {na}, {b}');num=add('num',f'fmul fast float {peak}, {nb}')
    dc=add('dc',f'fmul fast float {peak}, {c}');dd=add('dd',f'fadd fast float {dc}, {d}');de=add('de',f'fmul fast float {peak}, {dd}');den=add('den',f'fadd fast float {de}, {e}')
    tt=add('t0',f'fdiv fast float {num}, {den}');tt=add('tone',f'call float @dx.op.unary.f32(i32 7, float {tt})')
    values=[hi]
    for i in (1,2):
        y=add(f'y{i}',f'fmul fast float {tt}, {fp(REFERENCE[i]**(1/gamma))}')
        cy=add(f'cy{i}',f'fmul fast float {y}, {c}');aa=add(f'a{i}',f'fsub fast float {a}, {cy}');dy=add(f'dy{i}',f'fmul fast float {y}, {d}');bb=add(f'b{i}',f'fsub fast float {b}, {dy}')
        bb2=add(f'bb{i}',f'fmul fast float {bb}, {bb}');ey=add(f'ey{i}',f'fmul fast float {y}, {e}');ae=add(f'ae{i}',f'fmul fast float {aa}, {ey}');four=add(f'four{i}',f'fmul fast float {ae}, 4.000000e+00')
        disc=add(f'disc{i}',f'fadd fast float {bb2}, {four}');sq=add(f'sqrt{i}',f'call float @dx.op.unary.f32(i32 24, float {disc})');div=add(f'div{i}',f'fadd fast float {sq}, {bb}');ey2=add(f'ey2_{i}',f'fmul fast float {ey}, 2.000000e+00')
        inv=add(f'inv{i}',f'fdiv fast float {ey2}, {div}');values.append(add(f'final{i}',f'fadd fast float {inv}, {neutral}'))
    at=text.index('  call void @dx.op.storeOutput.f32');edited=text[:at]+'\n'.join(rows)+'\n'+text[at:]
    for i,hit in enumerate(hits):edited=edited.replace(hit[0],hit[0].replace('float '+nodes[i]+')','float '+values[i]+')'),1)
    reversed='\n'.join(x for x in edited.splitlines() if not x.startswith('  %rb_oh_'))+'\n'
    for i,node in enumerate(nodes):reversed=reversed.replace('float '+values[i]+')','float '+node+')')
    assert reversed==text
    edited,_=declarations(edited,text)
    return edited,dict(kind='hdr',leaves=nodes,added_prefix='rb_oh_',outputs=values,neutral_white_and_peak_preserved=True,zero_input_zero_output=True,alpha_depth_geometry_unchanged=True,reference_display_RGB=REFERENCE)

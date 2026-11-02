"""Bound only the final sampled diffuse illumination of private blood sprites.

Three max operations, no additive emission, unchanged native alpha/fog/specular.
This is a visibility policy for weak illumination, not a measured cause of a
particular user's regression. Native programs with no light RGB stay untouched.
"""
import re

FLOOR = 0.25
PREFIX = 'rb_air_light'


def definitions(text):
    return {m[1]:m[2].split(';')[0].strip()
            for m in re.finditer(r'^  (%[\w.]+) = (.+)$', text, re.M)}


def validate_dependencies(text, nodes):
    defs = definitions(text)
    memo = {}
    def depends(node):
        if node in nodes:
            return True
        if node in memo:
            return memo[node]
        memo[node] = False
        memo[node] = any(depends(n) for n in re.findall(r'%[\w.]+', defs.get(node, '')))
        return memo[node]
    affected = []
    for line in text.splitlines():
        if 'call void @dx.op.storeOutput' in line:
            m = re.search(r'storeOutput.f32\(i32 5, i32 (\d+), i32 0, i8 ([0-3]), float (%[\w.]+)\)', line)
            if m and depends(m[3]):
                assert int(m[1]) == 0 and int(m[2]) < 3, 'Illumination affects protected output'
                affected.append(int(m[2]))
        elif re.match(r'\s*(br |switch |call void )', line):
            assert not any(depends(n) for n in re.findall(r'%[\w.]+', line)), 'Illumination affects control/side effect'
    assert sorted(affected) == [0, 1, 2], affected


def patch(text):
    assert PREFIX not in text
    samples = list(re.finditer(r'^  (%[\w.]+) = call %dx.types.ResRet.f32 @dx.op.sampleLevel.f32\([^\n]+', text, re.M))
    if not samples:
        return text, None
    sample = samples[-1][1]
    rows = list(re.finditer(r'^  (%[\w.]+) = extractvalue %dx.types.ResRet.f32 '+re.escape(sample)+r', ([0-3])[^\n]*', text, re.M))
    if [m[2] for m in rows] != ['0','1','2']:
        # Native debug/auxiliary permutations sample a scalar mask, not light.
        return text, None
    nodes = [m[1] for m in rows]
    validate_dependencies(text, nodes)
    split = rows[-1].end()
    before, after = text[:split], text[split:]
    for index, node in enumerate(nodes):
        after = re.sub(re.escape(node)+r'(?![\w.])', '%'+PREFIX+str(index), after)
    added = '\n'+'\n'.join(f'  %{PREFIX}{i} = call float @dx.op.binary.f32(i32 35, float {node}, float 2.500000e-01)' for i,node in enumerate(nodes))
    edited = before+added+after
    declaration = ''
    if 'declare float @dx.op.binary.f32' not in text:
        declaration = 'declare float @dx.op.binary.f32(i32, float, float) #0\n\n'
        assert 'attributes #0 =' in edited
        edited = edited.replace('attributes #0 =', declaration+'attributes #0 =', 1)
    # Remove the inserted guard and reverse just its consumers: everything else
    # must be literally the original disassembly, including protected stores.
    reversed_text = edited.replace(added, '', 1)
    if declaration:
        reversed_text = reversed_text.replace(declaration, '', 1)
    for i, node in enumerate(nodes):
        reversed_text = reversed_text.replace('%'+PREFIX+str(i), node)
    assert reversed_text == text
    validate_dependencies(edited, ['%'+PREFIX+str(i) for i in range(3)])
    return edited, dict(light_nodes=nodes, floor=FLOOR, added_max_operations=3,
                        protected_alpha_fog_specular_geometry_controls_preserved=True)


def verify_saved(text, guard):
    defs = definitions(text)
    for i, source in enumerate(guard['light_nodes']):
        assert defs['%'+PREFIX+str(i)] == f'call float @dx.op.binary.f32(i32 35, float {source}, float 2.500000e-01)'
    validate_dependencies(text, ['%'+PREFIX+str(i) for i in range(3)])
    return dict(saved_three_max_operations_exact=True, protected_output_dependency_check=True,
                weak_light_raised_to=FLOOR, light_at_or_above_floor_unchanged=True,
                additive_emission_added=False)
